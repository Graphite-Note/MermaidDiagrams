/**
 * File: JavaScriptStringTrimming.swift
 * ------------------------------------
 * Layer: Core
 * Description: JavaScript's whitespace over Unicode scalars, and text trimmed at either end as JavaScript's trim,
 *              trimStart and trimEnd leave it, as Pele trims a label's lines.
 *
 * Authors: Bahey Shalash
 * Version: 0.2
 * Date: 23/11/2026
 */

/// JavaScript's `\s` and its `trim`, `trimStart` and `trimEnd`, on Unicode scalars: tab to carriage return, space,
/// no-break space, the Ogham space mark, U+2000 to U+200A, the line and paragraph separators, the narrow no-break
/// space, the medium mathematical space, the ideographic space and the byte order mark. A zero-width space and a soft
/// hyphen are not whitespace.
enum JavaScriptStringTrimming {
    static func isWhitespace(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.value {
        case 0x09...0x0D, 0x20, 0xA0, 0x1680, 0x2000...0x200A, 0x2028, 0x2029, 0x202F, 0x205F, 0x3000, 0xFEFF: true
        default: false
        }
    }

    static func trimmed(_ scalars: ArraySlice<Unicode.Scalar>) -> ArraySlice<Unicode.Scalar> {
        trimmedEnd(trimmedStart(scalars))
    }

    static func trimmedStart(_ scalars: ArraySlice<Unicode.Scalar>) -> ArraySlice<Unicode.Scalar> {
        scalars.drop(while: isWhitespace)
    }

    static func trimmedEnd(_ scalars: ArraySlice<Unicode.Scalar>) -> ArraySlice<Unicode.Scalar> {
        var end = scalars.endIndex
        while end > scalars.startIndex, isWhitespace(scalars[end - 1]) { end -= 1 }
        return scalars[scalars.startIndex..<end]
    }

    static func trimmed(_ text: String) -> String {
        trimmedEnd(trimmedStart(text))
    }

    static func trimmedStart(_ text: String) -> String {
        let scalars = text.unicodeScalars
        guard let first = scalars.first, isWhitespace(first) else { return text }
        let start = scalars.firstIndex { scalar in !isWhitespace(scalar) } ?? scalars.endIndex
        return String(Substring(scalars[start...]))
    }

    static func trimmedEnd(_ text: String) -> String {
        let scalars = text.unicodeScalars
        guard let last = scalars.last, isWhitespace(last) else { return text }
        var end = scalars.endIndex
        while end > scalars.startIndex, case let before = scalars.index(before: end), isWhitespace(scalars[before]) { end = before }
        return String(Substring(scalars[..<end]))
    }

    static func endsWithWhitespace(_ text: String) -> Bool {
        text.unicodeScalars.last.map(isWhitespace) ?? false
    }
}
