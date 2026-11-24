/**
 * File: DiagramTextBlockMeasuring.swift
 * -------------------------------------
 * Layer: Core
 * Description: Measures a label into a text block as Pele's layoutLabel does, each span in its emphasis, wrapping a line
 *              wider than a width between its pieces; a label of one line that needs no wrapping becomes a block of its
 *              own bytes, with nothing written.
 *
 * Authors: Bahey Shalash
 * Version: 0.2
 * Date: 24/11/2026
 */

import CoreGraphics

extension DiagramTextBlock {
    /// Measures `label` in `measurer`'s font, each span in its emphasis, as Pele's `layoutLabel` measures it, and
    /// wraps a line wider than `maximumWidth` between its pieces (`DiagramTextLineWrapping`). A word wider than that stays
    /// whole on its own line. An empty label has no lines.
    init(label: DiagramLabel, measurer: some DiagramTextMeasuring, maximumWidth: CGFloat) {
        self = Self.measured(label, measurer: measurer, maximumWidth: maximumWidth)
        #if DEBUG
        DiagramTextBlockObservation.observer?(DiagramTextBlockObservation.Measuring(label: label, measurer: measurer, maximumWidth: maximumWidth,
                                                                                    breakingWidth: nil, block: self))
        #endif
    }

    private static func measured(_ label: DiagramLabel, measurer: some DiagramTextMeasuring, maximumWidth: CGFloat) -> DiagramTextBlock {
        let record = label.record
        if record.flags.contains(.isOneLine) {
            // Most labels: one line without emphasis that fits or cannot break, measured from its bytes where they are.
            guard record.first != record.end else {
                return DiagramTextBlock(storage: label.storage, record: .empty, fontSize: measurer.fontSize, lineHeight: measurer.lineHeight)
            }
            let bytes = label.storage.bytes(from: record.first, to: record.end)
            let width = DiagramTextMeasuringWidths.width(of: bytes, measurer: measurer)
            if !(width > maximumWidth) || !DiagramTextMeasuringWidths.canBreak(bytes, isReadWithoutMarkup: label.isReadWithoutMarkup) {
                return DiagramTextBlock(storage: label.storage, record: DiagramTextRecord(first: record.first, end: record.end, lineCount: 1, isOneLine: true,
                                                                                          hasEmphasis: false, widestLineWidth: width),
                                        fontSize: measurer.fontSize, lineHeight: measurer.lineHeight)
            }
        }
        return DiagramTextThreadState.current.withMeasuringScratch { scratch in
            scratch.measure(label, measurer: measurer, maximumWidth: maximumWidth)
        }
    }
}

#if DEBUG
/// What the tests watch of every label measured into a block in a debug build: the label, the measurer, the widths and
/// the block made, so that every block of every corpus is checked against the measuring it replaces.
enum DiagramTextBlockObservation {
    struct Measuring {
        let label: DiagramLabel
        let measurer: any DiagramTextMeasuring
        let maximumWidth: CGFloat
        let breakingWidth: CGFloat?
        let block: DiagramTextBlock
    }

    nonisolated(unsafe) static var observer: ((Measuring) -> Void)?
}
#endif

extension DiagramTextMeasuringScratch {
    /// `label` measured and wrapped into a block, as `DiagramTextBlock(label:measurer:maximumWidth:)`.
    mutating func measure<Measurer: DiagramTextMeasuring>(_ label: DiagramLabel, measurer: Measurer, maximumWidth: CGFloat) -> DiagramTextBlock {
        let storage = label.storage
        var measuring = DiagramStyledByteMeasuring(measurer)
        if !label.isEmpty {
            for index in 0..<label.lineCount {
                measureLine(index, of: label, measuring: &measuring, maximumWidth: maximumWidth)
            }
        }
        return finishedBlock(source: storage, keepsRuns: label.hasSpans, fontSize: measurer.fontSize,
                             lineHeight: DiagramTextBlock.lineHeight(lineCount: lines.count, measurer: measurer))
    }

