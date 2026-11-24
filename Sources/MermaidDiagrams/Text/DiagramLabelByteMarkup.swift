/**
 * File: DiagramLabelByteMarkup.swift
 * ----------------------------------
 * Layer: Core
 * Description: Reads one trimmed line of a label's bytes into spans as Pele's inline does: HTML's emphasis tags, other
 *              HTML tags dropped with their text kept, and in a Markdown string its `*` and `_` markers; tag names looked
 *              up as numbers of their packed bytes.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 24/11/2026
 */

/// Pele's `inline` (text/label.ts): `<b>`, `<strong>` bold; `<i>`, `<em>`, `<cite>`, `<dfn>`, `<var>` italic; `<code>`,
/// `<kbd>`, `<samp>`, `<tt>` monospaced; every other HTML tag (`<span>`, `<u>`, `<sub>`) dropped and its text kept, and
/// anything else shaped like a tag (`List<T>`) kept as text. HTML's emphasis carries over the label's line breaks, so
/// `open` goes from one line to the next. In a Markdown string, `**` or `__` opens bold and `*` or `_` italic where a
/// character other than a space follows and the marker comes again later in the line, and closes it after a character
/// other than a space; an `_` between two word characters is text; Markdown's emphasis ends with its line. The package
/// draws `<sub>`, `<sup>` and `<u>` as plain text, where Pele shifts, shrinks or underlines it.
extension DiagramLabelByteDecoder {
    /// The emphasis a line's reading has open: HTML's, carried from line to line, and Markdown's, which ends with the line.
    struct OpenEmphasis {
        var style: DiagramTextStyle
        var markedByMarkdown: DiagramTextStyle = []
    }

    /// Reads the trimmed line `source[range]` into a line of spans; whether one of its spans has an emphasis.
    mutating func readLine(_ source: UnsafeBufferPointer<UInt8>, _ range: Range<Int>, isMarkdown: Bool, open: inout DiagramTextStyle) -> Bool {
        let lineStart = Int32(output.count)
        let firstSpan = spans.count
        var emphasis = OpenEmphasis(style: open)
        pending.removeAll(keepingCapacity: true)
        var index = range.lowerBound
        while index < range.upperBound {
            let byte = source[index]
            if byte == UInt8(ascii: "<"), let tag = Self.tag(source, range.upperBound, at: index) {
                if !tag.emphasis.isEmpty {
                    flush(style: emphasis.style, firstSpan: firstSpan)
                    if tag.isClosing {
                        open.subtract(tag.emphasis)
                        emphasis.style.subtract(tag.emphasis)
                    } else {
                        open.formUnion(tag.emphasis)
                        emphasis.style.formUnion(tag.emphasis)
                    }
                }
                if !tag.emphasis.isEmpty || tag.isHTMLTag {
                    index += tag.length
                    continue
                }
            } else if isMarkdown, byte == UInt8(ascii: "*") || byte == UInt8(ascii: "_"),
                      let length = markdownMarkerLength(source, range, at: index, emphasis: &emphasis, firstSpan: firstSpan) {
                index += length
                continue
            }
            pending.append(byte)
            index += 1
        }
        flush(style: emphasis.style, firstSpan: firstSpan)
        return finishLine(start: lineStart, firstSpan: firstSpan)
    }

    /// Ends the line: its empty spans dropped, as Pele's inline drops them; whether a span kept has an emphasis.
    private mutating func finishLine(start lineStart: Int32, firstSpan: Int) -> Bool {
        var kept = firstSpan
        var hasEmphasis = false
        for spanIndex in firstSpan..<spans.count where spans[spanIndex].start != spans[spanIndex].end {
            spans[kept] = spans[spanIndex]
            if !spans[spanIndex].style.isEmpty { hasEmphasis = true }
            kept += 1
        }
        spans.removeSubrange(kept...)
        lines.append(DiagramLabelLineRecord(start: lineStart, end: Int32(output.count), firstSpan: Int32(firstSpan), spanCount: Int32(kept - firstSpan)))
        return hasEmphasis
    }

    /// The length of the Markdown marker at `index` when it opens or closes emphasis, having done so, or nil when it is text.
    private mutating func markdownMarkerLength(_ bytes: UnsafeBufferPointer<UInt8>, _ range: Range<Int>, at index: Int, emphasis open: inout OpenEmphasis,
                                               firstSpan: Int) -> Int? {
        let (start, end) = (range.lowerBound, range.upperBound)
        let marker = bytes[index]
        let isDouble = index + 1 < end && bytes[index + 1] == marker
        let emphasis: DiagramTextStyle = isDouble ? .bold : .italic
        let length = isDouble ? 2 : 1
        let opens = !open.markedByMarkdown.contains(emphasis)
        let previousIsWhitespace = index > start ? JavaScriptWhitespace.lengthOfLast(in: bytes[start..<index]) > 0 : true
        let nextIsWhitespace = index + length < end ? JavaScriptWhitespace.length(in: bytes[..<end], at: index + length) > 0 : true
        let canOpen = opens && !nextIsWhitespace && Self.appearsAgain(marker, isDouble: isDouble, in: bytes, from: index + length, to: end)
        let canClose = !opens && !previousIsWhitespace
        let isInsideWord = marker == UInt8(ascii: "_") && index > start && Self.isWordByte(bytes[index - 1]) && index + length < end
            && Self.isWordByte(bytes[index + length])
        guard canOpen || canClose, !isInsideWord else { return nil }
        flush(style: open.style, firstSpan: firstSpan)
        if canOpen {
            open.markedByMarkdown.formUnion(emphasis)
            open.style.formUnion(emphasis)
        } else {
            open.markedByMarkdown.subtract(emphasis)
            open.style.subtract(emphasis)
        }
        return length
    }

