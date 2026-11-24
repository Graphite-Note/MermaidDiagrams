/**
 * File: FlatLabelDecoder.swift
 * ----------------------------
 * Layer: Prototype
 * Description: Reads a label's written bytes into lines and spans of decoded bytes as DiagramLabelDecoder reads its
 *              text into Strings: line breaks, a Markdown string's indentation, emphasis tags and markers, other tags
 *              dropped, icon names left out and entity codes read; a label without markup stays a range of its source.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 24/11/2026
 */

import CoreGraphics

/// The decoder's buffers: the decoded bytes, the line and span records, and scratch for the text being read.
struct FlatLabelDecoder {
    var output: [UInt8] = []
    var lines: [FlatLabelLine] = []
    var spans: [FlatLabelSpan] = []
    private var prepared: [UInt8] = []
    private var pending: [UInt8] = []
    private var entityScratch: [UInt8] = []
    private var splitLines: [Range<Int>] = []

    /// A decoded label, and whether its one line is a range of the source rather than of `output`.
    struct Decoded {
        var label: FlatLabel
        var isInSource: Bool
    }

    mutating func removeAll() {
        output.removeAll(keepingCapacity: true)
        lines.removeAll(keepingCapacity: true)
        spans.removeAll(keepingCapacity: true)
    }

    mutating func decode(_ source: UnsafeBufferPointer<UInt8>, _ start: Int, _ end: Int, form: DiagramLabelDecoder.Form) -> Decoded {
        let firstLine = Int32(lines.count)
        let isLiteral = form == .literal
        if start == end || DiagramLabelLineBreaks.isUnmarked(source[start..<end], isLiteral: isLiteral) {
            let trimmed = start == end ? start..<end : FlatLabelScanning.trimmed(source, start, end)
            lines.append(FlatLabelLine(start: Int32(trimmed.lowerBound), end: Int32(trimmed.upperBound), firstSpan: Int32(spans.count), spanCount: 0))
            return Decoded(label: FlatLabel(firstLine: firstLine, lineCount: 1, hasSpans: false, isReadWithoutMarkup: true, isPrintableASCII: false),
                           isInSource: true)
        }
        prepared.removeAll(keepingCapacity: true)
        prepared.append(contentsOf: UnsafeBufferPointer(rebasing: source[start..<end]))
        if isLiteral { prepared = Self.literalText(prepared) }
        let isMarkdown = form == .markdown
        let range = prepared.withUnsafeBufferPointer { bytes in
            isMarkdown ? 0..<0 : FlatLabelScanning.trimmed(bytes, 0, bytes.count)
        }
        if isMarkdown { prepareMarkdownSource() }
        let sourceRange = isMarkdown ? 0..<prepared.count : range
        let preparedBytes = prepared
        var open: DiagramTextStyle = []
        var hasEmphasis = false
        preparedBytes.withUnsafeBufferPointer { bytes in
            splitLines.removeAll(keepingCapacity: true)
            var lineStart = sourceRange.lowerBound
            var index = sourceRange.lowerBound
            while index < sourceRange.upperBound {
                if let length = Self.breakLength(bytes, sourceRange.upperBound, at: index) {
                    splitLines.append(lineStart..<index)
                    index += length
                    lineStart = index
                } else {
                    index += 1
                }
            }
            splitLines.append(lineStart..<sourceRange.upperBound)
            for line in splitLines {
                let trimmed = FlatLabelScanning.trimmed(bytes, line.lowerBound, line.upperBound)
                if readInline(bytes, trimmed.lowerBound, trimmed.upperBound, isMarkdown: isMarkdown, open: &open) { hasEmphasis = true }
            }
        }
        let lineCount = Int32(lines.count) - firstLine
        if !hasEmphasis {
            for index in Int(firstLine)..<lines.count { lines[index].spanCount = 0 }
        }
        return Decoded(label: FlatLabel(firstLine: firstLine, lineCount: lineCount, hasSpans: hasEmphasis, isReadWithoutMarkup: false,
                                        isPrintableASCII: false), isInSource: false)
    }