    /// Measures line `index` of `label`, wrapping it where it is wider than `maximumWidth` and can break.
    private mutating func measureLine<Measurer>(_ index: Int, of label: DiagramLabel, measuring: inout DiagramStyledByteMeasuring<Measurer>,
                                                maximumWidth: CGFloat) {
        let storage = label.storage
        lineSpans.removeAll()
        guard label.hasSpans else {
            let range = label.lineRange(at: index)
            let bytes = storage.bytes(from: range.start, to: range.end)
            let width = measuring.width(of: bytes, style: [])
            let run = DiagramTextRunRecord(start: range.start, end: range.end, width: width, style: [])
            guard width > maximumWidth, DiagramTextMeasuringWidths.canBreak(bytes, isReadWithoutMarkup: label.isReadWithoutMarkup) else {
                return range.start == range.end ? addEmptyLine(width: width) : addLine(run: run, width: width)
            }
            lineSpans.append(run)
            return wrapLine(of: storage, measuring: &measuring, maximumWidth: maximumWidth)
        }
        let line = label.lineRecord(at: index)
        var width: CGFloat = 0
        for spanIndex in 0..<Int(line.spanCount) {
            let span = storage.record(at: line.firstSpan, index: spanIndex, as: DiagramLabelSpanRecord.self)
            let spanWidth = measuring.width(of: storage.bytes(from: span.start, to: span.end), style: span.style)
            lineSpans.append(DiagramTextRunRecord(start: span.start, end: span.end, width: spanWidth, style: span.style))
            width += spanWidth
        }
        guard width > maximumWidth else { return addLine(runs: lineSpans.buffer, width: width) }
        wrapLine(of: storage, measuring: &measuring, maximumWidth: maximumWidth)
    }

    /// Wraps the spans of `lineSpans`, ranges of `storage`'s bytes: exactly, reading each byte once, where every width is
    /// an exact sum (`wrapsExactly`), else measuring joined text as `DiagramTextLineWrapping` does.
    private mutating func wrapLine<Measurer>(of storage: DiagramTextStorage, measuring: inout DiagramStyledByteMeasuring<Measurer>,
                                             maximumWidth: CGFloat) {
        if wrapsExactly(storage.bytePointer, measuring: &measuring) { return wrapExactly(storage.bytePointer, measuring: &measuring, maximumWidth: maximumWidth) }
        let end = Int(lineSpans[lineSpans.count - 1].end)
        var wrapping = DiagramTextLineWrapping(measuring: measuring, maximumWidth: maximumWidth,
                                               bytes: UnsafeBufferPointer(start: storage.bytePointer, count: end))
        wrapping.wrapLine(into: &self)
        measuring = wrapping.measuring
    }
}

/// The widths and the breaking test a block's measuring reads from bytes.
enum DiagramTextMeasuringWidths {
    /// The width of `bytes` in `measurer`'s own font: Core Text's measurer measures the bytes, any other the String.
    @inline(__always)
    static func width(of bytes: UnsafeBufferPointer<UInt8>, measurer: some DiagramTextMeasuring) -> CGFloat {
        if let coreText = measurer as? CoreTextDiagramTextMeasurer { return coreText.face.width(ofUTF8: bytes) }
        return measurer.width(of: String(decoding: bytes, as: UTF8.self))
    }

    /// Whether wrapping can break the line `bytes` hold, as Pele's layoutLabel decides: a line read without markup only
    /// at a plain space (`text.includes(' ')`), a Chinese or Japanese character or a break hint; a line read for its markup
    /// at any white space. An ASCII line, which holds no Chinese or Japanese character and no hint, is answered from its
    /// bytes.
    static func canBreak(_ bytes: UnsafeBufferPointer<UInt8>, isReadWithoutMarkup: Bool) -> Bool {
        // JavaScript's white space among ASCII bytes is the space and tab to carriage return.
        var isASCII = true
        for byte in bytes {
            if byte >= 0x80 {
                isASCII = false
            } else if byte == UInt8(ascii: " ") || (!isReadWithoutMarkup && (0x09...0x0D).contains(byte)) {
                return true
            }
        }
        if isASCII { return false }
        return String(decoding: bytes, as: UTF8.self).unicodeScalars.contains { scalar in
            (isReadWithoutMarkup ? scalar == " " : JavaScriptStringTrimming.isWhitespace(scalar)) || DiagramTextPieces.isCJK(scalar)
                || DiagramTextPieces.isHint(scalar)
        }
    }
}
