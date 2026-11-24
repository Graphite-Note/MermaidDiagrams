/**
 * File: DiagramLabelLineBreaks.swift
 * ----------------------------------
 * Layer: Core
 * Description: Where a label's text breaks into lines as Pele breaks it (<br>, a written \n, a line break), the text
 *              Pele reads without markup (found in its UTF-8 bytes), a Markdown string's indentation, and the literal text
 *              of journeys and timelines.
 *
 * Authors: Bahey Shalash
 * Version: 0.3
 * Date: 23/11/2026
 */

/// The line structure of a label's text, as Pele's text/label.ts and common/fit.ts read it.
enum DiagramLabelLineBreaks {
    /// The text split where Pele's `RE_BREAK` (`<br\s*\/?>|\\n|\n`, in any case) matches: `<br>`, `<br/>`, `<br />`
    /// with any whitespace before the `/`, a backslash and `n` or `N` as written, and a line break.
    static func lines(of scalars: ArraySlice<Unicode.Scalar>) -> [ArraySlice<Unicode.Scalar>] {
        var lines: [ArraySlice<Unicode.Scalar>] = []
        var lineStart = scalars.startIndex
        var index = scalars.startIndex
        while index < scalars.endIndex {
            if let length = breakLength(in: scalars, at: index) {
                lines.append(scalars[lineStart..<index])
                index += length
                lineStart = index
            } else {
                index += 1
            }
        }
        lines.append(scalars[lineStart..<scalars.endIndex])
        return lines
    }

    /// The length of a break at `index`, or nil.
    static func breakLength(in scalars: ArraySlice<Unicode.Scalar>, at index: Int) -> Int? {
        switch scalars[index] {
        case "\n": return 1
        case "\\": return index + 1 < scalars.endIndex && (scalars[index + 1] == "n" || scalars[index + 1] == "N") ? 2 : nil
        case "<": return lineBreakTagLength(in: scalars, at: index)
        default: return nil
        }
    }

    /// The length of `<br\s*\/?>`, in any case, at `index`, or nil.
    static func lineBreakTagLength(in scalars: ArraySlice<Unicode.Scalar>, at index: Int) -> Int? {
        guard index + 3 < scalars.endIndex, scalars[index] == "<", scalars[index + 1] == "b" || scalars[index + 1] == "B",
              scalars[index + 2] == "r" || scalars[index + 2] == "R" else { return nil }
        var end = index + 3
        while end < scalars.endIndex, JavaScriptStringTrimming.isWhitespace(scalars[end]) { end += 1 }
        if end < scalars.endIndex, scalars[end] == "/" { end += 1 }
        guard end < scalars.endIndex, scalars[end] == ">" else { return nil }
        return end + 1 - index
    }

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

    /// A Markdown string's text as Pele reads it before its lines: carriage returns as line breaks, the indentation all
    /// its lines with text share taken off each line, and the whole trimmed (text/label.ts `dedent`).
    static func markdownSource(_ scalars: [Unicode.Scalar]) -> ArraySlice<Unicode.Scalar> {
        var normalized: [Unicode.Scalar] = []
        normalized.reserveCapacity(scalars.count)
        var index = 0
        while index < scalars.count {
            if scalars[index] == "\r" {
                normalized.append("\n")
                if index + 1 < scalars.count, scalars[index + 1] == "\n" { index += 1 }
            } else {
                normalized.append(scalars[index])
            }
            index += 1
        }
        return JavaScriptStringTrimming.trimmed(dedented(normalized)[...])
    }

    private static func dedented(_ scalars: [Unicode.Scalar]) -> [Unicode.Scalar] {
        let lines = scalars.split(separator: "\n", omittingEmptySubsequences: false)
        let indents = lines.map { line in line.prefix(while: JavaScriptStringTrimming.isWhitespace).count }
        let shared = zip(lines, indents).filter { line, indent in indent < line.count }.map(\.1).min() ?? 0
        guard shared > 0 else { return scalars }
        return Array(zip(lines, indents).map { line, indent in line.dropFirst(min(shared, indent)) }.joined(separator: ["\n"]))
    }

    /// The text of a journey's or timeline's label as Pele's `plainLabel` writes it before laying it out: each `<` that
    /// starts no `<br>` written `&lt;` and each `:fa-` written `&colon;fa-`, so that tags and icon names show as written.
    static func literalText(_ scalars: [Unicode.Scalar]) -> [Unicode.Scalar] {
        guard scalars.contains("<") || scalars.contains(":") else { return scalars }
        var result: [Unicode.Scalar] = []
        result.reserveCapacity(scalars.count)
        let all = scalars[...]
        for index in scalars.indices {
            let scalar = scalars[index]
            if scalar == "<", lineBreakTagLength(in: all, at: index) == nil {
                result.append(contentsOf: "&lt;".unicodeScalars)
            } else if scalar == ":", index + 3 < scalars.count, scalars[index + 1] == "f", scalars[index + 2] == "a", scalars[index + 3] == "-" {
                result.append(contentsOf: "&colon;".unicodeScalars)
            } else {
                result.append(scalar)
            }
        }
        return result
    }
}
