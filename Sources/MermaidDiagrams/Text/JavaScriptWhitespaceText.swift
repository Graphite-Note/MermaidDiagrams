/**
 * File: JavaScriptWhitespaceText.swift
 * ------------------------------------
 * Layer: Core
 * Description: JavaScript's whitespace over a string's Unicode scalars: trimming as `trim` does and splitting as Pele's
 *              patterns `\s+` and `\s*,\s*` split, for the short color values a diagram's theme variables give.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 23/11/2026
 */

extension JavaScriptWhitespace {
    /// Whether `scalar` is JavaScript's whitespace (`\s`), the characters `length(in:at:)` finds in UTF-8.
    static func contains(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.value {
        case 0x09...0x0D, 0x20, 0xA0, 0x1680, 0x2000...0x200A, 0x2028, 0x2029, 0x202F, 0x205F, 0x3000, 0xFEFF: true
        default: false
        }
    }

    /// `text` without the whitespace at either end, as JavaScript's `trim` leaves it.
    static func trimmed(_ text: Substring) -> Substring {
        let scalars = text.unicodeScalars
        guard let first = scalars.firstIndex(where: { scalar in !contains(scalar) }),
              let last = scalars.lastIndex(where: { scalar in !contains(scalar) }) else { return text[text.endIndex...] }
        return Substring(scalars[first...last])
    }

    /// `text` cut at each run of whitespace, as JavaScript's `split(/\s+/)` cuts it: an empty piece before whitespace that
    /// starts the text and after whitespace that ends it.
    static func pieces(ofWhitespaceSeparated text: Substring) -> [Substring] {
        var pieces: [Substring] = []
        var start = text.unicodeScalars.startIndex
        var index = start
        let scalars = text.unicodeScalars
        while index < scalars.endIndex {
            guard contains(scalars[index]) else {
                index = scalars.index(after: index)
                continue
            }
            pieces.append(Substring(scalars[start..<index]))
            while index < scalars.endIndex, contains(scalars[index]) { index = scalars.index(after: index) }
            start = index
        }
        pieces.append(Substring(scalars[start...]))
        return pieces
    }

    /// `text` cut at each comma with the whitespace around it, as JavaScript's `split(/\s*,\s*/)` cuts it.
    static func pieces(ofCommaSeparated text: Substring) -> [Substring] {
        let pieces = text.split(separator: ",", omittingEmptySubsequences: false)
        return pieces.indices.map { index in
            let scalars = pieces[index].unicodeScalars
            var start = scalars.startIndex
            var end = scalars.endIndex
            if index > pieces.startIndex { while start < end, contains(scalars[start]) { start = scalars.index(after: start) } }
            if index < pieces.endIndex - 1 { while end > start, contains(scalars[scalars.index(before: end)]) { end = scalars.index(before: end) } }
            return Substring(scalars[start..<end])
        }
    }
}
