/**
 * File: DiagramLabelByteDecoder.swift
 * -----------------------------------
 * Layer: Core
 * Description: Reads the bytes written for a label with markup into its lines and spans of decoded bytes, as Pele's
 *              layoutLabel reads its text: line breaks, a Markdown string's carriage returns and indentation, a journey's
 *              and a timeline's literal text, each line trimmed; then each line's markup (`DiagramLabelByteMarkup`).
 *
 * Authors: Bahey Shalash
 * Version: 0.2
 * Date: 25/11/2026
 */

/// A label's decoded bytes and their lines and spans, as offsets into `output`, kept by a thread and reused. Every
/// character the decoding looks for is ASCII, so it works on bytes: a character beyond ASCII is only ever copied, and
/// white space beyond ASCII is found by its bytes (`JavaScriptWhitespace`). A String is made only for an entity's name
/// and for a tag name longer than eight bytes.
struct DiagramLabelByteDecoder {
    var output: [UInt8] = []
    var lines: [DiagramLabelLineRecord] = []
    var spans: [DiagramLabelSpanRecord] = []
    /// The text being read once prepared: literal text written out, or a Markdown string's source.
    var prepared: [UInt8] = []
    /// Text of the line read since the last markup, and Mermaid's codes written as HTML's.
    var pending: [UInt8] = []
    var codes: [UInt8] = []
    var lineRanges: [Range<Int>] = []

    /// The label `bytes` are written for, text with markup, in the thread's text storage.
    mutating func label(of bytes: UnsafeBufferPointer<UInt8>, form: DiagramLabelDecoder.Form) -> DiagramLabel {
        output.removeAll(keepingCapacity: true)
        lines.removeAll(keepingCapacity: true)
        spans.removeAll(keepingCapacity: true)
        prepared.removeAll(keepingCapacity: true)
        if form == .literal { Self.appendLiteralText(bytes, to: &prepared) } else { prepared.append(contentsOf: bytes) }
        if form == .markdown { prepareMarkdownSource() }
        var hasEmphasis = false
        let source = prepared
        source.withUnsafeBufferPointer { source in
            let range = form == .markdown ? 0..<source.count : DiagramLabelByteScanning.trimmed(source, 0..<source.count)
            splitLines(source, range)
            var open: DiagramTextStyle = []
            for line in lineRanges {
                if readLine(source, DiagramLabelByteScanning.trimmed(source, line), isMarkdown: form == .markdown, open: &open) { hasEmphasis = true }
            }
        }
        return output.withUnsafeBufferPointer { output in
            DiagramLabelWriting.label(decoded: output, lines: lines, spans: hasEmphasis ? spans : nil)
        }
    }

    /// The ranges of the lines of `source[range]`, split where Pele's `RE_BREAK` (`<br\s*\/?>|\\n|\n`, in any case)
    /// matches.
    private mutating func splitLines(_ source: UnsafeBufferPointer<UInt8>, _ range: Range<Int>) {
        lineRanges.removeAll(keepingCapacity: true)
        var lineStart = range.lowerBound
        var index = range.lowerBound
        while index < range.upperBound {
            if let length = Self.breakLength(source, range.upperBound, at: index) {
                lineRanges.append(lineStart..<index)
                index += length
                lineStart = index
            } else {
                index += 1
            }
        }
        lineRanges.append(lineStart..<range.upperBound)
    }

    /// The length of a break at `index`, or nil: a line feed, a backslash and `n` or `N` as written, or `<br>`.
    private static func breakLength(_ bytes: UnsafeBufferPointer<UInt8>, _ end: Int, at index: Int) -> Int? {
        switch bytes[index] {
        case UInt8(ascii: "\n"): 1
        case UInt8(ascii: "\\"): index + 1 < end && (bytes[index + 1] == UInt8(ascii: "n") || bytes[index + 1] == UInt8(ascii: "N")) ? 2 : nil
        case UInt8(ascii: "<"): lineBreakTagLength(bytes, end, at: index)
        default: nil
        }
    }

    /// The length of `<br\s*\/?>`, in any case, at `index`, or nil.
    static func lineBreakTagLength(_ bytes: UnsafeBufferPointer<UInt8>, _ end: Int, at index: Int) -> Int? {
        guard index + 3 < end, bytes[index] == UInt8(ascii: "<"), bytes[index + 1] | 0x20 == UInt8(ascii: "b"),
              bytes[index + 2] | 0x20 == UInt8(ascii: "r") else { return nil }
        var position = index + 3
        while case let length = JavaScriptWhitespace.length(in: bytes[..<end], at: position), length > 0 { position += length }
        if position < end, bytes[position] == UInt8(ascii: "/") { position += 1 }
        guard position < end, bytes[position] == UInt8(ascii: ">") else { return nil }
        return position + 1 - index
    }

