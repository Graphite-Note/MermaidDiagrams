/**
 * File: UseCaseMeasuredLabels.swift
 * ---------------------------------
 * Layer: Core
 * Description: Measures a use case diagram's labels from the ranges of its text, as UseCaseTextLabel measures their
 *              Strings: a plain label of printable ASCII trimmed on its bytes and measured, wrapped where it passes its
 *              room, with no String, label or trimmed copy made; a Markdown one through the flat Markdown measuring; any
 *              other label, and one of nothing but white space, as before.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 26/11/2026
 */

import CoreGraphics

/// The lines of a use case diagram's labels, measured one label at a time and made into its block at once: the list is
/// kept, emptied for each label, so that its memory is made once a layout.
struct UseCaseMeasuredLabels {
    private var lines = DiagramMeasuredLines()

    /// `label`, a range of `bytes`, measured in `measurer` and wrapped at `room`: the block
    /// `UseCaseTextLabel.block(String(decoding: bytes[label.text]), labelType: label.type, measurer:, room:)` makes.
    mutating func block<Measurer: DiagramTextMeasuring>(_ label: UseCaseLabelText, in bytes: UnsafeBufferPointer<UInt8>, measurer: Measurer,
                                                        room: CGFloat) -> DiagramTextBlock {
        precondition(label.text.start >= 0 && label.text.start <= label.text.end && Int(label.text.end) <= bytes.count, "label outside its text")
        guard !label.text.isEmpty else { return UseCaseTextLabel.empty(measurer) }
        lines.removeAll()
        let flat = DiagramFlatMeasurer(measurer)
        #if DEBUG
        // The tests that check every text the corpora measure watch the decoder, which the fast path does not call.
        if label.type == .markdown, DiagramLabelDecodingObservation.observer != nil {
            _ = DiagramLabelDecoder.label(fromUTF8: UnsafeBufferPointer(rebasing: bytes[Int(label.text.start)..<Int(label.text.end)]), form: .markdown)
        }
        #endif
        let measured: DiagramMeasuredText? = label.type == .markdown
            ? DiagramFlatTextMeasuring.measure(markdown: bytes, label.text, measurer: flat, maximumWidth: room, into: &lines)
            : Self.plainOnFastPath(bytes, label.text, measurer: flat, room: room, into: &lines)
        // A text of no line is one empty line, as the String's block makes it; it takes the String's way.
        guard let measured, measured.lineCount > 0 else {
            let text = String(decoding: UnsafeBufferPointer(rebasing: bytes[Int(label.text.start)..<Int(label.text.end)]), as: UTF8.self)
            return UseCaseTextLabel.block(text, labelType: label.type, measurer: measurer, room: room)
        }
        return DiagramTextBlock(measured, of: lines, source: bytes)
    }

    /// A plain label on the fast path, or nil: its bytes trimmed of ASCII white space, printable ASCII, not both a `#`
    /// and a `;` (which may write one of Mermaid's codes), in a measurer whose advances are known, wrapped only in a face
    /// whose advances sum exactly. Such a label is the one line the String's trimmed text is, measured as a block
    /// measures that line.
    static func plainOnFastPath<Measurer>(_ bytes: UnsafeBufferPointer<UInt8>, _ range: MermaidTextRange, measurer: DiagramFlatMeasurer<Measurer>,
                                          room: CGFloat, into lines: inout DiagramMeasuredLines) -> DiagramMeasuredText? {
        guard let advances = measurer.advances, let base = bytes.baseAddress else { return nil }
        var start = Int(range.start)
        var end = Int(range.end)
        var hasNumberSign = false
        var hasSemicolon = false
        for index in start..<end {
            if base[index] == UInt8(ascii: "#") { hasNumberSign = true } else if base[index] == UInt8(ascii: ";") { hasSemicolon = true }
        }
        guard !(hasNumberSign && hasSemicolon) else { return nil }
        while start < end, DiagramFlatTextMeasuring.isWhitespace(base[start]) { start += 1 }
        while end > start, DiagramFlatTextMeasuring.isWhitespace(base[end - 1]) { end -= 1 }
        guard start < end else { return nil }
        let (width, kinds) = DiagramFlatLineScanning.measured(base, from: start, to: end, advances: advances)
        guard !kinds.contains(.unprintable) else { return nil }
        let firstLine = lines.count
        if !(width > room) || !kinds.contains(.space) {
            lines.appendLine(start: start, end: end, width: width)
        } else {
            guard advances.isExactlySummable, end - start < DiagramFlatTextWrapping.longestWrappedByteCount else { return nil }
            DiagramFlatTextWrapping.wrap(base, from: start, to: end, advances: advances.byByte, maximumWidth: room, into: &lines)
        }
        let lineCount = lines.count - firstLine
        var widest: CGFloat = 0
        for index in firstLine..<lines.count where index == firstLine || widest < lines[index].width { widest = lines[index].width }
        let lineHeight = lineCount > 1 ? measurer.severalLinesHeight : measurer.singleLineHeight
        return DiagramMeasuredText(firstLine: Int32(firstLine), lineCount: Int32(lineCount), width: widest, height: CGFloat(lineCount) * lineHeight,
                                   lineHeight: lineHeight, fontSize: measurer.fontSize)
    }
}
