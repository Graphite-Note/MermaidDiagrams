/**
 * File: DiagramTextBlockWriting.swift
 * -----------------------------------
 * Layer: Core
 * Description: Writes a measured block into a text storage: its lines and runs as records, its text left where it is
 *              when the storage it is in has room for them, else copied with them; a line of one run without emphasis
 *              as its byte range alone, without any record.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 24/11/2026
 */

import CoreGraphics

extension DiagramTextMeasuringScratch {
    /// The block of the lines measured, whose runs are ranges of `source` or of the synthetic text. Runs are kept when
    /// `keepsRuns` and one of them has an emphasis.
    mutating func finishedBlock(source: DiagramTextStorage, keepsRuns: Bool, fontSize: CGFloat, lineHeight: CGFloat) -> DiagramTextBlock {
        let keepsRunRecords = keepsRuns && hasEmphasis
        let lineCount = lines.count
        var widest: CGFloat = 0
        for index in 0..<lineCount where index == 0 || widest < lines[index].width { widest = lines[index].width }
        findLineRanges(source: source.bytePointer)
        let (sourceStart, sourceEnd, usesSynthetic) = usedRanges(keepsRunRecords: keepsRunRecords)
        let sourceByteCount = sourceStart < sourceEnd ? Int(sourceEnd - sourceStart) : 0
        let isOneLine = lineCount == 1 && !keepsRunRecords
        if isOneLine, !usesSynthetic {
            let line = lineRanges[0]
            return DiagramTextBlock(storage: source, record: DiagramTextRecord(first: line.start, end: line.end, lineCount: 1, isOneLine: true,
                                                                                hasEmphasis: false, widestLineWidth: widest),
                                    fontSize: fontSize, lineHeight: lineHeight)
        }
        let recordBytes = isOneLine ? 0 : DiagramTextStorage.recordByteCount(lineCount, of: DiagramTextLineRecord.self)
            + (keepsRunRecords ? DiagramTextStorage.recordByteCount(runs.count, of: DiagramTextRunRecord.self) : 0)
        let syntheticByteCount = usesSynthetic ? synthetic.count : 0
        let state = DiagramTextThreadState.current
        var placement = DiagramTextPlacement(sourceStart: sourceStart, copiedStart: sourceStart, syntheticStart: 0)
        let target: DiagramTextStorage
        if state.storage === source, source.hasRoom(forBytes: syntheticByteCount, recordBytes: recordBytes) {
            target = source
        } else {
            target = state.storage(forBytes: sourceByteCount + syntheticByteCount, recordBytes: recordBytes)
            if sourceByteCount > 0 { placement.copiedStart = target.append(source.bytes(from: sourceStart, to: sourceEnd)) }
        }
        if syntheticByteCount > 0 { placement.syntheticStart = target.append(synthetic.buffer) }
        let record = write(into: target, placement: placement, keepsRunRecords: keepsRunRecords, isOneLine: isOneLine, widest: widest)
        return DiagramTextBlock(storage: target, record: record, fontSize: fontSize, lineHeight: lineHeight)
    }

    /// The range of the source the lines and the kept runs read, and whether they read synthetic text.
    private func usedRanges(keepsRunRecords: Bool) -> (start: Int32, end: Int32, usesSynthetic: Bool) {
        var sourceStart = Int32.max
        var sourceEnd = Int32.min
        var usesSynthetic = false
        func include(_ start: Int32, _ end: Int32) {
            guard start < end else { return }
            guard start < Self.syntheticOffset else { return usesSynthetic = true }
            sourceStart = min(sourceStart, start)
            sourceEnd = max(sourceEnd, end)
        }
        for index in 0..<lines.count { include(lineRanges[index].start, lineRanges[index].end) }
        if keepsRunRecords { for index in 0..<runs.count { include(runs[index].start, runs[index].end) } }
        return (sourceStart, sourceEnd, usesSynthetic)
    }

