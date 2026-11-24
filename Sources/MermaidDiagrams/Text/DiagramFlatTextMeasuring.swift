/**
 * File: DiagramFlatTextMeasuring.swift
 * ------------------------------------
 * Layer: Core
 * Description: Measures a text straight from a range of its source's bytes into a layout's list of lines, as
 *              DiagramLabelDecoder and DiagramTextBlock measure it: printable ASCII that Pele reads without markup but
 *              its line breaks on a fast path over the bytes, any other text through the label and the block, its lines
 *              copied.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 24/11/2026
 */

import CoreGraphics

/// A measurer as the flat measuring reads it, made once per layout: the measurer, for the full path, and the advances
/// the fast path adds up, which only Core Text's measurer has.
struct DiagramFlatMeasurer<Measurer: DiagramTextMeasuring> {
    let measurer: Measurer
    /// The advances of printable ASCII, or nil: every text then takes the full path.
    let advances: DiagramFontAdvances?
    let fontSize: CGFloat
    /// The line height of a text of one line, the measurer's; a text of several lines has `severalLinesHeight`.
    let singleLineHeight: CGFloat
    let severalLinesHeight: CGFloat

    init(_ measurer: Measurer) {
        self.measurer = measurer
        advances = (measurer as? CoreTextDiagramTextMeasurer)?.printableASCIIAdvances
        fontSize = measurer.fontSize
        singleLineHeight = measurer.lineHeight
        severalLinesHeight = (measurer.fontSize * DiagramTextBlock.severalLinesHeightRatio).rounded()
    }
}

/// Measures texts from their source's bytes into `DiagramMeasuredLines`, the same lines, widths and sizes to the bit as
/// `DiagramTextBlock(label: DiagramLabelDecoder.label(from: text, form: form), measurer:, maximumWidth:)`.
///
/// The fast path takes a plain or literal text whose bytes are ASCII: trimmed of white space, split where Pele's
/// `RE_BREAK` matches (`<br\s*/?>` in any case, a written `\n` or `\N`, a line feed), each line trimmed, made of
/// printable ASCII only and, when it holds a byte that may start markup, unmarked (`DiagramLabelLineBreaks.isUnmarked`).
/// Each line's width is its advances added from its first byte, as a block adds them; a line wider than the room that
/// holds a space wraps in a face whose advances sum exactly (`DiagramFlatTextWrapping`). Any other text (Markdown, an
/// entity, a tag, emphasis, a byte past ASCII, a line to wrap in a face that does not sum exactly) takes the full path.
enum DiagramFlatTextMeasuring {
    /// `bytes[range]` measured and wrapped at `maximumWidth`, its lines appended to `lines`.
    static func measure<Measurer>(_ bytes: UnsafeBufferPointer<UInt8>, _ range: MermaidTextRange, form: DiagramLabelDecoder.Form,
                                  measurer: DiagramFlatMeasurer<Measurer>, maximumWidth: CGFloat, into lines: inout DiagramMeasuredLines)
        -> DiagramMeasuredText {
        checkRange(range, of: bytes)
        if let measured = measuredOnFastPath(bytes, range, form: form, measurer: measurer, maximumWidth: maximumWidth, into: &lines) { return measured }
        return measuredOnFullPath(bytes, range, form: form, measurer: measurer, maximumWidth: maximumWidth, into: &lines)
    }

    /// `bytes[range]` wrapped at spaces to `wrappingWidth`, each line still wider than `breakingWidth` broken between
    /// characters, as `DiagramTextBlock(label:measurer:wrappingWidth:breakingWidth:)` sets a kanban card's text. Text
    /// whose wrapped lines all fit `breakingWidth`, most of it, stays on the fast path; a line to break takes the full path.
    static func measureBreakingCharacters<Measurer>(_ bytes: UnsafeBufferPointer<UInt8>, _ range: MermaidTextRange, form: DiagramLabelDecoder.Form,
                                                    measurer: DiagramFlatMeasurer<Measurer>, wrappingWidth: CGFloat, breakingWidth: CGFloat,
                                                    into lines: inout DiagramMeasuredLines) -> DiagramMeasuredText {
        checkRange(range, of: bytes)
        let firstLine = lines.count
        if let measured = measuredOnFastPath(bytes, range, form: form, measurer: measurer, maximumWidth: wrappingWidth, into: &lines) {
            guard measured.lineIndices.contains(where: { index in lines[index].width > breakingWidth }) else { return measured }
            lines.removeLines(from: firstLine)
        }
        let label = decodedLabel(bytes, range, form: form)
        let block = DiagramTextBlock(label: label, measurer: measurer.measurer, wrappingWidth: wrappingWidth, breakingWidth: breakingWidth)
        return copied(block, into: &lines)
    }

