/**
 * File: SequenceAttributesScalarSyntax.swift
 * ------------------------------------------
 * Layer: Core
 * Description: Reads YAML's plain scalars with the JSON schema (null, Booleans, numbers, text) and a double-quoted
 *              scalar's escapes, as Pele's small YAML reader does.
 *
 * Authors: Bahey Shalash
 * Version: 0.3
 * Date: 23/11/2026
 */

import Foundation

/// The scalars of a participant's attributes, as Pele's YAML reader reads them, from their UTF-8 bytes.
enum SequenceAttributesScalarSyntax {
    /// A plain scalar: `~`, `null` and the empty text are null, `true` and `false` (also capitalized or in capitals)
    /// Booleans, decimal, hexadecimal (`0x`), octal (`0o`) and binary (`0b`) numbers, `.inf` and `.nan` numbers, and
    /// anything else text. Every spelling is ASCII, which no other text equals, even canonically.
    static func scalar<Value: MermaidYAMLValue>(_ raw: ArraySlice<UInt8>) -> Value {
        let text = raw[YAMLBytes.trimmedBounds(in: raw, raw.indices)]
        switch text.count {
        case 0: return .null
        case 1 where text.first == UInt8(ascii: "~"): return .null
        case 4 where isSpelling(text, of: nullSpellings): return .null
        case 4 where isSpelling(text, of: trueSpellings): return .boolean(true)
        case 5 where isSpelling(text, of: falseSpellings): return .boolean(false)
        default: break
        }
        guard let first = text.first, first == UInt8(ascii: "-") || first == UInt8(ascii: "+") || first == UInt8(ascii: ".") || isDigit(first) else {
            return .text(String(decoding: text, as: UTF8.self))
        }
        let written = String(decoding: text, as: UTF8.self)
        if isDecimal(text), let number = Double(written) { return .number(number) }
        let isNegative = first == UInt8(ascii: "-")
        let unsigned = first == UInt8(ascii: "-") || first == UInt8(ascii: "+") ? withoutFirstCharacter(text, written: written) : text
        if let magnitude = radixMagnitude(unsigned) { return .number(isNegative ? -magnitude : magnitude) }
        if isSpelling(unsigned, of: infinitySpellings) { return .number(isNegative ? -Double.infinity : Double.infinity) }
        if isSpelling(text, of: notANumberSpellings) { return .number(Double.nan) }
        return .text(written)
    }

    /// The text without its first character, a sign: its byte, and when a scalar beyond ASCII follows it, the scalars
    /// Swift's characters join to it (a combining mark), as `String.dropFirst` takes them.
    private static func withoutFirstCharacter(_ text: ArraySlice<UInt8>, written: String) -> ArraySlice<UInt8> {
        guard text.count > 1, text[text.startIndex + 1] >= 0x80 else { return text.dropFirst() }
        return Array(written.dropFirst().utf8)[...]
    }

    /// The value of `0x`, `0o` or `0b` and its digits; nil when the text starts with none of them, and when its digits
    /// are not all of its base (a text then).
    private static func radixMagnitude(_ unsigned: ArraySlice<UInt8>) -> Double? {
        guard unsigned.count >= 2, unsigned.first == UInt8(ascii: "0") else { return nil }
        let marker = unsigned[unsigned.startIndex + 1]
        let radix: UInt8 = switch marker {
        case UInt8(ascii: "x"): 16
        case UInt8(ascii: "o"): 8
        case UInt8(ascii: "b"): 2
        default: 0
        }
        guard radix > 0 else { return nil }
        let body = unsigned.dropFirst(2)
        var magnitude = 0.0
        for byte in body {
            guard let digit = digitValue(byte), digit < radix else { return nil }
            magnitude = magnitude * Double(radix) + Double(digit)
        }
        return body.isEmpty ? nil : magnitude
    }

    /// A digit's value in base 16 and below: `0`–`9`, `a`–`f`, `A`–`F`.
    private static func digitValue(_ byte: UInt8) -> UInt8? {
        switch byte {
        case UInt8(ascii: "0")...UInt8(ascii: "9"): byte - UInt8(ascii: "0")
        case UInt8(ascii: "a")...UInt8(ascii: "f"): byte - UInt8(ascii: "a") + 10
        case UInt8(ascii: "A")...UInt8(ascii: "F"): byte - UInt8(ascii: "A") + 10
        default: nil
        }
    }

    @inline(__always)
    private static func isDigit(_ byte: UInt8) -> Bool {
        byte >= UInt8(ascii: "0") && byte <= UInt8(ascii: "9")
    }

    private static func isSpelling(_ text: ArraySlice<UInt8>, of spellings: [[UInt8]]) -> Bool {
        spellings.contains { spelling in spelling.elementsEqual(text) }
    }

    private static let nullSpellings = ["null", "Null", "NULL"].map { spelling in Array(spelling.utf8) }
    private static let trueSpellings = ["true", "True", "TRUE"].map { spelling in Array(spelling.utf8) }
    private static let falseSpellings = ["false", "False", "FALSE"].map { spelling in Array(spelling.utf8) }
    private static let infinitySpellings = [".inf", ".Inf", ".INF"].map { spelling in Array(spelling.utf8) }
    private static let notANumberSpellings = [".nan", ".NaN", ".NAN"].map { spelling in Array(spelling.utf8) }