    // MARK: Lines

    private static func breakLength(_ bytes: UnsafeBufferPointer<UInt8>, _ end: Int, at index: Int) -> Int? {
        switch bytes[index] {
        case UInt8(ascii: "\n"): return 1
        case UInt8(ascii: "\\"): return index + 1 < end && (bytes[index + 1] == UInt8(ascii: "n") || bytes[index + 1] == UInt8(ascii: "N")) ? 2 : nil
        case UInt8(ascii: "<"): return lineBreakTagLength(bytes, end, at: index)
        default: return nil
        }
    }

    private static func lineBreakTagLength(_ bytes: UnsafeBufferPointer<UInt8>, _ end: Int, at index: Int) -> Int? {
        guard index + 3 < end, bytes[index] == UInt8(ascii: "<"), bytes[index + 1] | 0x20 == UInt8(ascii: "b"),
              bytes[index + 2] | 0x20 == UInt8(ascii: "r") else { return nil }
        var position = index + 3
        while case let length = JavaScriptWhitespace.length(in: bytes[..<end], at: position), length > 0 { position += length }
        if position < end, bytes[position] == UInt8(ascii: "/") { position += 1 }
        guard position < end, bytes[position] == UInt8(ascii: ">") else { return nil }
        return position + 1 - index
    }

    /// Pele's `plainLabel`: each `<` that starts no `<br>` written `&lt;`, each `:fa-` written `&colon;fa-`.
    private static func literalText(_ bytes: [UInt8]) -> [UInt8] {
        guard bytes.contains(UInt8(ascii: "<")) || bytes.contains(UInt8(ascii: ":")) else { return bytes }
        var result: [UInt8] = []
        result.reserveCapacity(bytes.count + 8)
        bytes.withUnsafeBufferPointer { all in
            for index in all.indices {
                let byte = all[index]
                if byte == UInt8(ascii: "<"), lineBreakTagLength(all, all.count, at: index) == nil {
                    result.append(contentsOf: "&lt;".utf8)
                } else if byte == UInt8(ascii: ":"), index + 3 < all.count, all[index + 1] == UInt8(ascii: "f"), all[index + 2] == UInt8(ascii: "a"),
                          all[index + 3] == UInt8(ascii: "-") {
                    result.append(contentsOf: "&colon;".utf8)
                } else {
                    result.append(byte)
                }
            }
        }
        return result
    }

    /// A Markdown string's source: carriage returns as line breaks, the shared indentation taken off, trimmed.
    private mutating func prepareMarkdownSource() {
        var normalized: [UInt8] = []
        normalized.reserveCapacity(prepared.count)
        var index = 0
        while index < prepared.count {
            if prepared[index] == UInt8(ascii: "\r") {
                normalized.append(UInt8(ascii: "\n"))
                if index + 1 < prepared.count, prepared[index + 1] == UInt8(ascii: "\n") { index += 1 }
            } else {
                normalized.append(prepared[index])
            }
            index += 1
        }
        var dedented: [UInt8] = []
        normalized.withUnsafeBufferPointer { bytes in
            var lineRanges: [(range: Range<Int>, indent: Int, indentBytes: [Int])] = []
            var lineStart = 0
            for position in 0...bytes.count where position == bytes.count || bytes[position] == UInt8(ascii: "\n") {
                var indentEnds: [Int] = []
                var cursor = lineStart
                while case let length = JavaScriptWhitespace.length(in: bytes[..<position], at: cursor), length > 0 {
                    cursor += length
                    indentEnds.append(cursor)
                }
                lineRanges.append((lineStart..<position, indentEnds.count, indentEnds))
                lineStart = position + 1
            }
            let shared = lineRanges.filter { line in line.indentBytes.last ?? line.range.lowerBound < line.range.upperBound }.map(\.indent).min() ?? 0
            guard shared > 0 else {
                dedented = Array(bytes)
                return
            }
            for (index, line) in lineRanges.enumerated() {
                if index > 0 { dedented.append(UInt8(ascii: "\n")) }
                let dropped = min(shared, line.indent)
                let start = dropped == 0 ? line.range.lowerBound : line.indentBytes[dropped - 1]
                dedented.append(contentsOf: bytes[start..<line.range.upperBound])
            }
        }
        let trimmed = dedented.withUnsafeBufferPointer { bytes in FlatLabelScanning.trimmed(bytes, 0, bytes.count) }
        prepared = Array(dedented[trimmed])
    }

