/**
 * File: JavaScriptDateScanner.swift
 * ---------------------------------
 * Layer: Core
 * Description: The tokens of a date text as V8's legacy date parser scans them: numbers, keywords, signs and symbols.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 19/11/2026
 */

/// A token of a date text.
enum JavaScriptDateToken: Equatable {
    /// A run of digits: its value (from its first nine digits) and how many digits it has.
    case number(value: Int64, length: Int)
    case keyword(JavaScriptDateKeyword)
    /// `+` (1) or `-` (-1).
    case sign(Int64)
    case symbol(UInt16)
    case whitespace
    /// Text in parentheses, which is skipped.
    case unknown
    case end
}

/// A word of a date text, by its first three letters.
enum JavaScriptDateKeyword: Equatable {
    case month(Int64)
    /// `AM` (0) or `PM` (12): the hours to add.
    case amPm(Int64)
    case zone(hours: Int64)
    case timeSeparator
    /// Any other word: ignored before the first number, an error after it.
    case garbage
}

/// Scans a date text, by its UTF-16 code units as V8 does.
struct JavaScriptDateScanner {
    private let units: [UInt16]
    private var position = 0

    /// A number's value is made from its first nine digits.
    static let maximumSignificantDigits = 9
    private static let months = ["jan", "feb", "mar", "apr", "may", "jun", "jul", "aug", "sep", "oct", "nov", "dec"]
    private static let zones: [String: Int64] = ["ut": 0, "utc": 0, "z": 0, "gmt": 0, "cdt": -5, "cst": -6, "edt": -4, "est": -5, "mdt": -6, "mst": -7,
                                                 "pdt": -7, "pst": -8]

    init(text: String) {
        units = Array(text.utf16)
    }

    private func peekUnit() -> UInt16? {
        position < units.count ? units[position] : nil
    }

    private static func isDigit(_ unit: UInt16) -> Bool {
        unit >= 48 && unit <= 57
    }

    /// A word's character: V8 takes every character from `A` up, letters of any script included.
    private static func isWordUnit(_ unit: UInt16) -> Bool {
        unit >= 65
    }

    private static func isWhitespace(_ unit: UInt16) -> Bool {
        unit == 32 || (unit >= 9 && unit <= 13) || unit == 0xA0 || unit == 0x1680 || (0x2000...0x200A).contains(unit) || unit == 0x2028 || unit == 0x2029
            || unit == 0x202F || unit == 0x205F || unit == 0x3000 || unit == 0xFEFF
    }

    /// The next token, as V8's tokenizer scans it.
    mutating func next() -> JavaScriptDateToken {
        guard let unit = peekUnit() else { return .end }
        if Self.isDigit(unit) { return readNumber() }
        if Self.isWordUnit(unit) { return .keyword(readWord()) }
        if Self.isWhitespace(unit) {
            while let space = peekUnit(), Self.isWhitespace(space) { position += 1 }
            return .whitespace
        }
        if unit == 40 { return skipParentheses() }
        position += 1
        if unit == 43 { return .sign(1) }
        if unit == 45 { return .sign(-1) }
        return .symbol(unit)
    }

    /// The next token, which stays to be read.
    func peek() -> JavaScriptDateToken {
        var lookahead = self
        return lookahead.next()
    }

    /// Skips the symbol `unit` when it is next, and says whether it was.
    mutating func skipSymbol(_ unit: UInt16) -> Bool {
        guard peek() == .symbol(unit) else { return false }
        _ = next()
        return true
    }

    private mutating func readNumber() -> JavaScriptDateToken {
        var value: Int64 = 0
        var length = 0
        while let digit = peekUnit(), Self.isDigit(digit) {
            if length < Self.maximumSignificantDigits { value = value * 10 + Int64(digit - 48) }
            length += 1
            position += 1
        }
        return .number(value: value, length: length)
    }

    /// Text in parentheses, to its match.
    private mutating func skipParentheses() -> JavaScriptDateToken {
        var depth = 0
        while let character = peekUnit() {
            position += 1
            if character == 40 { depth += 1 } else if character == 41 { depth -= 1 }
            if depth == 0 { break }
        }
        return .unknown
    }

    private mutating func readWord() -> JavaScriptDateKeyword {
        var prefix: [UInt16] = []
        var length = 0
        while let unit = peekUnit(), Self.isWordUnit(unit) {
            if prefix.count < 3 { prefix.append(unit >= 65 && unit <= 90 ? unit + 32 : unit) }
            length += 1
            position += 1
        }
        let word = String(decoding: prefix, as: UTF16.self)
        // A word longer than three letters is only a month name.
        if prefix.count == 3, let index = Self.months.firstIndex(of: word) { return .month(Int64(index + 1)) }
        guard length <= 3 else { return .garbage }
        switch word {
        case "am": return .amPm(0)
        case "pm": return .amPm(12)
        case "t": return .timeSeparator
        default: return Self.zones[word].map { hours in .zone(hours: hours) } ?? .garbage
        }
    }
}
