/**
 * File: DiagramSVGSyntax.swift
 * ----------------------------
 * Layer: Core
 * Description: The pieces of SVG text as Strings, for callers that need one piece alone: escaped text, compact numbers
 *              and a path's data, written as the document's buffer writes them.
 *
 * Authors: Bahey Shalash
 * Version: 0.2
 * Date: 23/11/2026
 */

import CoreGraphics

/// Escapes text, writes numbers and writes paths as Strings, by `DiagramSVGBuffer`'s rules; the writer itself appends
/// them to its buffer.
enum DiagramSVGSyntax {
    /// `text` for an attribute's value or an element's content: `&`, `<`, `>`, `"` and `'` as entities, and the
    /// characters XML 1.0 has no place for (control characters other than tab, line feed and carriage return, U+FFFE and
    /// U+FFFF) left out.
    static func escaped(_ text: String) -> String {
        var buffer = DiagramSVGBuffer(reservingCapacity: text.utf8.count)
        buffer.appendEscaped(text)
        return buffer.text
    }

    /// `value` to two decimals without trailing zeros (`12`, `12.5`, `-0.25`), as Pele writes coordinates; 0 for a value
    /// that is not finite.
    static func number(_ value: CGFloat) -> String {
        var buffer = DiagramSVGBuffer(reservingCapacity: 16)
        buffer.appendNumber(value)
        return buffer.text
    }

    /// A path's data: `M`, `L`, `Q`, `C` and `Z` with absolute coordinates.
    static func pathData(_ path: CGPath) -> String {
        var buffer = DiagramSVGBuffer()
        buffer.appendPathData(path)
        return buffer.text
    }
}
