/**
 * File: RadarChartWords.swift
 * ---------------------------
 * Layer: Core
 * Description: The words and numbers of a radar chart's text, as Mermaid's lexer tells them apart, told on the bytes
 *              at the cursor: a word's String is made only for a name the chart keeps.
 *
 * Authors: Bahey Shalash
 * Version: 0.2
 * Date: 25/11/2026
 */

/// The words of a radar chart's grammar and how a name and a number are told from them. A name is a run of ASCII letters,
/// digits, underscores and hyphens that ends in a letter, digit or underscore; the lexer takes the longest, so `axes` is a
/// name and not `axis`, and a word the grammar keeps, alone, is that word and never a name.
enum RadarChartWords {
    /// A word the grammar keeps: no axis or curve is named one of them.
    enum KeptWord {
        case axis
        case curve
        case showLegend
        case ticks
        case max
        case min
        case graticule
        case title
        case `true`
        case `false`
        case circle
        case polygon

        /// Whether the word starts an option.
        var startsOption: Bool {
            switch self {
            case .showLegend, .ticks, .max, .min, .graticule: true
            default: false
            }
        }
    }

    /// The longest name at the cursor and the word the grammar keeps it is, if it is one; nil when none starts there.
    struct Word {
        /// Its length in bytes.
        let length: Int
        let kept: KeptWord?
        /// Whether it starts with a digit, and so is read as a number first.
        let startsWithDigit: Bool

        /// Whether it can name an axis, a curve or an entry's axis: it starts with a letter or an underscore and is not a
        /// kept word.
        var isName: Bool { !startsWithDigit && kept == nil }
    }

    /// The longest name at the cursor, told on its bytes, or nil when none starts there.
    static func word(in cursor: MermaidTextCursor) -> Word? {
        guard let first = cursor.peek(), isWordByte(first) else { return nil }
        var end = 0
        var lastWordEnd = 0
        while let byte = cursor.peek(end), isWordByte(byte) || byte == MermaidByte.hyphen {
            end += 1
            if byte != MermaidByte.hyphen { lastWordEnd = end }
        }
        guard lastWordEnd > 0 else { return nil }
        return Word(length: lastWordEnd, kept: keptWord(in: cursor, length: lastWordEnd), startsWithDigit: MermaidByte.isDigit(first))
    }

    /// The kept word the `length` bytes at the cursor are, compared by their length and bytes.
    private static func keptWord(in cursor: MermaidTextCursor, length: Int) -> KeptWord? {
        switch length {
        case 3: return isWritten("max", in: cursor) ? .max : isWritten("min", in: cursor) ? .min : nil
        case 4: return isWritten("axis", in: cursor) ? .axis : isWritten("true", in: cursor) ? .true : nil
        case 5:
            if isWritten("curve", in: cursor) { return .curve }
            if isWritten("ticks", in: cursor) { return .ticks }
            if isWritten("title", in: cursor) { return .title }
            return isWritten("false", in: cursor) ? .false : nil
        case 6: return isWritten("circle", in: cursor) ? .circle : nil
        case 7: return isWritten("polygon", in: cursor) ? .polygon : nil
        case 9: return isWritten("graticule", in: cursor) ? .graticule : nil
        case 10: return isWritten("showLegend", in: cursor) ? .showLegend : nil
        default: return nil
        }
    }

    /// Whether the bytes at the cursor start with `word`'s.
    static func isWritten(_ word: StaticString, in cursor: MermaidTextCursor) -> Bool {
        let bytes = word.utf8Start
        for offset in 0..<word.utf8CodeUnitCount where cursor.peek(offset) != bytes[offset] { return false }
        return true
    }

    private static func isWordByte(_ byte: UInt8) -> Bool {
        MermaidByte.isLetter(byte) || MermaidByte.isDigit(byte) || byte == MermaidByte.underscore
    }

    /// A number as the lexer reads one, and moves past it: digits, or digits, a `.` and digits; a `0` that is followed by
    /// more digits is a number of its own. Nil, with the cursor where it was, when none starts there or a `.` follows it.
    static func number(at cursor: inout MermaidTextCursor) -> Double? {
        let start = cursor.position
        var end = 0
        while let byte = cursor.peek(end), MermaidByte.isDigit(byte) { end += 1 }
        guard end > 0 else { return nil }
        if cursor.peek(end) == MermaidByte.period {
            end += 1
            let fractionStart = end
            while let byte = cursor.peek(end), MermaidByte.isDigit(byte) { end += 1 }
            guard end > fractionStart else { return nil }
        } else if cursor.bytes[start] == UInt8(ascii: "0") {
            end = 1
        }
        guard cursor.peek(end) != MermaidByte.period,
              let value = ChartDecimalText.value(of: cursor.bytes, from: start, to: start + end) ?? Double(cursor.text(from: start, to: start + end)) else {
            return nil
        }
        cursor.advance(by: end)
        return value
    }
}
