/**
 * File: DiagramMeasuredTextBlocks.swift
 * -------------------------------------
 * Layer: Core
 * Description: A text measured from its source's bytes made the block a scene keeps: its lines' bytes, and its runs' when
 *              it has emphasis, copied once into the thread's text storage with their widths, the same block to the byte
 *              as measuring its decoded label gives; and a measured text moved or centered.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 25/11/2026
 */

import CoreGraphics

extension DiagramTextBlock {
    /// The block of `measured`, a text of `lines` whose lines are ranges of `source` or of the lines' derived bytes:
    /// its lines, widths, runs, size, font size, line height and center, as `DiagramTextBlock(label:measurer:maximumWidth:)`
    /// gives them for the same text (`DiagramFlatTextMeasuring`). A text of one line without emphasis keeps its line in its
    /// record, as such a block does; any other keeps line records, and run records when it has emphasis.
    ///
    /// The bytes are copied into this thread's text storage, so that the block, and the scene that keeps it, no longer
    /// need `lines` or `source`. `measured` must be a text of `lines`, and its lines ranges of `source`: both are checked.
    init(_ measured: DiagramMeasuredText, of lines: borrowing DiagramMeasuredLines, source: UnsafeBufferPointer<UInt8>) {
        let lineCount = Int(measured.lineCount)
        precondition(measured.firstLine >= 0 && lineCount >= 0 && Int(measured.firstLine) + lineCount <= lines.count, "measured text outside its lines")
        let state = DiagramTextThreadState.current
        guard lineCount > 0 else {
            self.init(storage: state.storage, record: .empty, fontSize: measured.fontSize, lineHeight: measured.lineHeight, center: measured.center)
            return
        }
        let first = Int(measured.firstLine)
        guard lineCount > 1 || measured.hasEmphasis else {
            let line = lines[first]
            let storage = state.storage(forBytes: Self.checkedByteCount(line.start, line.end), recordBytes: 0)
            let start = lines.withBytes(from: line.start, to: line.end, source: source) { bytes in storage.append(bytes) }
            let record = DiagramTextRecord(first: start, end: start + (line.end - line.start), lineCount: 1, isOneLine: true, hasEmphasis: false,
                                           widestLineWidth: measured.width)
            self.init(storage: storage, record: record, fontSize: measured.fontSize, lineHeight: measured.lineHeight, center: measured.center)
            return
        }
        let record = Self.writtenRecords(of: measured, lines: lines, source: source, state: state)
        self.init(storage: record.storage, record: record.record, fontSize: measured.fontSize, lineHeight: measured.lineHeight, center: measured.center)
    }

    /// The bytes and records of a text of several lines, or of one with emphasis, written into a storage of `state`.
    private static func writtenRecords(of measured: DiagramMeasuredText, lines: borrowing DiagramMeasuredLines, source: UnsafeBufferPointer<UInt8>,
                                       state: DiagramTextThreadState) -> (storage: DiagramTextStorage, record: DiagramTextRecord) {
        let lineIndices = measured.lineIndices
        var byteCount = 0
        var runCount = 0
        for index in lineIndices {
            let line = lines[index]
            byteCount += checkedByteCount(line.start, line.end)
            guard measured.hasEmphasis else { continue }
            for runIndex in runIndices(of: line) { byteCount += checkedByteCount(lines.runs[runIndex].start, lines.runs[runIndex].end) }
            runCount += Int(line.runCount)
        }
        let recordBytes = DiagramTextStorage.recordByteCount(lineIndices.count, of: DiagramTextLineRecord.self)
            + (measured.hasEmphasis ? DiagramTextStorage.recordByteCount(runCount, of: DiagramTextRunRecord.self) : 0)
        let storage = state.storage(forBytes: byteCount, recordBytes: recordBytes)
        let firstLine = storage.reserveRecords(count: lineIndices.count, of: DiagramTextLineRecord.self)
        let firstRun = measured.hasEmphasis ? storage.reserveRecords(count: runCount, of: DiagramTextRunRecord.self) : 0
        let runStride = Int32(MemoryLayout<DiagramTextRunRecord>.stride)
        var runWritten = 0
        for (offset, index) in lineIndices.enumerated() {
            let line = lines[index]
            let start = lines.withBytes(from: line.start, to: line.end, source: source) { bytes in storage.append(bytes) }
            let keptRunCount = measured.hasEmphasis ? line.runCount : 0
            storage.setRecord(DiagramTextLineRecord(start: start, end: start + (line.end - line.start), firstRun: firstRun + Int32(runWritten) * runStride,
                                                    runCount: keptRunCount, width: line.width), at: firstLine, index: offset)
            guard measured.hasEmphasis else { continue }
            for runIndex in runIndices(of: line) {
                var run = lines.runs[runIndex]
                let runStart = lines.withBytes(from: run.start, to: run.end, source: source) { bytes in storage.append(bytes) }
                (run.start, run.end) = (runStart, runStart + (run.end - run.start))
                storage.setRecord(run, at: firstRun, index: runWritten)
                runWritten += 1
            }
        }
        return (storage, DiagramTextRecord(first: firstLine, end: 0, lineCount: Int32(lineIndices.count), isOneLine: false,
                                           hasEmphasis: measured.hasEmphasis, widestLineWidth: measured.width))
    }

    /// The bytes from `start` to `end`, a range checked when its bytes are read.
    @inline(__always)
    private static func checkedByteCount(_ start: Int32, _ end: Int32) -> Int {
        precondition(start <= end, "a measured line ends before it starts")
        return Int(end - start)
    }

    /// The runs of `line` in its lines' runs.
    @inline(__always)
    private static func runIndices(of line: DiagramMeasuredLine) -> Range<Int> {
        Int(line.firstRun)..<Int(line.firstRun + line.runCount)
    }
}

extension DiagramMeasuredText {
    /// The text moved by `offset`, as `DiagramTextBlock.translated(by:)` moves a block.
    func translated(by offset: CGVector) -> DiagramMeasuredText {
        var moved = self
        moved.center = center.translated(by: offset)
        return moved
    }

    /// The text centered on `center`.
    func centered(at center: CGPoint) -> DiagramMeasuredText {
        var moved = self
        moved.center = center
        return moved
    }
}