    /// The range checked against its source: within it, and below the offsets of derived bytes.
    private static func checkRange(_ range: MermaidTextRange, of bytes: UnsafeBufferPointer<UInt8>) {
        precondition(range.start >= 0 && range.start <= range.end && Int(range.end) <= bytes.count, "text range outside its source")
        precondition(bytes.count < Int(DiagramMeasuredLines.derivedOffset), "source too long for measured lines' offsets")
    }

    /// The text measured on the fast path, or nil, with no line added, when it is not on it.
    static func measuredOnFastPath<Measurer>(_ bytes: UnsafeBufferPointer<UInt8>, _ range: MermaidTextRange, form: DiagramLabelDecoder.Form,
                                             measurer: DiagramFlatMeasurer<Measurer>, maximumWidth: CGFloat,
                                             into lines: inout DiagramMeasuredLines) -> DiagramMeasuredText? {
        guard form != .markdown, let base = bytes.baseAddress else {
            return range.isEmpty && form != .markdown ? emptyText(lines: lines, measurer: measurer) : nil
        }
        var start = Int(range.start)
        var end = Int(range.end)
        while start < end, isWhitespace(base[start]) { start += 1 }
        while end > start, isWhitespace(base[end - 1]) { end -= 1 }
        guard start < end else { return emptyText(lines: lines, measurer: measurer) }
        guard let advances = measurer.advances else { return nil }
        let firstLine = lines.count
        guard measureLines(base, start, end, advances: advances, maximumWidth: maximumWidth, isLiteral: form == .literal, into: &lines) else {
            return leftFastPath(&lines, firstLine)
        }
        let lineCount = lines.count - firstLine
        // A label whose lines are all empty (breaks alone) has nothing to draw, and a block gives it no line.
        guard (firstLine..<lines.count).contains(where: { index in lines[index].end > lines[index].start }) else {
            lines.removeLines(from: firstLine)
            return emptyText(lines: lines, measurer: measurer)
        }
        var widest: CGFloat = 0
        for index in firstLine..<lines.count where index == firstLine || widest < lines[index].width { widest = lines[index].width }
        let lineHeight = lineCount > 1 ? measurer.severalLinesHeight : measurer.singleLineHeight
        return DiagramMeasuredText(firstLine: Int32(firstLine), lineCount: Int32(lineCount), width: widest, height: CGFloat(lineCount) * lineHeight,
                                   lineHeight: lineHeight, fontSize: measurer.fontSize)
    }

    /// The lines of the trimmed text `bytes[start..<end]`, split at its breaks, each measured and wrapped; false, with
    /// lines added that the caller takes out, when one is not on the fast path.
    private static func measureLines(_ base: UnsafePointer<UInt8>, _ start: Int, _ end: Int, advances: DiagramFontAdvances, maximumWidth: CGFloat,
                                     isLiteral: Bool, into lines: inout DiagramMeasuredLines) -> Bool {
        var lineStart = start
        var searchStart = start
        while true {
            let candidate = DiagramFlatLineScanning.nextBreakCandidate(base, from: searchStart, to: end)
            guard candidate < end else { break }
            let breakLength = Self.breakLength(base, end, at: candidate)
            guard breakLength > 0 else {
                searchStart = candidate + 1
                continue
            }
            guard measureLine(base, lineStart, candidate, advances: advances, maximumWidth: maximumWidth, isLiteral: isLiteral, into: &lines) else {
                return false
            }
            lineStart = candidate + breakLength
            searchStart = lineStart
        }
        return measureLine(base, lineStart, end, advances: advances, maximumWidth: maximumWidth, isLiteral: isLiteral, into: &lines)
    }

    /// A text of no line: empty, or white space alone.
    private static func emptyText<Measurer>(lines: DiagramMeasuredLines, measurer: DiagramFlatMeasurer<Measurer>) -> DiagramMeasuredText {
        DiagramMeasuredText(firstLine: Int32(lines.count), lineCount: 0, width: 0, height: 0, lineHeight: measurer.singleLineHeight, fontSize: measurer.fontSize)
    }

    private static func leftFastPath(_ lines: inout DiagramMeasuredLines, _ firstLine: Int) -> DiagramMeasuredText? {
        lines.removeLines(from: firstLine)
        return nil
    }

