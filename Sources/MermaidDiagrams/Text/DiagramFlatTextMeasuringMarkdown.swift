/**
 * File: DiagramFlatTextMeasuringMarkdown.swift
 * --------------------------------------------
 * Layer: Core
 * Description: A Markdown string measured on the flat path when its decoding is that of plain text: written without
 *              markup, or one line of printable ASCII whose only markup bytes are underscores inside words, which
 *              Markdown keeps as written (a requirement's `REQ_001`, a field's `test_entity`); any other Markdown takes
 *              the full decoder.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 26/11/2026
 */

import CoreGraphics

extension DiagramFlatTextMeasuring {
    /// `bytes[range]`, written as a Markdown string, measured as `measure(_:_:form:measurer:maximumWidth:into:)` measures it
    /// with `form: .markdown`: the same lines, widths and size to the bit.
    ///
    /// A text without markup (`DiagramLabelLineBreaks.isUnmarked`) is decoded alike in every form, so it is measured as
    /// plain text. A text of one line of printable ASCII whose only markup bytes are underscores between two letters or
    /// digits is decoded by Markdown as itself, trimmed and without emphasis (an underscore inside a word opens nothing),
    /// so its trimmed bytes are measured, and wrapped where they pass `maximumWidth`, as one plain line. Any other text
    /// takes the full path.
    static func measure<Measurer>(markdown bytes: UnsafeBufferPointer<UInt8>, _ range: MermaidTextRange, measurer: DiagramFlatMeasurer<Measurer>,
                                  maximumWidth: CGFloat, into lines: inout DiagramMeasuredLines) -> DiagramMeasuredText {
        precondition(range.start >= 0 && range.start <= range.end && Int(range.end) <= bytes.count, "text range outside its source")
        let text = UnsafeBufferPointer(rebasing: bytes[Int(range.start)..<Int(range.end)])
        if DiagramLabelLineBreaks.isUnmarked(text, isLiteral: false) {
            return measure(bytes, range, form: .plain, measurer: measurer, maximumWidth: maximumWidth, into: &lines)
        }
        if let measured = measuredWithInnerUnderscores(bytes, range, measurer: measurer, maximumWidth: maximumWidth, into: &lines) { return measured }
        return measure(bytes, range, form: .markdown, measurer: measurer, maximumWidth: maximumWidth, into: &lines)
    }

    /// `text`, a String written as a Markdown string, measured as `measure(markdown:_:measurer:maximumWidth:into:)`
    /// measures the same bytes, its lines copied into the derived bytes.
    static func measure<Measurer>(markdownWritten text: String, measurer: DiagramFlatMeasurer<Measurer>, maximumWidth: CGFloat,
                                  into lines: inout DiagramMeasuredLines) -> DiagramMeasuredText {
        var text = text
        return text.withUTF8 { bytes in
            let measured = measure(markdown: bytes, MermaidTextRange(start: 0, end: bytes.count), measurer: measurer, maximumWidth: maximumWidth,
                                   into: &lines)
            lines.deriveLines(of: measured, source: bytes)
            return measured
        }
    }

    /// The text measured as one plain line when it is one line of printable ASCII, trimmed, whose only markup bytes are
    /// underscores each between two ASCII letters or digits; nil, with no line added, otherwise.
    private static func measuredWithInnerUnderscores<Measurer>(_ bytes: UnsafeBufferPointer<UInt8>, _ range: MermaidTextRange,
                                                               measurer: DiagramFlatMeasurer<Measurer>, maximumWidth: CGFloat,
                                                               into lines: inout DiagramMeasuredLines) -> DiagramMeasuredText? {
        guard let base = bytes.baseAddress, let advances = measurer.advances else { return nil }
        var start = Int(range.start)
        var end = Int(range.end)
        while start < end, isWhitespace(base[start]) { start += 1 }
        while end > start, isWhitespace(base[end - 1]) { end -= 1 }
        guard start < end, hasOnlyInnerUnderscores(base, from: start, to: end) else { return nil }
        let (width, kinds) = DiagramFlatLineScanning.measured(base, from: start, to: end, advances: advances)
        guard !kinds.contains(.unprintable) else { return nil }
        let firstLine = lines.count
        if !(width > maximumWidth) || !kinds.contains(.space) {
            lines.appendLine(start: start, end: end, width: width)
        } else {
            guard advances.isExactlySummable, end - start < DiagramFlatTextWrapping.longestWrappedByteCount else { return nil }
            DiagramFlatTextWrapping.wrap(base, from: start, to: end, advances: advances.byByte, maximumWidth: maximumWidth, into: &lines)
        }
        let lineCount = lines.count - firstLine
        var widest: CGFloat = 0
        for index in firstLine..<lines.count where index == firstLine || widest < lines[index].width { widest = lines[index].width }
        let lineHeight = lineCount > 1 ? measurer.severalLinesHeight : measurer.singleLineHeight
        return DiagramMeasuredText(firstLine: Int32(firstLine), lineCount: Int32(lineCount), width: widest, height: CGFloat(lineCount) * lineHeight,
                                   lineHeight: lineHeight, fontSize: measurer.fontSize)
    }

    /// Whether `bytes[start..<end]` holds only ASCII, at least one underscore, each between two ASCII letters or digits,
    /// and none of the other bytes the label decoder reads as markup (`DiagramLabelLineBreaks.isUnmarked`'s: line feed,
    /// `#`, `&`, `*`, `:`, `<` and backslash).
    private static func hasOnlyInnerUnderscores(_ bytes: UnsafePointer<UInt8>, from start: Int, to end: Int) -> Bool {
        var underscoreCount = 0
        for index in start..<end {
            switch bytes[index] {
            case UInt8(ascii: "_"):
                guard index > start, index + 1 < end, isLetterOrDigit(bytes[index - 1]), isLetterOrDigit(bytes[index + 1]) else { return false }
                underscoreCount += 1
            case UInt8(ascii: "\n"), UInt8(ascii: "#"), UInt8(ascii: "&"), UInt8(ascii: "*"), UInt8(ascii: ":"), UInt8(ascii: "<"), UInt8(ascii: "\\"):
                return false
            case 0x80...:
                return false
            default:
                continue
            }
        }
        return underscoreCount > 0
    }

    private static func isLetterOrDigit(_ byte: UInt8) -> Bool {
        (byte >= UInt8(ascii: "a") && byte <= UInt8(ascii: "z")) || (byte >= UInt8(ascii: "A") && byte <= UInt8(ascii: "Z"))
            || (byte >= UInt8(ascii: "0") && byte <= UInt8(ascii: "9"))
    }
}