    // MARK: Inline markup

    /// Reads one trimmed line into spans; whether a span of it has emphasis.
    private mutating func readInline(_ bytes: UnsafeBufferPointer<UInt8>, _ start: Int, _ end: Int, isMarkdown: Bool, open: inout DiagramTextStyle) -> Bool {
        let lineStart = Int32(output.count)
        let firstSpan = spans.count
        var style = open
        var markedByMarkdown: DiagramTextStyle = []
        pending.removeAll(keepingCapacity: true)
        var index = start
        while index < end {
            let byte = bytes[index]
            if byte == UInt8(ascii: "<"), let tag = Self.tag(bytes, end, at: index) {
                if !tag.emphasis.isEmpty {
                    flush(style: style, firstSpan: firstSpan)
                    if tag.isClosing {
                        open.subtract(tag.emphasis)
                        style.subtract(tag.emphasis)
                    } else {
                        open.formUnion(tag.emphasis)
                        style.formUnion(tag.emphasis)
                    }
                }
                if !tag.emphasis.isEmpty || tag.isHTMLTag {
                    index += tag.length
                    continue
                }
            } else if isMarkdown, byte == UInt8(ascii: "*") || byte == UInt8(ascii: "_"),
                      let length = markdownMarkerLength(bytes, start, end, at: index, style: &style, marked: &markedByMarkdown, firstSpan: firstSpan) {
                index += length
                continue
            }
            pending.append(byte)
            index += 1
        }
        flush(style: style, firstSpan: firstSpan)
        // Empty spans are dropped, as Pele's inline drops them.
        var kept = firstSpan
        var hasEmphasis = false
        for spanIndex in firstSpan..<spans.count where spans[spanIndex].start != spans[spanIndex].end {
            spans[kept] = spans[spanIndex]
            if !spans[spanIndex].style.isEmpty { hasEmphasis = true }
            kept += 1
        }
        spans.removeSubrange(kept...)
        lines.append(FlatLabelLine(start: lineStart, end: Int32(output.count), firstSpan: Int32(firstSpan), spanCount: Int32(kept - firstSpan)))
        return hasEmphasis
    }

    private mutating func markdownMarkerLength(_ bytes: UnsafeBufferPointer<UInt8>, _ start: Int, _ end: Int, at index: Int, style: inout DiagramTextStyle,
                                               marked: inout DiagramTextStyle, firstSpan: Int) -> Int? {
        let marker = bytes[index]
        let isDouble = index + 1 < end && bytes[index + 1] == marker
        let emphasis: DiagramTextStyle = isDouble ? .bold : .italic
        let length = isDouble ? 2 : 1
        let opens = !marked.contains(emphasis)
        let previousIsWhitespace = index > start ? JavaScriptWhitespace.lengthOfLast(in: bytes[start..<index]) > 0 : true
        let previousIsWord = index > start && Self.isWordByte(bytes[index - 1])
        let nextIsWhitespace = index + length < end ? JavaScriptWhitespace.length(in: bytes[..<end], at: index + length) > 0 : true
        let nextIsWord = index + length < end && Self.isWordByte(bytes[index + length])
        var appearsAgain = false
        if opens, !nextIsWhitespace {
            var position = index + length
            while position < end {
                if bytes[position] == marker, !isDouble || (position + 1 < end && bytes[position + 1] == marker) {
                    appearsAgain = true
                    break
                }
                position += 1
            }
        }
        let canOpen = opens && !nextIsWhitespace && appearsAgain
        let canClose = !opens && !previousIsWhitespace
        let isInsideWord = marker == UInt8(ascii: "_") && previousIsWord && nextIsWord
        guard canOpen || canClose, !isInsideWord else { return nil }
        flush(style: style, firstSpan: firstSpan)
        if canOpen {
            marked.formUnion(emphasis)
            style.formUnion(emphasis)
        } else {
            marked.subtract(emphasis)
            style.subtract(emphasis)
        }
        return length
    }

