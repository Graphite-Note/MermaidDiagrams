/**
 * File: MermaidByte.swift
 * -----------------------
 * Layer: Core
 * Description: The bytes of Mermaid's syntax, the classes of bytes its readers test, and a look at a text's bytes before
 *              a search through its characters.
 *
 * Authors: Félix Chevalier, Bahey Shalash
 * Version: 0.3
 * Date: 23/11/2026
 */

import Foundation

/// The bytes of Mermaid's syntax, and the classes of bytes its readers test.
enum MermaidByte {
    static let newline = UInt8(ascii: "\n")
    static let carriageReturn = UInt8(ascii: "\r")
    static let space = UInt8(ascii: " ")
    static let exclamationMark = UInt8(ascii: "!")
    static let tab = UInt8(ascii: "\t")
    static let semicolon = UInt8(ascii: ";")
    static let colon = UInt8(ascii: ":")
    static let comma = UInt8(ascii: ",")
    static let hyphen = UInt8(ascii: "-")
    static let equals = UInt8(ascii: "=")
    static let period = UInt8(ascii: ".")
    static let tilde = UInt8(ascii: "~")
    static let lessThan = UInt8(ascii: "<")
    static let greaterThan = UInt8(ascii: ">")
    static let letterO = UInt8(ascii: "o")
    static let letterX = UInt8(ascii: "x")
    static let verticalBar = UInt8(ascii: "|")
    static let ampersand = UInt8(ascii: "&")
    static let atSign = UInt8(ascii: "@")
    static let quotationMark = UInt8(ascii: "\"")
    static let graveAccent = UInt8(ascii: "`")
    static let percent = UInt8(ascii: "%")
    static let openingBracket = UInt8(ascii: "[")
    static let closingBracket = UInt8(ascii: "]")
    static let openingBrace = UInt8(ascii: "{")
    static let closingBrace = UInt8(ascii: "}")
    static let underscore = UInt8(ascii: "_")

    static func isSpace(_ byte: UInt8) -> Bool {
        byte == space || byte == tab
    }

    /// A space, a tab, a carriage return or a line break.
    static func isWhitespace(_ byte: UInt8) -> Bool {
        isSpace(byte) || byte == newline || byte == carriageReturn
    }

    static func isLetter(_ byte: UInt8) -> Bool {
        (byte >= UInt8(ascii: "a") && byte <= UInt8(ascii: "z")) || (byte >= UInt8(ascii: "A") && byte <= UInt8(ascii: "Z"))
    }

    static func isDigit(_ byte: UInt8) -> Bool {
        byte >= UInt8(ascii: "0") && byte <= UInt8(ascii: "9")
    }

    /// A letter, a digit, an underscore, or any byte of a character beyond ASCII, so that `Étape_2` is an identifier.
    static func isIdentifierByte(_ byte: UInt8) -> Bool {
        isLetter(byte) || isDigit(byte) || byte == underscore || byte >= 0x80
    }

    static func lowercased(_ byte: UInt8) -> UInt8 {
        byte >= UInt8(ascii: "A") && byte <= UInt8(ascii: "Z") ? byte + 32 : byte
    }

    /// Whether a statement ends at this byte: a line break, a semicolon or a carriage return.
    static func endsStatement(_ byte: UInt8) -> Bool {
        byte == newline || byte == semicolon || byte == carriageReturn
    }

    /// The text split at its line feeds as `split(separator: "\n", omittingEmptySubsequences: false)` splits it at its
    /// characters: a line feed is a character of its own but after a carriage return, so text without one is cut at its
    /// bytes, straight from its storage.
    static func lines(of text: String) -> [String] {
        guard !text.utf8.contains(carriageReturn) else { return text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init) }
        var text = text
        return text.withUTF8 { bytes in
            var lines: [String] = []
            var start = 0
            for index in bytes.indices where bytes[index] == newline {
                lines.append(String(decoding: UnsafeBufferPointer(rebasing: bytes[start..<index]), as: UTF8.self))
                start = index + 1
            }
            lines.append(String(decoding: UnsafeBufferPointer(rebasing: bytes[start...]), as: UTF8.self))
            return lines
        }
    }

    /// The value without its `!important`s, in any case, as CSS's priority is dropped from a style's values; a value
    /// without an exclamation mark's byte is returned as it is, as none can be found in it.
    static func withoutImportance(_ value: String) -> String {
        guard value.utf8.contains(exclamationMark) else { return value }
        return value.replacingOccurrences(of: "!important", with: "", options: .caseInsensitive)
    }

    /// Whether the text starts and ends with a printable ASCII character other than a space: trimming white space or line
    /// breaks from either end then leaves it as it is.
    static func startsAndEndsWithPrintableASCII(_ text: String) -> Bool {
        guard let first = text.utf8.first, let last = text.utf8.last else { return false }
        return first > space && first < 0x7F && last > space && last < 0x7F
    }

    /// Whether the text's bytes hold two spaces in a row or a tab: false when its characters hold neither, so that a
    /// search through its characters can be left out.
    static func hasBlankRun(_ text: String) -> Bool {
        var previous: UInt8 = 0
        for byte in text.utf8 {
            if byte == UInt8(ascii: "\t") || (byte == space && previous == space) { return true }
            previous = byte
        }
        return false
    }
}
