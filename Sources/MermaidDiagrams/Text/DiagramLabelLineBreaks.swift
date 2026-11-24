/**
 * File: DiagramLabelLineBreaks.swift
 * ----------------------------------
 * Layer: Core
 * Description: Whether Pele reads a label's text without markup, found in its UTF-8 bytes: no tag, break, marker,
 *              icon name or code.
 *
 * Authors: Bahey Shalash
 * Version: 0.4
 * Date: 24/11/2026
 */

/// The line structure of a label's text, as Pele's text/label.ts and common/fit.ts read it.
enum DiagramLabelLineBreaks {
    /// Whether Pele lays the text whose UTF-8 is `bytes` out as one line as written, trimmed (its `RE_MARKUP` test, after
    /// `literalText` when `isLiteral`): no `<`, backslash, line break, `*`, `_` or `&`; no `ﬂ` (EF AC 82), the first
    /// character of the entity codes Pele hides; no Mermaid code (`#`, word characters, `;`), which Pele hides behind
    /// characters it then tests for; and no `:fa-` after `fa` and at most one of `bklrs` (an icon name), or after anything
    /// in literal text, which writes it `&colon;fa-`. Every character looked for is ASCII but `ﬂ`, so a byte of one is it.
    static func isUnmarked<Bytes: RandomAccessCollection<UInt8>>(_ bytes: Bytes, isLiteral: Bool) -> Bool where Bytes.Index == Int {
        let lowMarkupBytes = Self.lowMarkupBytes
        let highMarkupBytes = Self.highMarkupBytes
        var index = bytes.startIndex
        while index < bytes.endIndex {
            let byte = bytes[index]
            // Most bytes are none of those looked for, which two masks of ASCII and one comparison tell.
            let isLookedFor = byte < 64 ? (lowMarkupBytes &>> UInt64(byte)) & 1 != 0
                : byte < 128 ? (highMarkupBytes &>> UInt64(byte - 64)) & 1 != 0 : byte == 0xEF
            guard isLookedFor else {
                index += 1
                continue
            }
            switch byte {
            case UInt8(ascii: "<"), UInt8(ascii: "\\"), UInt8(ascii: "\n"), UInt8(ascii: "*"), UInt8(ascii: "_"), UInt8(ascii: "&"):
                return false
            case 0xEF:
                if index + 2 < bytes.endIndex, bytes[index + 1] == 0xAC, bytes[index + 2] == 0x82 { return false }
            case UInt8(ascii: "#"):
                var end = index + 1
                while end < bytes.endIndex, isASCIIWordCharacter(bytes[end]) { end += 1 }
                if end > index + 1, end < bytes.endIndex, bytes[end] == UInt8(ascii: ";") { return false }
            case UInt8(ascii: ":"):
                if startsIconName(in: bytes, colon: index, isLiteral: isLiteral) { return false }
            default: break
            }
            index += 1
        }
        return true
    }

    /// The bytes below 64 that `isUnmarked` looks at, as bits: line feed, `#`, `&`, `*`, `:` and `<`.
    private static let lowMarkupBytes: UInt64 = [UInt8(ascii: "\n"), UInt8(ascii: "#"), UInt8(ascii: "&"), UInt8(ascii: "*"), UInt8(ascii: ":"),
                                                 UInt8(ascii: "<")].reduce(0) { mask, byte in mask | 1 &<< UInt64(byte) }
    /// The bytes from 64 to 127 that `isUnmarked` looks at, as bits from 64: backslash and `_`.
    private static let highMarkupBytes: UInt64 = [UInt8(ascii: "\\"), UInt8(ascii: "_")].reduce(0) { mask, byte in mask | 1 &<< UInt64(byte - 64) }

    /// Whether the `:` at `colon` is followed by `fa-` and, unless `isLiteral`, comes after `fa` or `fa` and one of `bklrs`.
    private static func startsIconName<Bytes: RandomAccessCollection<UInt8>>(in bytes: Bytes, colon: Int, isLiteral: Bool) -> Bool
        where Bytes.Index == Int {
        guard colon + 3 < bytes.endIndex, bytes[colon + 1] == UInt8(ascii: "f"), bytes[colon + 2] == UInt8(ascii: "a"),
              bytes[colon + 3] == UInt8(ascii: "-") else { return false }
        if isLiteral { return true }
        func isFontAwesome(endingAt end: Int) -> Bool {
            end - 2 >= bytes.startIndex && bytes[end - 2] == UInt8(ascii: "f") && bytes[end - 1] == UInt8(ascii: "a")
        }
        if isFontAwesome(endingAt: colon) { return true }
        return colon - 1 >= bytes.startIndex && "bklrs".utf8.contains(bytes[colon - 1]) && isFontAwesome(endingAt: colon - 1)
    }

    /// JavaScript's `\w` among bytes: ASCII letters, digits and `_`.
    private static func isASCIIWordCharacter(_ byte: UInt8) -> Bool {
        switch byte {
        case UInt8(ascii: "a")...UInt8(ascii: "z"), UInt8(ascii: "A")...UInt8(ascii: "Z"), UInt8(ascii: "0")...UInt8(ascii: "9"), UInt8(ascii: "_"): true
        default: false
        }
    }
}