    private struct Tag {
        let emphasis: DiagramTextStyle
        let isHTMLTag: Bool
        let isClosing: Bool
        let length: Int
    }

    /// Pele's `RE_TAG` at `index`: its emphasis, whether it is one of HTML's tags, whether it closes, its length.
    private static func tag(_ bytes: UnsafeBufferPointer<UInt8>, _ end: Int, at index: Int) -> Tag? {
        var position = index + 1
        let isClosing = position < end && bytes[position] == UInt8(ascii: "/")
        if isClosing { position += 1 }
        guard position < end, bytes[position] | 0x20 >= UInt8(ascii: "a"), bytes[position] | 0x20 <= UInt8(ascii: "z") else { return nil }
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
        let emphasis: DiagramTextStyle
        let isHTMLTag: Bool
        if nameLength <= 8 {
            emphasis = FlatTagNames.emphasis[packedName] ?? []
            isHTMLTag = FlatTagNames.htmlTags.contains(packedName)
        } else {
            let name = String(decoding: UnsafeBufferPointer(rebasing: bytes[nameStart..<(nameStart + nameLength)]), as: UTF8.self).lowercased()
            emphasis = DiagramLabelInlineMarkup.emphasisByTag[name] ?? []
            isHTMLTag = DiagramLabelInlineMarkup.htmlTagNames.contains(name)
        }
        return Tag(emphasis: emphasis, isHTMLTag: isHTMLTag, isClosing: isClosing, length: position + 1 - index)
    }

    static func isWordByte(_ byte: UInt8) -> Bool {
        (byte | 0x20 >= UInt8(ascii: "a") && byte | 0x20 <= UInt8(ascii: "z")) || (byte >= UInt8(ascii: "0") && byte <= UInt8(ascii: "9")) || byte == UInt8(ascii: "_")
    }

    // MARK: Spans, icons and codes

    /// Pele's `pushIcons` then `pushPlain` for the pending text in `style`.
    private mutating func flush(style: DiagramTextStyle, firstSpan: Int) {
        defer { pending.removeAll(keepingCapacity: true) }
        guard !pending.isEmpty else { return }
        let text = pending
        text.withUnsafeBufferPointer { text in
            var kept = 0
            var searchStart = 0
            while let name = Self.nextIconName(text, from: searchStart) {
                appendText(text, kept, name.lowerBound, style: style, firstSpan: firstSpan)
                kept = name.upperBound
                searchStart = name.upperBound
                if kept < text.count, text[kept] == UInt8(ascii: " ") {
                    kept += 1
                } else if kept == text.count, spans.count > firstSpan {
                    let lastIndex = spans.count - 1
                    var trimmedEnd = Int(spans[lastIndex].end)
                    let spanStart = Int(spans[lastIndex].start)
                    while trimmedEnd > spanStart, case let length = output.withUnsafeBufferPointer({ bytes in
                        JavaScriptWhitespace.lengthOfLast(in: bytes[spanStart..<trimmedEnd]) }), length > 0 {
                        trimmedEnd -= length
                    }
                    spans[lastIndex].end = Int32(trimmedEnd)
                    output.removeSubrange(trimmedEnd...)
                }
            }
            appendText(text, kept, text.count, style: style, firstSpan: firstSpan)
        }
    }