    /// Writes the line and run records into `target`, the bytes already there.
    private func write(into target: DiagramTextStorage, placement: DiagramTextPlacement, keepsRunRecords: Bool, isOneLine: Bool,
                       widest: CGFloat) -> DiagramTextRecord {
        let lineCount = lines.count
        if isOneLine {
            let line = lineRanges[0]
            let range = placement.placed(line.start, line.end)
            return DiagramTextRecord(first: range.start, end: range.end, lineCount: 1, isOneLine: true, hasEmphasis: false, widestLineWidth: widest)
        }
        let firstLine = target.reserveRecords(count: lineCount, of: DiagramTextLineRecord.self)
        let firstRun = keepsRunRecords ? target.reserveRecords(count: runs.count, of: DiagramTextRunRecord.self) : 0
        let runStride = Int32(MemoryLayout<DiagramTextRunRecord>.stride)
        for index in 0..<lineCount {
            let line = lines[index]
            let range = lineRanges[index]
            let placed = placement.placed(range.start, range.end)
            target.setRecord(DiagramTextLineRecord(start: placed.start, end: placed.end,
                                                   firstRun: firstRun + line.firstRun * runStride, runCount: keepsRunRecords ? line.runCount : 0,
                                                   width: line.width), at: firstLine, index: index)
        }
        if keepsRunRecords {
            for index in 0..<runs.count {
                var run = runs[index]
                (run.start, run.end) = placement.placed(run.start, run.end)
                target.setRecord(run, at: firstRun, index: index)
            }
        }
        return DiagramTextRecord(first: firstLine, end: 0, lineCount: Int32(lineCount), isOneLine: false, hasEmphasis: keepsRunRecords,
                                 widestLineWidth: widest)
    }

    /// Each line's bytes: its runs' range when they follow one another, else a copy of them one after the other in the
    /// synthetic text; an empty line's an empty range.
    private mutating func findLineRanges(source: UnsafePointer<UInt8>) {
        lineRanges.removeAll()
        for index in 0..<lines.count {
            let line = lines[index]
            let first = Int(line.firstRun)
            let count = Int(line.runCount)
            guard count > 0 else {
                lineRanges.append(DiagramTextLineRecord(start: 0, end: 0, firstRun: 0, runCount: 0, width: 0))
                continue
            }
            var isContiguous = true
            for runIndex in (first + 1)..<(first + count) where runs[runIndex].start != runs[runIndex - 1].end { isContiguous = false }
            if isContiguous {
                lineRanges.append(DiagramTextLineRecord(start: runs[first].start, end: runs[first + count - 1].end, firstRun: 0, runCount: 0, width: 0))
                continue
            }
            var byteCount = 0
            for runIndex in first..<(first + count) { byteCount += Int(runs[runIndex].end - runs[runIndex].start) }
            synthetic.reserveCapacity(synthetic.count + byteCount)
            let start = Self.syntheticOffset + Int32(synthetic.count)
            for runIndex in first..<(first + count) {
                synthetic.append(contentsOf: bytes(runs[runIndex].start, runs[runIndex].end, source: source))
            }
            lineRanges.append(DiagramTextLineRecord(start: start, end: Self.syntheticOffset + Int32(synthetic.count), firstRun: 0, runCount: 0, width: 0))
        }
    }
}

/// Where a block's bytes went: the source's range from `sourceStart` copied to `copiedStart` (the same place when the
/// block is written into its source), the synthetic text to `syntheticStart`.
struct DiagramTextPlacement {
    let sourceStart: Int32
    var copiedStart: Int32
    var syntheticStart: Int32

    /// Where the range from `start` to `end` went; an empty range is the storage's first, empty.
    @inline(__always)
    func placed(_ start: Int32, _ end: Int32) -> (start: Int32, end: Int32) {
        guard start < end else { return (0, 0) }
        let shift = start >= DiagramTextMeasuringScratch.syntheticOffset ? syntheticStart - DiagramTextMeasuringScratch.syntheticOffset
            : copiedStart - sourceStart
        return (start + shift, end + shift)
    }
}
