/**
 * File: ReferenceRadarChartWords.swift
 * ------------------------------------
 * Layer: Tests
 * Description: 0.7.0's RadarChartWords, frozen as main de81532 had it, which the radar chart reader is compared with.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 25/11/2026
 */

@testable import MermaidDiagrams

/// The words of a radar chart's grammar and how a name and a number are told from them. A name is a run of ASCII letters,
/// digits, underscores and hyphens that ends in a letter, digit or underscore; the lexer takes the longest, so `axes` is a
/// name and not `axis`, and a word the grammar keeps, alone, is that word and never a name.
enum ReferenceRadarChartWords {
    static let axis = Array("axis".utf8)
    static let curve = Array("curve".utf8)
    /// The words that start an option.
    static let options: Set<String> = ["showLegend", "ticks", "max", "min", "graticule"]
    /// Every word the grammar keeps: no axis or curve is named one of them.
    private static let kept: Set<String> = ["axis", "curve", "showLegend", "ticks", "max", "min", "graticule", "title", "true", "false", "circle", "polygon"]

    /// The longest name at the cursor, or nil when none starts there.
    static func name(in cursor: MermaidTextCursor) -> String? {
        guard let first = cursor.peek(), isWordByte(first) else { return nil }
        var end = 0
        var lastWordEnd = 0
        while let byte = cursor.peek(end), isWordByte(byte) || byte == MermaidByte.hyphen {
            end += 1
            if byte != MermaidByte.hyphen { lastWordEnd = end }
        }
        guard lastWordEnd > 0 else { return nil }
        return cursor.text(from: cursor.position, to: cursor.position + lastWordEnd)
    }

    /// Whether `word` can name an axis, a curve or an entry's axis: it starts with a letter or an underscore (one that starts
    /// with a digit is a number first) and is not a kept word.
    static func isName(_ word: String?) -> Bool {
        guard let word, let first = word.utf8.first else { return false }
        return !MermaidByte.isDigit(first) && !kept.contains(word)
    }

    private static func isWordByte(_ byte: UInt8) -> Bool {
        MermaidByte.isLetter(byte) || MermaidByte.isDigit(byte) || byte == MermaidByte.underscore
    }

    /// A number as the lexer reads one, and moves past it: digits, or digits, a `.` and digits; a `0` that is followed by
    /// more digits is a number of its own. Nil, with the cursor where it was, when none starts there or a `.` follows it.
    static func number(at cursor: inout MermaidTextCursor) -> Double? {
        var lookahead = cursor
        let start = lookahead.position
        while let byte = lookahead.peek(), MermaidByte.isDigit(byte) { lookahead.advance() }
        guard lookahead.position > start else { return nil }
        if lookahead.peek() == MermaidByte.period {
            lookahead.advance()
            let fractionStart = lookahead.position
            while let byte = lookahead.peek(), MermaidByte.isDigit(byte) { lookahead.advance() }
            guard lookahead.position > fractionStart else { return nil }
        } else if cursor.bytes[start] == UInt8(ascii: "0") {
            lookahead = cursor
            lookahead.advance()
        }
        guard lookahead.peek() != MermaidByte.period, let value = Double(lookahead.text(from: start, to: lookahead.position)) else { return nil }
        cursor = lookahead
        return value
    }
}
