/**
 * File: UseCaseCharacters.swift
 * -----------------------------
 * Layer: Core
 * Description: The classes of UTF-16 code units Mermaid's use case lexer tells apart, and what it reads of a text by
 *              them: word characters, punctuation, blanks, line breaks and keywords.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 19/11/2026
 */

/// The code units of a use case diagram's text as Pele's lexer reads them with `charCodeAt`: past the end of the text
/// a read is nil, which is in no class.
struct UseCaseCharacters {
    let units: [UInt16]

    subscript(index: Int) -> UInt16? { index >= 0 && index < units.count ? units[index] : nil }

    var count: Int { units.count }

    /// `[A-Za-z0-9_]`.
    static func isWord(_ unit: UInt16?) -> Bool {
        guard let unit else { return false }
        return isDigit(unit) || isLetter(unit) || unit == 0x5F
    }

    /// The punctuation a style may hold: `!#$&*+/=?^|~`.
    static func isCSSPunctuation(_ unit: UInt16) -> Bool {
        [0x21, 0x23, 0x24, 0x26, 0x2A, 0x2B, 0x2F, 0x3D, 0x3F, 0x5E, 0x7C, 0x7E].contains(unit)
    }

    static func isBlank(_ unit: UInt16?) -> Bool { unit == 0x20 || unit == 0x09 }

    static func isLineBreak(_ unit: UInt16?) -> Bool { unit == 0x0A || unit == 0x0D }

    static func isDigit(_ unit: UInt16?) -> Bool {
        guard let unit else { return false }
        return unit >= 0x30 && unit <= 0x39
    }

    static func isLetter(_ unit: UInt16?) -> Bool {
        guard let unit else { return false }
        return (unit >= 0x41 && unit <= 0x5A) || (unit >= 0x61 && unit <= 0x7A)
    }

    static func isHexadecimal(_ unit: UInt16?) -> Bool {
        guard let unit else { return false }
        return isDigit(unit) || (unit >= 0x41 && unit <= 0x46) || (unit >= 0x61 && unit <= 0x66)
    }

    /// JavaScript's whitespace (`\s`, what `trim()` takes away) as one code unit.
    static func isJavaScriptWhitespace(_ unit: UInt16) -> Bool {
        switch unit {
        case 0x09...0x0D, 0x20, 0xA0, 0x1680, 0x2000...0x200A, 0x2028, 0x2029, 0x202F, 0x205F, 0x3000, 0xFEFF: true
        default: false
        }
    }

    /// `text` without JavaScript's whitespace at its ends, as `trim()` gives it.
    static func trimmed(_ text: String) -> String {
        let units = Array(text.utf16)
        guard let first = units.firstIndex(where: { unit in !isJavaScriptWhitespace(unit) }),
              let last = units.lastIndex(where: { unit in !isJavaScriptWhitespace(unit) }) else { return "" }
        return String(decoding: units[first...last], as: UTF16.self)
    }

    /// Whether the text at `index` starts with `word`, exactly or, for `include` and `extend`, in any case.
    func starts(with word: String, at index: Int, ignoringCase: Bool = false) -> Bool {
        var position = index
        for expected in word.utf16 {
            guard let unit = self[position] else { return false }
            if ignoringCase ? unit | 0x20 != expected : unit != expected { return false }
            position += 1
        }
        return true
    }

    /// The text between two offsets.
    func text(from start: Int, to end: Int) -> String {
        String(decoding: units[max(0, start)..<min(units.count, max(start, end))], as: UTF16.self)
    }

    /// The first offset from `index` where the line ends, or the end of the text.
    func lineEnd(from index: Int) -> Int {
        var position = index
        while position < units.count, !Self.isLineBreak(units[position]) { position += 1 }
        return position
    }

    /// The keyword the text at `index` starts with, tried in the order of Mermaid's token list; `.end` for none.
    func keyword(at index: Int) -> UseCaseTokenKind {
        switch self[index] {
        case UInt16(ascii: "a"): starts(with: "actor", at: index) ? .actor : .end
        case UInt16(ascii: "s"): starts(with: "systemBoundary", at: index) ? .systemBoundary : starts(with: "style", at: index) ? .style : .end
        case UInt16(ascii: "e"): starts(with: "end", at: index) ? .endKeyword : starts(with: "extend", at: index, ignoringCase: true) ? .extend : .end
        case UInt16(ascii: "E"): starts(with: "extend", at: index, ignoringCase: true) ? .extend : .end
        case UInt16(ascii: "d"): starts(with: "direction", at: index) ? .direction : .end
        case UInt16(ascii: "T"): starts(with: "TD", at: index) ? .topDown : starts(with: "TB", at: index) ? .topBottom : .end
        case UInt16(ascii: "B"): starts(with: "BT", at: index) ? .bottomTop : .end
        case UInt16(ascii: "L"): starts(with: "LR", at: index) ? .leftRight : .end
        case UInt16(ascii: "R"): starts(with: "RL", at: index) ? .rightLeft : .end
        case UInt16(ascii: "n"): starts(with: "note", at: index) ? .note : .end
        case UInt16(ascii: "f"): starts(with: "for", at: index) ? .forKeyword : starts(with: "false", at: index) ? .falseKeyword : .end
        case UInt16(ascii: "j"): starts(with: "json", at: index) ? .json : .end
        case UInt16(ascii: "c"): starts(with: "classDef", at: index) ? .classDefinition : starts(with: "class", at: index) ? .classKeyword : .end
        case UInt16(ascii: "i"), UInt16(ascii: "I"): starts(with: "include", at: index, ignoringCase: true) ? .include : .end
        case UInt16(ascii: "t"): starts(with: "true", at: index) ? .trueKeyword : .end
        case UInt16(ascii: "u"): starts(with: "usecase-beta", at: index) ? .useCase : .end
        default: .end
        }
    }

    /// The 1-based line of `offset`, counting a line feed, a carriage return, or both together, as one line break.
    func line(of offset: Int) -> Int {
        var line = 1
        var index = 0
        let end = min(offset, units.count)
        while index < end {
            let unit = units[index]
            if unit == 0x0D, index + 1 < end, units[index + 1] == 0x0A { index += 1 }
            if unit == 0x0A || unit == 0x0D { line += 1 }
            index += 1
        }
        return line
    }

    /// The 1-based column of `offset` on its line.
    func column(of offset: Int) -> Int {
        var start = min(offset, units.count)
        while start > 0, !Self.isLineBreak(units[start - 1]) { start -= 1 }
        return offset - start + 1
    }
}

extension UInt16 {
    /// The code unit of an ASCII character, as `UInt8(ascii:)` gives its byte.
    init(ascii scalar: Unicode.Scalar) {
        self = UInt16(truncatingIfNeeded: scalar.value)
    }
}
