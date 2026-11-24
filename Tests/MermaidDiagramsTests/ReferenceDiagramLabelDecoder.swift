/**
 * File: ReferenceDiagramLabelDecoder.swift
 * ----------------------------------------
 * Layer: Tests
 * Description: Release 0.7.0's label decoder on Unicode scalars, kept as it was written: line breaks, a Markdown
 *              string's indentation, literal text, inline markup, icon names and codes; the oracle the decoding on bytes
 *              is checked against.
 *
 * Authors: Félix Chevalier, Bahey Shalash
 * Version: 0.1
 * Date: 24/11/2026
 */

@testable import MermaidDiagrams

/// 0.7.0's `DiagramLabelDecoder.label(from:form:)`: text without markup kept as it is, trimmed; text with markup read
/// on its Unicode scalars into lines and spans.
enum ReferenceDiagramLabelDecoder {
    static func label(from rawText: String, form: DiagramLabelDecoder.Form) -> DiagramLabel {
        guard !rawText.isEmpty else { return DiagramLabel(lines: [rawText]) }
        let isLiteral = form == .literal
        if DiagramLabelLineBreaks.isUnmarked(Array(rawText.utf8), isLiteral: isLiteral) {
            return DiagramLabel(lines: [JavaScriptStringTrimming.trimmed(rawText)])
        }
        var scalars = Array(rawText.unicodeScalars)
        if isLiteral { scalars = ReferenceLabelLineBreaks.literalText(scalars) }
        let isMarkdown = form == .markdown
        let source = isMarkdown ? ReferenceLabelLineBreaks.markdownSource(scalars) : JavaScriptStringTrimming.trimmed(scalars[...])
        var open: DiagramTextStyle = []
        let lines = ReferenceLabelLineBreaks.lines(of: source).map { line in
            ReferenceLabelInlineMarkup.spans(of: JavaScriptStringTrimming.trimmed(line), isMarkdown: isMarkdown, open: &open)
        }
        return DiagramLabel(spans: lines)
    }
}

/// 0.7.0's line structure of a label's text, on Unicode scalars.
enum ReferenceLabelLineBreaks {
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

/// Pele's `inline` (text/label.ts): `<b>`, `<strong>` bold; `<i>`, `<em>`, `<cite>`, `<dfn>`, `<var>` italic; `<code>`,
/// `<kbd>`, `<samp>`, `<tt>` monospaced; every other HTML tag (`<span>`, `<u>`, `<sub>`) dropped and its text kept, and
/// anything else shaped like a tag (`List<T>`) kept as text. HTML's emphasis carries over the label's line breaks, so
/// `open` goes from one line to the next. In a Markdown string, `**` or `__` opens bold and `*` or `_` italic where a
/// character other than a space follows and the marker comes again later in the line, and closes it after a character
/// other than a space; an `_` between two word characters is text; Markdown's emphasis ends with its line. The package
/// draws `<sub>`, `<sup>` and `<u>` as plain text, where Pele shifts, shrinks or underlines it.
struct ReferenceLabelInlineMarkup {
    private let source: ArraySlice<Unicode.Scalar>
    private let isMarkdown: Bool
    private var builder = ReferenceLabelIcons()
    private var style: DiagramTextStyle
    private var markedByMarkdown: DiagramTextStyle = []
    private var pendingText: [Unicode.Scalar] = []

    /// The spans of `source`, a line of a label already trimmed; `open` is the HTML emphasis open before the line, and
    /// after it, the emphasis open at its end.
    static func spans(of source: ArraySlice<Unicode.Scalar>, isMarkdown: Bool, open: inout DiagramTextStyle) -> [DiagramLabelSpan] {
        var reader = ReferenceLabelInlineMarkup(source: source, isMarkdown: isMarkdown, style: open)
        reader.read(open: &open)
        return reader.builder.spans.filter { span in !span.text.isEmpty }
    }

    private init(source: ArraySlice<Unicode.Scalar>, isMarkdown: Bool, style: DiagramTextStyle) {
        self.source = source
        self.isMarkdown = isMarkdown
        self.style = style
    }

