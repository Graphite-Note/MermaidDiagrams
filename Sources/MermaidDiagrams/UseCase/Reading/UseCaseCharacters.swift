/**
 * File: UseCaseCharacters.swift
 * -----------------------------
 * Layer: Core
 * Description: The classes of bytes Mermaid's use case lexer tells apart (word characters, punctuation, blanks, line
 *              breaks), JavaScript's white space found in UTF-8 and in UTF-16, and `trim()` as JavaScript trims.
 *
 * Authors: Bahey Shalash
 * Version: 0.4
 * Date: 25/11/2026
 */

/// The characters Mermaid's use case lexer tells apart. Its classes are ASCII's, so a byte of UTF-8 is in one exactly
/// when the UTF-16 code unit of the same character is; a read past the end of the text is nil, which is in no class.
enum UseCaseCharacters {
    /// `[A-Za-z0-9_]`.
    @inline(__always) static func isWord(_ byte: UInt8?) -> Bool {
        guard let byte else { return false }
        return isDigit(byte) || isLetter(byte) || byte == 0x5F
    }

    /// The punctuation a style may hold: `!#$&*+/=?^|~`.
    static func isCSSPunctuation(_ byte: UInt8) -> Bool {
        switch byte {
        case 0x21, 0x23, 0x24, 0x26, 0x2A, 0x2B, 0x2F, 0x3D, 0x3F, 0x5E, 0x7C, 0x7E: true
        default: false
        }
    }

    @inline(__always) static func isBlank(_ byte: UInt8?) -> Bool { byte == 0x20 || byte == 0x09 }

    static let lineFeed: UInt8 = 0x0A

    @inline(__always) static func isLineBreak(_ byte: UInt8?) -> Bool { byte == 0x0A || byte == 0x0D }

    @inline(__always) static func isDigit(_ byte: UInt8?) -> Bool {
        guard let byte else { return false }
        return byte >= 0x30 && byte <= 0x39
    }

    @inline(__always) static func isLetter(_ byte: UInt8?) -> Bool {
        guard let byte else { return false }
        return (byte >= 0x41 && byte <= 0x5A) || (byte >= 0x61 && byte <= 0x7A)
    }

    static func isHexadecimal(_ byte: UInt8?) -> Bool {
        guard let byte else { return false }
        return isDigit(byte) || (byte >= 0x41 && byte <= 0x46) || (byte >= 0x61 && byte <= 0x66)
    }

    /// JavaScript's whitespace (`\s`, what `trim()` takes away) as one code unit.
    static func isJavaScriptWhitespace(_ unit: UInt16) -> Bool {
        switch unit {
        case 0x09...0x0D, 0x20, 0xA0, 0x1680, 0x2000...0x200A, 0x2028, 0x2029, 0x202F, 0x205F, 0x3000, 0xFEFF: true
        default: false
        }
    }

    /// The length in bytes of the character of JavaScript's whitespace that starts at `index` of `bytes`, before
    /// `end`, or 0 when none does: in UTF-8, U+00A0 takes two bytes, U+1680, U+2000 to U+200A, U+2028, U+2029, U+202F,
    /// U+205F, U+3000 and U+FEFF three.
    @inline(__always) static func javaScriptWhitespaceLength(in bytes: UnsafeBufferPointer<UInt8>, at index: Int, end: Int) -> Int {
        let byte = bytes[index]
        if byte < 0x80 { return (byte >= 0x09 && byte <= 0x0D) || byte == 0x20 ? 1 : 0 }
        guard byte == 0xC2 || byte == 0xE1 || byte == 0xE2 || byte == 0xE3 || byte == 0xEF else { return 0 }
        guard index + 1 < end else { return 0 }
        let second = bytes[index + 1]
        if byte == 0xC2 { return second == 0xA0 ? 2 : 0 }
        guard index + 2 < end else { return 0 }
        let third = bytes[index + 2]
        switch byte {
        case 0xE1: return second == 0x9A && third == 0x80 ? 3 : 0
        case 0xE2:
            if second == 0x80 { return third <= 0x8A || third == 0xA8 || third == 0xA9 || third == 0xAF ? 3 : 0 }
            return second == 0x81 && third == 0x9F ? 3 : 0
        case 0xE3: return second == 0x80 && third == 0x80 ? 3 : 0
        default: return second == 0xBB && third == 0xBF ? 3 : 0
        }
    }

    /// Whether the three bytes at `index` are U+2028 or U+2029, after which JavaScript's `^` also matches.
    @inline(__always) static func isLineOrParagraphSeparator(in bytes: UnsafeBufferPointer<UInt8>, at index: Int, end: Int) -> Bool {
        index + 2 < end && bytes[index] == 0xE2 && bytes[index + 1] == 0x80 && (bytes[index + 2] == 0xA8 || bytes[index + 2] == 0xA9)
    }

    /// `range` of `bytes` without JavaScript's whitespace at its ends, as `trim()` gives it.
    static func trimmed(_ range: MermaidTextRange, in bytes: UnsafeBufferPointer<UInt8>) -> MermaidTextRange {
        var start = range.lowerBound
        let end = range.upperBound
        while start < end {
            let length = javaScriptWhitespaceLength(in: bytes, at: start, end: end)
            guard length > 0 else { break }
            start += length
        }
        guard start < end else { return MermaidTextRange(start: start, end: start) }
        var last = end
        // A character ends where the next one starts: step back over continuation bytes to the start of the last.
        while last > start {
            var characterStart = last - 1
            while characterStart > start, bytes[characterStart] & 0xC0 == 0x80 { characterStart -= 1 }
            guard javaScriptWhitespaceLength(in: bytes, at: characterStart, end: last) == last - characterStart else { break }
            last = characterStart
        }
        return MermaidTextRange(start: start, end: last)
    }

    /// `text` without JavaScript's whitespace at its ends, as `trim()` gives it.
    static func trimmed(_ text: String) -> String {
        let units = Array(text.utf16)
        guard let first = units.firstIndex(where: { unit in !isJavaScriptWhitespace(unit) }),
              let last = units.lastIndex(where: { unit in !isJavaScriptWhitespace(unit) }) else { return "" }
        return UnicodeScalarText.string(utf16: units[first...last])
    }
}
