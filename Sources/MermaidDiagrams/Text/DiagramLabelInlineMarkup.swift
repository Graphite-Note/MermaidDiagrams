/**
 * File: DiagramLabelInlineMarkup.swift
 * ------------------------------------
 * Layer: Core
 * Description: One line of a label read into spans of one emphasis as Pele's inline reads it: HTML's emphasis tags,
 *              other HTML tags dropped with their text kept, and in a Markdown string the * and _ markers.
 *
 * Authors: Bahey Shalash
 * Version: 0.5
 * Date: 23/11/2026
 */

/// Pele's `inline` (text/label.ts): `<b>`, `<strong>` bold; `<i>`, `<em>`, `<cite>`, `<dfn>`, `<var>` italic; `<code>`,
/// `<kbd>`, `<samp>`, `<tt>` monospaced; every other HTML tag (`<span>`, `<u>`, `<sub>`) dropped and its text kept, and
/// anything else shaped like a tag (`List<T>`) kept as text. HTML's emphasis carries over the label's line breaks, so
/// `open` goes from one line to the next. In a Markdown string, `**` or `__` opens bold and `*` or `_` italic where a
/// character other than a space follows and the marker comes again later in the line, and closes it after a character
/// other than a space; an `_` between two word characters is text; Markdown's emphasis ends with its line. The package
/// draws `<sub>`, `<sup>` and `<u>` as plain text, where Pele shifts, shrinks or underlines it.
struct DiagramLabelInlineMarkup {
    private let source: ArraySlice<Unicode.Scalar>
    private let isMarkdown: Bool
    private var builder = DiagramLabelIcons()
    private var style: DiagramTextStyle
    private var markedByMarkdown: DiagramTextStyle = []
    private var pendingText: [Unicode.Scalar] = []

    /// The spans of `source`, a line of a label already trimmed; `open` is the HTML emphasis open before the line, and
    /// after it, the emphasis open at its end.
    static func spans(of source: ArraySlice<Unicode.Scalar>, isMarkdown: Bool, open: inout DiagramTextStyle) -> [DiagramLabelSpan] {
        var reader = DiagramLabelInlineMarkup(source: source, isMarkdown: isMarkdown, style: open)
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
                let emphasis = Self.emphasisByTag[tag.name] ?? []
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
                if !emphasis.isEmpty || Self.htmlTagNames.contains(tag.name) {
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

extension DiagramLabelInlineMarkup {
    /// A tag at `index` as Pele's `RE_TAG` (`<\/?([a-zA-Z][\w-]*)(?:\s[^<>]*)?\/?>`) finds it: its name in lower case,
    /// whether it closes, and its length.
    static func tag(in source: ArraySlice<Unicode.Scalar>, at index: Int) -> (name: String, isClosing: Bool, length: Int)? {
        var end = index + 1
        let isClosing = end < source.endIndex && source[end] == "/"
        if isClosing { end += 1 }
        guard end < source.endIndex, isASCIILetter(source[end]) else { return nil }
        let nameStart = end
        while end < source.endIndex, DiagramLabelEntities.isWordCharacter(source[end]) || source[end] == "-" { end += 1 }
        let name = String(String.UnicodeScalarView(source[nameStart..<end])).lowercased()
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

    /// Pele's `TAG_STYLES` that the package draws.
    static let emphasisByTag: [String: DiagramTextStyle] = [
        "b": .bold, "strong": .bold, "i": .italic, "em": .italic, "cite": .italic, "dfn": .italic, "var": .italic,
        "code": .monospaced, "kbd": .monospaced, "samp": .monospaced, "tt": .monospaced,
    ]

    /// Pele's `HTML_TAGS`: tags dropped with their text kept.
    static let htmlTagNames: Set<String> = Set(("a abbr address article aside audio b bdi bdo big blockquote body br button caption center cite code col "
        + "colgroup data dd del details dfn dialog div dl dt em embed fieldset figcaption figure font footer form h1 h2 "
        + "h3 h4 h5 h6 head header hr html i iframe img input ins kbd label legend li link main map mark meta meter nav "
        + "noscript object ol optgroup option output p picture pre progress q rp rt ruby s samp script section select "
        + "small source span strike strong style sub summary sup table tbody td template textarea tfoot th thead time "
        + "title tr track tt u ul var video wbr").split(separator: " ").map(String.init))
}
