/**
 * File: SequenceAttributesScalarSyntax.swift
 * ------------------------------------------
 * Layer: Core
 * Description: Reads YAML's plain scalars with the JSON schema (null, Booleans, numbers, text) and a double-quoted
 *              scalar's escapes, as Pele's small YAML reader does.
 *
 * Authors: Bahey Shalash
 * Version: 0.2
 * Date: 23/11/2026
 */

import Foundation

/// The scalars of a participant's attributes, as Pele's YAML reader reads them.
enum SequenceAttributesScalarSyntax {
    typealias Text = [Unicode.Scalar]

    /// A plain scalar: `~`, `null` and the empty text are null, `true` and `false` (also capitalized or in capitals)
    /// Booleans, decimal, hexadecimal (`0x`), octal (`0o`) and binary (`0b`) numbers, `.inf` and `.nan` numbers, and
    /// anything else text.
    static func scalar(_ raw: String) -> SequenceAttributeValue {
        let scalars = raw.unicodeScalars
        let isTrimmed = scalars.first.map { first in !SequenceAttributesFlowSyntax.isTrimmed(first) } ?? true
            && scalars.last.map { last in !SequenceAttributesFlowSyntax.isTrimmed(last) } ?? true
        let text = isTrimmed ? raw : SequenceAttributesFlowSyntax.string(SequenceAttributesFlowSyntax.trimmed(scalars))
        switch text {
        case "", "~", "null", "Null", "NULL": return .null
        case "true", "True", "TRUE": return .boolean(true)
        case "false", "False", "FALSE": return .boolean(false)
        default: break
        }
        guard let first = text.unicodeScalars.first, first == "-" || first == "+" || first == "." || ("0"..."9").contains(first) else { return .text(text) }
        if isDecimal(text), let number = Double(text) { return .number(number) }
        let isNegative = first == "-"
        let unsigned = first == "-" || first == "+" ? String(text.dropFirst()) : text
        for (prefix, radix, digits) in [("0x", 16, "0123456789abcdefABCDEF"), ("0o", 8, "01234567"), ("0b", 2, "01")] where unsigned.hasPrefix(prefix) {
            let body = unsigned.dropFirst(2)
            guard !body.isEmpty, body.allSatisfy({ character in digits.contains(character) }) else { break }
            let magnitude = body.reduce(0.0) { value, digit in value * Double(radix) + Double(Int(String(digit), radix: radix) ?? 0) }
            return .number(isNegative ? -magnitude : magnitude)
        }
        if [".inf", ".Inf", ".INF"].contains(unsigned) { return .number(isNegative ? -Double.infinity : Double.infinity) }
        if [".nan", ".NaN", ".NAN"].contains(text) { return .number(Double.nan) }
        return .text(text)
    }

    /// A decimal number of the JSON schema: a sign, digits with a fraction (or a fraction alone), and an exponent.
    private static func isDecimal(_ text: String) -> Bool {
        var scalars = text.unicodeScalars[...]
        if let sign = scalars.first, sign == "-" || sign == "+" { scalars = scalars.dropFirst() }
        let wholeDigits = scalars.prefix { scalar in ("0"..."9").contains(scalar) }.count
        scalars = scalars.dropFirst(wholeDigits)
        var fractionDigits = 0
        if scalars.first == "." {
            scalars = scalars.dropFirst()
            fractionDigits = scalars.prefix { scalar in ("0"..."9").contains(scalar) }.count
            scalars = scalars.dropFirst(fractionDigits)
            guard wholeDigits > 0 || fractionDigits > 0 else { return false }
        } else if wholeDigits == 0 {
            return false
        }
        if let marker = scalars.first, marker == "e" || marker == "E" {
            scalars = scalars.dropFirst()
            if let sign = scalars.first, sign == "-" || sign == "+" { scalars = scalars.dropFirst() }
            let exponentDigits = scalars.prefix { scalar in ("0"..."9").contains(scalar) }.count
            guard exponentDigits > 0 else { return false }
            scalars = scalars.dropFirst(exponentDigits)
        }
        return scalars.isEmpty
    }

    /// A double-quoted body without its escaped line breaks: a backslash, a line break and the blanks after it.
    static func removingEscapedLineBreaks(_ body: Text) -> Text {
        var result: Text = []
        var index = 0
        while index < body.count {
            if body[index] == "\\", index + 1 < body.count, body[index + 1] == "\n" {
                index += 2
                while index < body.count, body[index] == " " || body[index] == "\t" { index += 1 }
                continue
            }
            result.append(body[index])
            index += 1
        }
        return result
    }

    /// The scalars an escape stands for, its letter at `index` just after the backslash, and how many scalars it takes:
    /// `\x` with two hexadecimal digits, `\u` with four, `\U` with eight, or one of YAML's letters. Any other is invalid.
    static func escape(_ text: Text, at index: Int) throws(SequenceAttributesYAMLFailure) -> (Text, Int) {
        let letter = text[index]
        let hexadecimalLength: Int? = switch letter {
        case "x": 2
        case "u": 4
        case "U": 8
        default: nil
        }
        if let hexadecimalLength {
            let digits = text[(index + 1)..<min(text.count, index + 1 + hexadecimalLength)].prefix { scalar in scalar.properties.isASCIIHexDigit }
            guard !digits.isEmpty, let value = UInt32(UnicodeScalarText.string(digits), radix: 16), value <= 0x10FFFF else { throw .invalid }
            return ([Unicode.Scalar(value) ?? "\u{FFFD}"], 1 + hexadecimalLength)
        }
        guard let replacement = escapes[letter] else { throw .invalid }
        return ([replacement], 1)
    }

    private static let escapes: [Unicode.Scalar: Unicode.Scalar] = [
        "0": "\u{0}", "a": "\u{7}", "b": "\u{8}", "t": "\t", "n": "\n", "v": "\u{B}", "f": "\u{C}", "r": "\r", "e": "\u{1B}", " ": " ",
        "\"": "\"", "/": "/", "\\": "\\", "N": "\u{85}", "_": "\u{A0}", "L": "\u{2028}", "P": "\u{2029}",
    ]
}
