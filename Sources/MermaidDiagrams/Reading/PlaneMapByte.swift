/**
 * File: PlaneMapByte.swift
 * ------------------------
 * Layer: Core
 * Description: The bytes and classes of bytes the readers of the diagrams drawn on a fixed plane (Venn diagrams, Cynefin
 *              frameworks, Wardley maps) test, as Pele's lexers test UTF-16 code units.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 19/11/2026
 */

/// The bytes the Venn, Cynefin and Wardley readers test, and their classes as Pele's `util/chars.ts` defines them, on
/// ASCII: every byte of a character beyond ASCII is none of them, as Pele's tests are on ASCII code units but `isSpace`.
enum PlaneMapByte {
    static let tab = UInt8(ascii: "\t")
    static let lineFeed = UInt8(ascii: "\n")
    static let carriageReturn = UInt8(ascii: "\r")
    static let space = UInt8(ascii: " ")
    static let quotationMark = UInt8(ascii: "\"")
    static let apostrophe = UInt8(ascii: "'")
    static let hash = UInt8(ascii: "#")
    static let percent = UInt8(ascii: "%")
    static let ampersand = UInt8(ascii: "&")
    static let openingParenthesis = UInt8(ascii: "(")
    static let closingParenthesis = UInt8(ascii: ")")
    static let plus = UInt8(ascii: "+")
    static let comma = UInt8(ascii: ",")
    static let hyphen = UInt8(ascii: "-")
    static let period = UInt8(ascii: ".")
    static let slash = UInt8(ascii: "/")
    static let colon = UInt8(ascii: ":")
    static let semicolon = UInt8(ascii: ";")
    static let lessThan = UInt8(ascii: "<")
    static let greaterThan = UInt8(ascii: ">")
    static let atSign = UInt8(ascii: "@")
    static let openingBracket = UInt8(ascii: "[")
    static let backslash = UInt8(ascii: "\\")
    static let closingBracket = UInt8(ascii: "]")
    static let underscore = UInt8(ascii: "_")
    static let openingBrace = UInt8(ascii: "{")
    static let closingBrace = UInt8(ascii: "}")

    /// A space or a tab.
    static func isBlank(_ byte: UInt8) -> Bool {
        byte == space || byte == tab
    }

    /// White space as `\s` sees it on ASCII: a space, a tab, a line feed, a vertical tab, a form feed, a carriage return.
    static func isSpace(_ byte: UInt8) -> Bool {
        byte == space || (byte >= tab && byte <= carriageReturn)
    }

    /// A line feed or a carriage return.
    static func isLineBreak(_ byte: UInt8) -> Bool {
        byte == lineFeed || byte == carriageReturn
    }

    static func isDigit(_ byte: UInt8) -> Bool {
        byte >= UInt8(ascii: "0") && byte <= UInt8(ascii: "9")
    }

    static func isLetter(_ byte: UInt8) -> Bool {
        (byte >= UInt8(ascii: "a") && byte <= UInt8(ascii: "z")) || (byte >= UInt8(ascii: "A") && byte <= UInt8(ascii: "Z"))
    }

    static func isHexadecimalDigit(_ byte: UInt8) -> Bool {
        isDigit(byte) || (byte >= UInt8(ascii: "a") && byte <= UInt8(ascii: "f")) || (byte >= UInt8(ascii: "A") && byte <= UInt8(ascii: "F"))
    }

    /// A character of `\w`: a letter, a digit or an underscore.
    static func isWord(_ byte: UInt8) -> Bool {
        isLetter(byte) || isDigit(byte) || byte == underscore
    }

    static func lowercased(_ byte: UInt8) -> UInt8 {
        byte >= UInt8(ascii: "A") && byte <= UInt8(ascii: "Z") ? byte + 32 : byte
    }

    /// The 1-based line of the byte at `offset`: one more than the line feeds before it.
    static func line(of offset: Int, in bytes: [UInt8]) -> Int {
        1 + bytes[..<min(max(offset, 0), bytes.count)].reduce(0) { count, byte in byte == lineFeed ? count + 1 : count }
    }

    /// The first characters at `offset` up to its line's end, for an error that shows what could not be read.
    static func excerpt(at offset: Int, in bytes: [UInt8]) -> String {
        var cursor = MermaidTextCursor(bytes: bytes)
        cursor.advance(by: offset)
        return cursor.excerpt()
    }
}
