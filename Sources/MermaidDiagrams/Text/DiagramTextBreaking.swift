/**
 * File: DiagramTextBreaking.swift
 * -------------------------------
 * Layer: Core
 * Description: Text that may not grow past a width: lines broken between characters, measured on their bytes, literal
 *              text that keeps every character, blocks of lines already measured, and a block's lines placed from their
 *              left or right end, as Pele writes text by its start.
 *
 * Authors: Bahey Shalash
 * Version: 0.5
 * Date: 24/11/2026
 */

import CoreGraphics

extension DiagramTextBlock {
    /// A block of lines already measured, written into the thread's text storage; one width per line.
    init(lines: [String], lineWidths: [CGFloat], fontSize: CGFloat, lineHeight: CGFloat, center: CGPoint = .zero) {
        precondition(lines.count == lineWidths.count, "one width per line")
        var widest: CGFloat = 0
        for (index, width) in lineWidths.enumerated() where index == 0 || widest < width { widest = width }
        let byteCount = lines.reduce(0) { total, line in total + line.utf8.count }
        let isOneLine = lines.count == 1
        let recordBytes = isOneLine ? 0 : DiagramTextStorage.recordByteCount(lines.count, of: DiagramTextLineRecord.self)
        let storage = DiagramTextThreadState.current.storage(forBytes: byteCount, recordBytes: recordBytes)
        guard !isOneLine else {
            let start = DiagramLabelWriting.append(lines[0], to: storage)
            self.init(storage: storage, record: DiagramTextRecord(first: start, end: start + Int32(lines[0].utf8.count), lineCount: 1, isOneLine: true,
                                                                  hasEmphasis: false, widestLineWidth: widest),
                      fontSize: fontSize, lineHeight: lineHeight, center: center)
            return
        }
        let first = storage.reserveRecords(count: lines.count, of: DiagramTextLineRecord.self)
        for (index, line) in lines.enumerated() {
            let start = DiagramLabelWriting.append(line, to: storage)
            storage.setRecord(DiagramTextLineRecord(start: start, end: start + Int32(line.utf8.count), firstRun: 0, runCount: 0, width: lineWidths[index]),
                              at: first, index: index)
        }
        self.init(storage: storage, record: DiagramTextRecord(first: first, end: 0, lineCount: Int32(lines.count), isOneLine: false,
                                                              hasEmphasis: false, widestLineWidth: widest),
                  fontSize: fontSize, lineHeight: lineHeight, center: center)
    }

    /// `label` wrapped at spaces to `maximumWidth`, and each line still wider broken between characters, as Pele's kanban
    /// fits a card's text: a card cannot grow sideways to hold a long word. The lines keep the distance of the wrapped
    /// text, as Pele's `fitLabel` and `breakLabel` keep its label's: 1.3 sizes when it wrapped to several lines, 1.5 when a
    /// single line is broken.
    init(label: DiagramLabel, measurer: some DiagramTextMeasuring, fittingWidth maximumWidth: CGFloat) {
        self.init(label: label, measurer: measurer, wrappingWidth: maximumWidth, breakingWidth: maximumWidth)
    }

    /// `label` wrapped at spaces to `wrappingWidth`, and each line still wider than `breakingWidth` broken between
    /// characters, as Pele's `layoutLabel` then `breakLabel` set a text (a sequence diagram's in a tight layout).
    init(label: DiagramLabel, measurer: some DiagramTextMeasuring, wrappingWidth: CGFloat, breakingWidth maximumWidth: CGFloat) {
        let wrapped = DiagramTextBlock(label: label, measurer: measurer, maximumWidth: wrappingWidth)
        if (0..<wrapped.lineCount).contains(where: { index in wrapped.lineWidth(at: index) > maximumWidth }) {
            self = DiagramTextThreadState.current.withMeasuringScratch { scratch in
                scratch.breakLines(of: wrapped, measurer: measurer, maximumWidth: maximumWidth)
            }
        } else {
            self = wrapped
        }
        #if DEBUG
        DiagramTextBlockObservation.observer?(DiagramTextBlockObservation.Measuring(label: label, measurer: measurer, maximumWidth: wrappingWidth,
                                                                                    breakingWidth: maximumWidth, block: self))
        #endif
    }

    /// Text that keeps every character but the spaces a line breaks at, as Pele's literal labels (a file's name) do:
    /// each written line broken where it passes `room`, at the last space before that when there is one, else between
    /// characters. Empty text has no lines.
    init(literal text: String, measurer: some DiagramTextMeasuring, room: CGFloat) {
        var lines: [String] = []
        if !text.isEmpty {
            for written in text.split(separator: "\n", omittingEmptySubsequences: false) {
                lines += DiagramLiteralLines.lines(of: written, measurer: measurer, room: room)
            }
        }
        self.init(lines: lines, lineWidths: lines.map { line in measurer.width(of: line) }, fontSize: measurer.fontSize,
                  lineHeight: measurer.lineHeight)
    }

    /// Each line as a block of its own, its left end at `left` (or its right end at `right`), the first line's box
    /// starting at `top`: text Pele writes from its start or its end rather than its middle.
    func placedLines(left: CGFloat? = nil, right: CGFloat? = nil, top: CGFloat) -> [DiagramTextBlock] {
        (0..<lineCount).map { index in
            let width = lineWidth(at: index)
            let middleAcross = left.map { left in left + width / 2 } ?? (right ?? 0) - width / 2
            return lineBlock(at: index, center: CGPoint(x: middleAcross, y: top + (CGFloat(index) + 0.5) * lineHeight))
        }
    }

    /// Line `index` as a block of its own, with its runs when the block has emphasis, centered at `center`: its line
    /// record, or its bytes alone, in the same storage.
    func lineBlock(at index: Int, center: CGPoint) -> DiagramTextBlock {
        let width = lineWidth(at: index)
        let lineRecord: DiagramTextRecord
        if record.isOneLine {
            lineRecord = record
        } else if record.hasEmphasis {
            lineRecord = DiagramTextRecord(first: record.first + Int32(index * MemoryLayout<DiagramTextLineRecord>.stride), end: 0, lineCount: 1,
                                           isOneLine: false, hasEmphasis: true, widestLineWidth: width)
        } else {
            let range = lineRange(at: index)
            lineRecord = DiagramTextRecord(first: range.start, end: range.end, lineCount: 1, isOneLine: true, hasEmphasis: false, widestLineWidth: width)
        }
        return DiagramTextBlock(storage: storage, record: lineRecord, fontSize: fontSize, lineHeight: lineHeight, center: center)
    }
}

extension DiagramTextBlock {
    /// Line `index` as a block of its own in the text's own font, without its runs, centered at `center`: its bytes in the
    /// same storage.
    func plainLineBlock(at index: Int, center: CGPoint) -> DiagramTextBlock {
        let range = lineRange(at: index)
        return DiagramTextBlock(storage: storage, record: DiagramTextRecord(first: range.start, end: range.end, lineCount: 1, isOneLine: true,
                                                                            hasEmphasis: false, widestLineWidth: lineWidth(at: index)),
                                fontSize: fontSize, lineHeight: lineHeight, center: center)
    }
}

/// A broken line's span being filled: its bytes, its emphasis, its width added up as Pele's `breakLabel` adds it, the
/// width of its whole text measured, and whether every byte is printable ASCII.
struct DiagramBrokenSpan {
    var start: Int32
    var end: Int32
    let style: DiagramTextStyle
    var width: CGFloat
    var measuredWidth: CGFloat
    var isPrintableASCII: Bool
}