    private static func iconPrefixLength(_ text: UnsafeBufferPointer<UInt8>, at index: Int) -> Int? {
        guard index + 1 < text.count, text[index] == UInt8(ascii: "f"), text[index + 1] == UInt8(ascii: "a") else { return nil }
        var colon = index + 2
        if colon < text.count, "bklrs".utf8.contains(text[colon]) { colon += 1 }
        guard colon + 3 < text.count, text[colon] == UInt8(ascii: ":"), text[colon + 1] == UInt8(ascii: "f"), text[colon + 2] == UInt8(ascii: "a"),
              text[colon + 3] == UInt8(ascii: "-") else { return nil }
        return colon + 4 - index
    }

    private static func nextIconName(_ text: UnsafeBufferPointer<UInt8>, from start: Int) -> Range<Int>? {
        var index = start
        while index < text.count {
            if let prefix = iconPrefixLength(text, at: index) {
                var end = index + prefix
                while end < text.count, isWordByte(text[end]) || text[end] == UInt8(ascii: "-") { end += 1 }
                if end > index + prefix { return index..<end }
            }
            index += 1
        }
        return nil
    }

    /// `text[start..<end]` with its codes read, joined to the line's last span when that has the same emphasis.
    private mutating func appendText(_ text: UnsafeBufferPointer<UInt8>, _ start: Int, _ end: Int, style: DiagramTextStyle, firstSpan: Int) {
        guard start < end else { return }
        let spanStart = Int32(output.count)
        appendDecodingEntities(text, start, end)
        if spans.count > firstSpan, spans[spans.count - 1].style == style {
            spans[spans.count - 1].end = Int32(output.count)
        } else {
            spans.append(FlatLabelSpan(start: spanStart, end: Int32(output.count), style: style))
        }
    }

    private mutating func appendDecodingEntities(_ text: UnsafeBufferPointer<UInt8>, _ start: Int, _ end: Int) {
        var hasSemicolon = false, hasCodeStart = false
        for index in start..<end {
            let byte = text[index]
            if byte == UInt8(ascii: ";") { hasSemicolon = true } else if byte == UInt8(ascii: "#") || byte == UInt8(ascii: "&") { hasCodeStart = true }
        }
        guard hasSemicolon, hasCodeStart else {
            output.append(contentsOf: UnsafeBufferPointer(rebasing: text[start..<end]))
            return
        }
        // Mermaid's `#…;` as HTML's code first, then HTML's codes read, as Pele does.
        entityScratch.removeAll(keepingCapacity: true)
        var index = start
        while index < end {
            if text[index] == UInt8(ascii: "#") {
                var wordEnd = index + 1
                var isNumber = true
                while wordEnd < end, Self.isWordByte(text[wordEnd]) {
                    if text[wordEnd] < UInt8(ascii: "0") || text[wordEnd] > UInt8(ascii: "9") { isNumber = false }
                    wordEnd += 1
                }
                if wordEnd > index + 1, wordEnd < end, text[wordEnd] == UInt8(ascii: ";") {
                    entityScratch.append(UInt8(ascii: "&"))
                    if isNumber { entityScratch.append(UInt8(ascii: "#")) }
                    entityScratch.append(contentsOf: UnsafeBufferPointer(rebasing: text[(index + 1)...wordEnd]))
                    index = wordEnd + 1
                    continue
                }
            }
            entityScratch.append(text[index])
            index += 1
        }
        let codes = entityScratch
        codes.withUnsafeBufferPointer { codes in
            var index = 0
            while index < codes.count {
                if codes[index] == UInt8(ascii: "&"), let end = appendCode(codes, at: index) {
                    index = end
                    continue
                }
                output.append(codes[index])
                index += 1
            }
        }
    }