    /// One line between breaks, trimmed, measured and wrapped; false when it holds markup, a control character or must
    /// wrap in a face that does not sum exactly.
    @inline(__always)
    private static func measureLine(_ bytes: UnsafePointer<UInt8>, _ writtenStart: Int, _ writtenEnd: Int, advances: DiagramFontAdvances,
                                    maximumWidth: CGFloat, isLiteral: Bool, into lines: inout DiagramMeasuredLines) -> Bool {
        var start = writtenStart
        var end = writtenEnd
        while start < end, isWhitespace(bytes[start]) { start += 1 }
        while end > start, isWhitespace(bytes[end - 1]) { end -= 1 }
        let (width, kinds) = DiagramFlatLineScanning.measured(bytes, from: start, to: end, advances: advances)
        guard !kinds.contains(.unprintable) else { return false }
        if kinds.contains(.markup), !DiagramLabelLineBreaks.isUnmarked(UnsafeBufferPointer(start: bytes + start, count: end - start), isLiteral: isLiteral) {
            return false
        }
        let hasSpace = kinds.contains(.space)
        if !(width > maximumWidth) || !hasSpace {
            lines.appendLine(start: start, end: end, width: width)
            return true
        }
        guard advances.isExactlySummable, end - start < DiagramFlatTextWrapping.longestWrappedByteCount else { return false }
        DiagramFlatTextWrapping.wrap(bytes, from: start, to: end, advances: advances.byByte, maximumWidth: maximumWidth, into: &lines)
        return true
    }

    /// JavaScript's white space among ASCII bytes: the space, and tab to carriage return.
    @inline(__always)
    static func isWhitespace(_ byte: UInt8) -> Bool {
        byte == UInt8(ascii: " ") || (byte >= 0x09 && byte <= 0x0D)
    }

    /// The length of Pele's `RE_BREAK` at `index` of ASCII bytes, or zero for none.
    @inline(__always)
    private static func breakLength(_ bytes: UnsafePointer<UInt8>, _ end: Int, at index: Int) -> Int {
        switch bytes[index] {
        case 0x0A: return 1
        case UInt8(ascii: "\\"): return index + 1 < end && (bytes[index + 1] == UInt8(ascii: "n") || bytes[index + 1] == UInt8(ascii: "N")) ? 2 : 0
        default: return DiagramLabelByteDecoder.lineBreakTagLength(UnsafeBufferPointer(start: bytes, count: end), end, at: index) ?? 0
        }
    }
}

extension DiagramFlatTextMeasuring {
    /// The text measured as the label decoder and a block measure it, its lines copied into the derived bytes.
    static func measuredOnFullPath<Measurer>(_ bytes: UnsafeBufferPointer<UInt8>, _ range: MermaidTextRange, form: DiagramLabelDecoder.Form,
                                             measurer: DiagramFlatMeasurer<Measurer>, maximumWidth: CGFloat,
                                             into lines: inout DiagramMeasuredLines) -> DiagramMeasuredText {
        let block = DiagramTextBlock(label: decodedLabel(bytes, range, form: form), measurer: measurer.measurer, maximumWidth: maximumWidth)
        return copied(block, into: &lines)
    }

    private static func decodedLabel(_ bytes: UnsafeBufferPointer<UInt8>, _ range: MermaidTextRange, form: DiagramLabelDecoder.Form) -> DiagramLabel {
        DiagramLabelDecoder.label(fromUTF8: UnsafeBufferPointer(rebasing: bytes[Int(range.start)..<Int(range.end)]), form: form)
    }

    /// `block`'s lines, widths and runs appended to `lines` as derived bytes.
    static func copied(_ block: DiagramTextBlock, into lines: inout DiagramMeasuredLines) -> DiagramMeasuredText {
        let firstLine = lines.count
        let hasEmphasis = block.record.hasEmphasis
        for index in 0..<block.lineCount {
            var runs: [(bytes: UnsafeBufferPointer<UInt8>, width: CGFloat, style: DiagramTextStyle)] = []
            if hasEmphasis {
                let (first, count) = block.runRecords(ofLine: index)
                for runIndex in 0..<count {
                    let run = block.storage.record(at: first, index: runIndex, as: DiagramTextRunRecord.self)
                    runs.append((block.storage.bytes(from: run.start, to: run.end), run.width, run.style))
                }
            }
            withExtendedLifetime(block.storage) {
                block.withUTF8(ofLine: index) { line in lines.appendDerivedLine(line, width: block.lineWidth(at: index), runs: runs) }
            }
        }
        return DiagramMeasuredText(firstLine: Int32(firstLine), lineCount: Int32(block.lineCount), width: block.size.width, height: block.size.height,
                                   lineHeight: block.lineHeight, fontSize: block.fontSize, hasEmphasis: hasEmphasis)
    }
}