    /// Whether the marker (twice for a double one) is written again from `start` on.
    private static func appearsAgain(_ marker: UInt8, isDouble: Bool, in bytes: UnsafeBufferPointer<UInt8>, from start: Int, to end: Int) -> Bool {
        var position = start
        while position < end {
            if bytes[position] == marker, !isDouble || (position + 1 < end && bytes[position + 1] == marker) { return true }
            position += 1
        }
        return false
    }

    struct Tag {
        let emphasis: DiagramTextStyle
        let isHTMLTag: Bool
        let isClosing: Bool
        let length: Int
    }

    /// A tag at `index` as Pele's `RE_TAG` (`<\/?([a-zA-Z][\w-]*)(?:\s[^<>]*)?\/?>`) finds it: its emphasis, whether it is
    /// one of HTML's tags, whether it closes, and its length.
    static func tag(_ bytes: UnsafeBufferPointer<UInt8>, _ end: Int, at index: Int) -> Tag? {
        var position = index + 1
        let isClosing = position < end && bytes[position] == UInt8(ascii: "/")
        if isClosing { position += 1 }
        guard position < end, isASCIILetter(bytes[position]) else { return nil }
        let nameStart = position
        var packedName: UInt64 = 0
        while position < end, isWordByte(bytes[position]) || bytes[position] == UInt8(ascii: "-") {
            let byte = bytes[position]
            let lowered = byte >= UInt8(ascii: "A") && byte <= UInt8(ascii: "Z") ? byte | 0x20 : byte
            if position - nameStart < 8 { packedName |= UInt64(lowered) << UInt64(8 * (position - nameStart)) }
            position += 1
        }
        let nameLength = position - nameStart
        if position < end, JavaScriptWhitespace.length(in: bytes[..<end], at: position) > 0 {
            while position < end, bytes[position] != UInt8(ascii: "<"), bytes[position] != UInt8(ascii: ">") { position += 1 }
        } else if position < end, bytes[position] == UInt8(ascii: "/") {
            position += 1
        }
        guard position < end, bytes[position] == UInt8(ascii: ">") else { return nil }
        if nameLength <= 8 {
            return Tag(emphasis: DiagramLabelTagNames.emphasisByPackedName[packedName] ?? [], isHTMLTag: DiagramLabelTagNames.packedHTMLTagNames.contains(packedName),
                       isClosing: isClosing, length: position + 1 - index)
        }
        let name = String(decoding: UnsafeBufferPointer(rebasing: bytes[nameStart..<(nameStart + nameLength)]), as: UTF8.self).lowercased()
        return Tag(emphasis: DiagramLabelTagNames.emphasisByTag[name] ?? [], isHTMLTag: DiagramLabelTagNames.htmlTagNames.contains(name), isClosing: isClosing,
                   length: position + 1 - index)
    }

    private static func isASCIILetter(_ byte: UInt8) -> Bool {
        (byte >= UInt8(ascii: "a") && byte <= UInt8(ascii: "z")) || (byte >= UInt8(ascii: "A") && byte <= UInt8(ascii: "Z"))
    }

    /// JavaScript's `\w` among bytes: ASCII letters, digits and `_`.
    static func isWordByte(_ byte: UInt8) -> Bool {
        isASCIILetter(byte) || (byte >= UInt8(ascii: "0") && byte <= UInt8(ascii: "9")) || byte == UInt8(ascii: "_")
    }
}

/// Pele's tag names: the emphasis tags the package draws and HTML's tags, and those of at most eight bytes as numbers of
/// their bytes, lower case, first byte lowest.
enum DiagramLabelTagNames {
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

    static func packed(_ name: String) -> UInt64 {
        var value: UInt64 = 0
        for (offset, byte) in name.utf8.enumerated() where offset < 8 { value |= UInt64(byte) << UInt64(8 * offset) }
        return value
    }

    static let emphasisByPackedName: [UInt64: DiagramTextStyle] = Dictionary(uniqueKeysWithValues: emphasisByTag.map { name, style in (packed(name), style) })
    static let packedHTMLTagNames: Set<UInt64> = Set(htmlTagNames.filter { name in name.utf8.count <= 8 }.map(packed))
}