    /// A decimal number of the JSON schema: a sign, digits with a fraction (or a fraction alone), and an exponent.
    private static func isDecimal(_ text: ArraySlice<UInt8>) -> Bool {
        var index = text.startIndex
        func digitCount() -> Int {
            let start = index
            while index < text.endIndex, isDigit(text[index]) { index += 1 }
            return index - start
        }
        if index < text.endIndex, text[index] == UInt8(ascii: "-") || text[index] == UInt8(ascii: "+") { index += 1 }
        let wholeDigits = digitCount()
        if index < text.endIndex, text[index] == UInt8(ascii: ".") {
            index += 1
            let fractionDigits = digitCount()
            guard wholeDigits > 0 || fractionDigits > 0 else { return false }
        } else if wholeDigits == 0 {
            return false
        }
        if index < text.endIndex, text[index] == UInt8(ascii: "e") || text[index] == UInt8(ascii: "E") {
            index += 1
            if index < text.endIndex, text[index] == UInt8(ascii: "-") || text[index] == UInt8(ascii: "+") { index += 1 }
            guard digitCount() > 0 else { return false }
        }
        return index == text.endIndex
    }

    /// A double-quoted scalar's body (`range` of `bytes`) with its escapes replaced; an escaped line break and the
    /// blanks after it go first, then the line breaks are folded.
    static func unescaped(_ bytes: [UInt8], _ range: Range<Int>) throws(SequenceAttributesYAMLFailure) -> String {
        guard YAMLBytes.firstIndex(of: YAMLBytes.backslash, in: bytes, range) < range.upperBound else {
            return String(decoding: SequenceAttributesFlowSyntax.folding(bytes, range), as: UTF8.self)
        }
        let removed = removingEscapedLineBreaks(bytes[range])
        let text = Array(SequenceAttributesFlowSyntax.folding(removed, removed.indices))
        var result: [UInt8] = []
        result.reserveCapacity(text.count)
        var index = 0
        while index < text.count {
            guard text[index] == YAMLBytes.backslash else {
                result.append(text[index])
                index += 1
                continue
            }
            index += 1
            guard index < text.count else { throw .invalid }
            index = try escape(text, at: index, into: &result)
        }
        return String(decoding: result, as: UTF8.self)
    }

    /// A single-quoted scalar's folded body with each doubled apostrophe made one, as `replacingOccurrences` makes them:
    /// in the bytes when they are all ASCII, else through Foundation, whose search compares composed characters.
    static func undoublingApostrophes(_ folded: ArraySlice<UInt8>) -> String {
        guard folded.allSatisfy({ byte in byte < 0x80 }) else {
            return String(decoding: folded, as: UTF8.self).replacingOccurrences(of: "''", with: "'")
        }
        var result: [UInt8] = []
        result.reserveCapacity(folded.count)
        var index = folded.startIndex
        while index < folded.endIndex {
            result.append(folded[index])
            let isDoubled = folded[index] == YAMLBytes.apostrophe && index + 1 < folded.endIndex && folded[index + 1] == YAMLBytes.apostrophe
            index += isDoubled ? 2 : 1
        }
        return String(decoding: result, as: UTF8.self)
    }

    /// A double-quoted body without its escaped line breaks: a backslash, a line break and the blanks after it.
    private static func removingEscapedLineBreaks(_ body: ArraySlice<UInt8>) -> [UInt8] {
        var result: [UInt8] = []
        result.reserveCapacity(body.count)
        var index = body.startIndex
        while index < body.endIndex {
            if body[index] == YAMLBytes.backslash, index + 1 < body.endIndex, body[index + 1] == YAMLBytes.newline {
                index += 2
                while index < body.endIndex, body[index] == YAMLBytes.space || body[index] == YAMLBytes.tab { index += 1 }
                continue
            }
            result.append(body[index])
            index += 1
        }
        return result
    }

    /// Writes the scalar the escape whose letter is at `index`, just after the backslash, stands for, and returns where
    /// the text continues: `\x` with two hexadecimal digits, `\u` with four, `\U` with eight (the escape takes that many
    /// scalars, digits or not), or one of YAML's letters. Any other is invalid.
    private static func escape(_ text: [UInt8], at index: Int, into result: inout [UInt8]) throws(SequenceAttributesYAMLFailure) -> Int {
        let letter = text[index]
        let hexadecimalLength: Int? = switch letter {
        case UInt8(ascii: "x"): 2
        case UInt8(ascii: "u"): 4
        case UInt8(ascii: "U"): 8
        default: nil
        }
        if let hexadecimalLength {
            var value: UInt32 = 0
            var digitCount = 0
            while digitCount < hexadecimalLength, index + 1 + digitCount < text.count, let digit = digitValue(text[index + 1 + digitCount]) {
                value = value << 4 | UInt32(digit)
                digitCount += 1
            }
            guard digitCount > 0, value <= 0x10FFFF else { throw .invalid }
            appendUTF8(Unicode.Scalar(value) ?? "\u{FFFD}", to: &result)
            return YAMLBytes.passingScalars(hexadecimalLength, in: text, from: index + 1, end: text.count)
        }
        guard letter < 0x80, let replacement = escapes[Unicode.Scalar(letter)] else { throw .invalid }
        appendUTF8(replacement, to: &result)
        return index + 1
    }

    private static func appendUTF8(_ scalar: Unicode.Scalar, to result: inout [UInt8]) {
        if scalar.isASCII {
            result.append(UInt8(scalar.value))
        } else {
            if let encoded = UTF8.encode(scalar) { result.append(contentsOf: encoded) }
        }
    }

    private static let escapes: [Unicode.Scalar: Unicode.Scalar] = [
        "0": "\u{0}", "a": "\u{7}", "b": "\u{8}", "t": "\t", "n": "\n", "v": "\u{B}", "f": "\u{C}", "r": "\r", "e": "\u{1B}", " ": " ",
        "\"": "\"", "/": "/", "\\": "\\", "N": "\u{85}", "_": "\u{A0}", "L": "\u{2028}", "P": "\u{2029}",
    ]
}