    /// Pele's `plainLabel`, a journey's and a timeline's text: each `<` that starts no `<br>` written `&lt;`, each `:fa-`
    /// written `&colon;fa-`, so that tags and icon names show as written.
    private static func appendLiteralText(_ bytes: UnsafeBufferPointer<UInt8>, to result: inout [UInt8]) {
        guard bytes.contains(UInt8(ascii: "<")) || bytes.contains(UInt8(ascii: ":")) else { return result.append(contentsOf: bytes) }
        result.reserveCapacity(bytes.count + 8)
        for index in bytes.indices {
            let byte = bytes[index]
            if byte == UInt8(ascii: "<"), lineBreakTagLength(bytes, bytes.count, at: index) == nil {
                result.append(contentsOf: "&lt;".utf8)
            } else if byte == UInt8(ascii: ":"), index + 3 < bytes.count, bytes[index + 1] == UInt8(ascii: "f"), bytes[index + 2] == UInt8(ascii: "a"),
                      bytes[index + 3] == UInt8(ascii: "-") {
                result.append(contentsOf: "&colon;".utf8)
            } else {
                result.append(byte)
            }
        }
    }

    /// A Markdown string's source as Pele reads it before its lines (text/label.ts `dedent`): carriage returns as line
    /// breaks, the indentation all its lines with text share taken off each line, and the whole trimmed.
    private mutating func prepareMarkdownSource() {
        // Most Markdown text is one line written without indentation, as a requirement's `checkout_req` is: with no
        // carriage return and a line of text that starts without white space, no indentation is shared and the text is
        // only trimmed, which needs no copy when there is nothing to trim.
        if let kept = prepared.withUnsafeBufferPointer({ bytes in Self.rangeKeptWithoutDedenting(bytes) }) {
            if kept != 0..<prepared.count { prepared = Array(prepared[kept]) }
            return
        }
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
        let dedented = normalized.withUnsafeBufferPointer { bytes in Self.dedented(bytes) }
        prepared = dedented.withUnsafeBufferPointer { bytes in Array(bytes[DiagramLabelByteScanning.trimmed(bytes, 0..<bytes.count)]) }
    }

    /// The trimmed range of `bytes` when dedenting them changes nothing: no carriage return, and a line that holds text
    /// from its first byte, so that the indentation shared by the lines with text is none; nil otherwise.
    private static func rangeKeptWithoutDedenting(_ bytes: UnsafeBufferPointer<UInt8>) -> Range<Int>? {
        var hasUnindentedLine = false
        var lineStart = 0
        for position in 0...bytes.count {
            if position < bytes.count {
                let byte = bytes[position]
                if byte == UInt8(ascii: "\r") { return nil }
                guard byte == UInt8(ascii: "\n") else { continue }
            }
            if !hasUnindentedLine, position > lineStart, JavaScriptWhitespace.length(in: bytes[..<position], at: lineStart) == 0 {
                hasUnindentedLine = true
            }
            lineStart = position + 1
        }
        return hasUnindentedLine ? DiagramLabelByteScanning.trimmed(bytes, 0..<bytes.count) : nil
    }

    /// The lines of `bytes` with the indentation shared by the lines that hold text taken off, counted in characters of
    /// white space, as Pele counts it.
    private static func dedented(_ bytes: UnsafeBufferPointer<UInt8>) -> [UInt8] {
        var lines: [(range: Range<Int>, indentEnds: [Int])] = []
        var lineStart = 0
        for position in 0...bytes.count where position == bytes.count || bytes[position] == UInt8(ascii: "\n") {
            var indentEnds: [Int] = []
            var cursor = lineStart
            while case let length = JavaScriptWhitespace.length(in: bytes[..<position], at: cursor), length > 0 {
                cursor += length
                indentEnds.append(cursor)
            }
            lines.append((lineStart..<position, indentEnds))
            lineStart = position + 1
        }
        let shared = lines.filter { line in (line.indentEnds.last ?? line.range.lowerBound) < line.range.upperBound }.map(\.indentEnds.count).min() ?? 0
        guard shared > 0 else { return Array(bytes) }
        var dedented: [UInt8] = []
        dedented.reserveCapacity(bytes.count)
        for (index, line) in lines.enumerated() {
            if index > 0 { dedented.append(UInt8(ascii: "\n")) }
            let dropped = min(shared, line.indentEnds.count)
            dedented.append(contentsOf: bytes[(dropped == 0 ? line.range.lowerBound : line.indentEnds[dropped - 1])..<line.range.upperBound])
        }
        return dedented
    }
}

/// White space at the ends of a range of bytes, as JavaScript's `trim` finds it.
enum DiagramLabelByteScanning {
    /// `range` without JavaScript's white space at either end, a character beyond ASCII taken whole.
    static func trimmed(_ bytes: UnsafeBufferPointer<UInt8>, _ range: Range<Int>) -> Range<Int> {
        let start = JavaScriptWhitespace.endOfRun(in: bytes[..<range.upperBound], from: range.lowerBound)
        var end = range.upperBound
        while end > start, case let length = JavaScriptWhitespace.lengthOfLast(in: bytes[start..<end]), length > 0 { end -= length }
        return start..<end
    }
}
