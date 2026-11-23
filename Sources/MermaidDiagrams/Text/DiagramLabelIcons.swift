/**
 * File: DiagramLabelIcons.swift
 * -----------------------------
 * Layer: Core
 * Description: A label's line built span by span as Pele's pushIcons and pushText build it: Font Awesome names
 *              (fa:fa-…) left out as Pele leaves out icons it has no drawing for, the text's entity codes read, and
 *              text of one emphasis joined into one span.
 *
 * Authors: Bahey Shalash
 * Version: 0.2
 * Date: 23/11/2026
 */

/// The spans of one line of a label. Pele draws `fa:fa-name` (and `fab:`, `fak:`, `fal:`, `far:`, `fas:`) as an icon
/// only when the host gives it one by that name (text/icons.ts `iconMarkup`); it ships no icon of its own, and with
/// none an icon takes no room: its name is left out with the space after it, or, at the end of the text, with the
/// spaces before it (text/label.ts `pushIcons`). The package has no icons to draw either, so every name is left out so.
struct DiagramLabelIcons {
    private(set) var spans: [DiagramLabelSpan] = []

    /// Appends `text` in `style`, its icon names left out.
    mutating func append(_ text: ArraySlice<Unicode.Scalar>, style: DiagramTextStyle) {
        guard Self.containsIconName(text) else { return appendText(text, style: style) }
        var kept = text.startIndex
        var searchStart = text.startIndex
        while let name = Self.nextIconName(in: text, from: searchStart) {
            appendText(text[kept..<name.lowerBound], style: style)
            kept = name.upperBound
            searchStart = name.upperBound
            if kept < text.endIndex, text[kept] == " " {
                kept += 1
            } else if kept == text.endIndex, var last = spans.popLast() {
                last.text = JavaScriptStringTrimming.trimmedEnd(last.text)
                spans.append(last)
            }
        }
        appendText(text[kept...], style: style)
    }

    /// Pele's `pushPlain`: the text's codes read, joined to the span before when it has the same emphasis.
    private mutating func appendText(_ text: ArraySlice<Unicode.Scalar>, style: DiagramTextStyle) {
        guard !text.isEmpty else { return }
        let decoded = DiagramLabelEntities.decoded(UnicodeScalarText.string(text))
        if var last = spans.popLast() {
            if last.style == style {
                last.text += decoded
                spans.append(last)
                return
            }
            spans.append(last)
        }
        spans.append(DiagramLabelSpan(text: decoded, style: style))
    }

    /// Whether `text` holds `:fa-` after `fa` and at most one of `bklrs`, Pele's `fa[bklrs]?:fa-`.
    static func containsIconName(_ text: ArraySlice<Unicode.Scalar>) -> Bool {
        var index = text.startIndex
        while index < text.endIndex {
            if iconPrefixLength(in: text, at: index) != nil { return true }
            index += 1
        }
        return false
    }

    /// The first icon name at or after `start`: Pele's `(fa[bklrs]?):fa-([\w-]+)`.
    private static func nextIconName(in text: ArraySlice<Unicode.Scalar>, from start: Int) -> Range<Int>? {
        var index = start
        while index < text.endIndex {
            if let prefix = iconPrefixLength(in: text, at: index) {
                var end = index + prefix
                while end < text.endIndex, DiagramLabelEntities.isWordCharacter(text[end]) || text[end] == "-" { end += 1 }
                if end > index + prefix { return index..<end }
            }
            index += 1
        }
        return nil
    }

    /// The length of `fa:fa-` (or `fab:fa-` and the others) at `index`, or nil.
    private static func iconPrefixLength(in text: ArraySlice<Unicode.Scalar>, at index: Int) -> Int? {
        guard index + 1 < text.endIndex, text[index] == "f", text[index + 1] == "a" else { return nil }
        var colon = index + 2
        if colon < text.endIndex, "bklrs".unicodeScalars.contains(text[colon]) { colon += 1 }
        guard colon + 3 < text.endIndex, text[colon] == ":", text[colon + 1] == "f", text[colon + 2] == "a", text[colon + 3] == "-" else {
            return nil
        }
        return colon + 4 - index
    }
}