    private mutating func read(open: inout DiagramTextStyle) {
        var index = source.startIndex
        while index < source.endIndex {
            let scalar = source[index]
            if scalar == "<", let tag = Self.tag(in: source, at: index) {
                let emphasis = DiagramLabelTagNames.emphasisByTag[tag.name] ?? []
                if !emphasis.isEmpty {
                    flush()
                    if tag.isClosing {
                        open.subtract(emphasis)
                        style.subtract(emphasis)
                    } else {
                        open.formUnion(emphasis)
                        style.formUnion(emphasis)
                    }
                }
                if !emphasis.isEmpty || DiagramLabelTagNames.htmlTagNames.contains(tag.name) {
                    index += tag.length
                    continue
                }
            } else if isMarkdown, scalar == "*" || scalar == "_", let length = markdownMarkerLength(at: index) {
                index += length
                continue
            }
            pendingText.append(scalar)
            index += 1
        }
        flush()
    }

    private mutating func flush() {
        builder.append(pendingText[...], style: style)
        pendingText.removeAll(keepingCapacity: true)
    }

    /// The length of the Markdown marker at `index` when it opens or closes emphasis, having done so, or nil when it is text.
    private mutating func markdownMarkerLength(at index: Int) -> Int? {
        let marker = source[index]
        let isDouble = index + 1 < source.endIndex && source[index + 1] == marker
        let emphasis: DiagramTextStyle = isDouble ? .bold : .italic
        let length = isDouble ? 2 : 1
        let opens = !markedByMarkdown.contains(emphasis)
        let previous: Unicode.Scalar = index > source.startIndex ? source[index - 1] : " "
        let next: Unicode.Scalar = index + length < source.endIndex ? source[index + length] : " "
        let canOpen = opens && !JavaScriptStringTrimming.isWhitespace(next) && appearsAgain(marker, isDouble: isDouble, from: index + length)
        let canClose = !opens && !JavaScriptStringTrimming.isWhitespace(previous)
        let isInsideWord = marker == "_" && DiagramLabelEntities.isWordCharacter(previous) && DiagramLabelEntities.isWordCharacter(next)
        guard canOpen || canClose, !isInsideWord else { return nil }
        flush()
        if canOpen {
            markedByMarkdown.formUnion(emphasis)
            style.formUnion(emphasis)
        } else {
            markedByMarkdown.subtract(emphasis)
            style.subtract(emphasis)
        }
        return length
    }

    /// Whether the marker (twice for a double one) is written again at or after `start`.
    private func appearsAgain(_ marker: Unicode.Scalar, isDouble: Bool, from start: Int) -> Bool {
        var index = start
        while index < source.endIndex {
            if source[index] == marker, !isDouble || (index + 1 < source.endIndex && source[index + 1] == marker) { return true }
            index += 1
        }
        return false
    }
}

extension ReferenceLabelInlineMarkup {
    /// A tag at `index` as Pele's `RE_TAG` (`<\/?([a-zA-Z][\w-]*)(?:\s[^<>]*)?\/?>`) finds it: its name in lower case,
    /// whether it closes, and its length.
    static func tag(in source: ArraySlice<Unicode.Scalar>, at index: Int) -> (name: String, isClosing: Bool, length: Int)? {
        var end = index + 1
        let isClosing = end < source.endIndex && source[end] == "/"
        if isClosing { end += 1 }
        guard end < source.endIndex, isASCIILetter(source[end]) else { return nil }
        let nameStart = end
        while end < source.endIndex, DiagramLabelEntities.isWordCharacter(source[end]) || source[end] == "-" { end += 1 }
        let name = UnicodeScalarText.string(source[nameStart..<end]).lowercased()
        if end < source.endIndex, JavaScriptStringTrimming.isWhitespace(source[end]) {
            while end < source.endIndex, source[end] != "<", source[end] != ">" { end += 1 }
        } else if end < source.endIndex, source[end] == "/" {
            end += 1
        }
        guard end < source.endIndex, source[end] == ">" else { return nil }
        return (name, isClosing, end + 1 - index)
    }

    private static func isASCIILetter(_ scalar: Unicode.Scalar) -> Bool {
        ("a"..."z").contains(scalar) || ("A"..."Z").contains(scalar)
    }
}

/// The spans of one line of a label. Pele draws `fa:fa-name` (and `fab:`, `fak:`, `fal:`, `far:`, `fas:`) as an icon
/// only when the host gives it one by that name (text/icons.ts `iconMarkup`); it ships no icon of its own, and with
/// none an icon takes no room: its name is left out with the space after it, or, at the end of the text, with the
/// spaces before it (text/label.ts `pushIcons`). The package has no icons to draw either, so every name is left out so.
struct ReferenceLabelIcons {
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