    /// The code at `start` (an `&`) read into the output, and the position after it; nil where no code starts.
    private mutating func appendCode(_ codes: UnsafeBufferPointer<UInt8>, at start: Int) -> Int? {
        let body = start + 1
        guard body < codes.count else { return nil }
        func run(from position: Int, while belongs: (UInt8) -> Bool) -> Int {
            var end = position
            while end < codes.count, belongs(codes[end]) { end += 1 }
            return end
        }
        let isDigit = { (byte: UInt8) in byte >= UInt8(ascii: "0") && byte <= UInt8(ascii: "9") }
        if codes[body] == UInt8(ascii: "#") {
            let end = run(from: body + 1, while: isDigit)
            if end > body + 1, end < codes.count, codes[end] == UInt8(ascii: ";") {
                appendCharacter(numbered: codes, body + 1, end, radix: 10, code: start...end)
                return end + 1
            }
            let digits = body + 2
            guard digits < codes.count, codes[body + 1] | 0x20 == UInt8(ascii: "x") else { return nil }
            let hexEnd = run(from: digits) { byte in Self.hexadecimalValue(byte) != nil }
            guard hexEnd > digits, hexEnd < codes.count, codes[hexEnd] == UInt8(ascii: ";") else { return nil }
            appendCharacter(numbered: codes, digits, hexEnd, radix: 16, code: start...hexEnd)
            return hexEnd + 1
        }
        let end = run(from: body, while: Self.isWordByte)
        guard end > body, end < codes.count, codes[end] == UInt8(ascii: ";") else { return nil }
        let name = String(decoding: UnsafeBufferPointer(rebasing: codes[body..<end]), as: UTF8.self)
        if let named = DiagramLabelEntityNames.character(named: name) {
            appendScalar(named)
        } else {
            output.append(contentsOf: UnsafeBufferPointer(rebasing: codes[start...end]))
        }
        return end + 1
    }

    private mutating func appendCharacter(numbered codes: UnsafeBufferPointer<UInt8>, _ start: Int, _ end: Int, radix: UInt32, code: ClosedRange<Int>) {
        var value: UInt32 = 0
        for index in start..<end {
            guard let digit = Self.hexadecimalValue(codes[index]), value <= (0x10FFFF - digit) / radix else {
                output.append(contentsOf: UnsafeBufferPointer(rebasing: codes[code]))
                return
            }
            value = value * radix + digit
        }
        guard value > 0, let scalar = Unicode.Scalar(value) else {
            output.append(contentsOf: UnsafeBufferPointer(rebasing: codes[code]))
            return
        }
        appendScalar(scalar)
    }

    private mutating func appendScalar(_ scalar: Unicode.Scalar) {
        UTF8.encode(scalar) { byte in output.append(byte) }
    }

    private static func hexadecimalValue(_ byte: UInt8) -> UInt32? {
        switch byte {
        case UInt8(ascii: "0")...UInt8(ascii: "9"): UInt32(byte) - 48
        case UInt8(ascii: "a")...UInt8(ascii: "f"): UInt32(byte) - 87
        case UInt8(ascii: "A")...UInt8(ascii: "F"): UInt32(byte) - 55
        default: nil
        }
    }
}

/// Tag names of at most eight bytes, lower case, packed into a number: Pele's emphasis tags and HTML's tags.
enum FlatTagNames {
    static func packed(_ name: String) -> UInt64 {
        var value: UInt64 = 0
        for (offset, byte) in name.utf8.enumerated() where offset < 8 { value |= UInt64(byte) << UInt64(8 * offset) }
        return value
    }

    static let emphasis: [UInt64: DiagramTextStyle] = Dictionary(uniqueKeysWithValues: DiagramLabelInlineMarkup.emphasisByTag.map { name, style in
        (packed(name), style)
    })
    static let htmlTags: Set<UInt64> = Set(DiagramLabelInlineMarkup.htmlTagNames.filter { name in name.utf8.count <= 8 }.map(packed))
}
