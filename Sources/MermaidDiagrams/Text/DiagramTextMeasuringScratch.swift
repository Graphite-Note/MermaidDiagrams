/**
 * File: DiagramTextMeasuringScratch.swift
 * ---------------------------------------
 * Layer: Core
 * Description: The working lists a block's lines and runs are measured into on a thread, as byte ranges, and how they
 *              are written into a text storage once the block is measured: in the storage its text is already in when
 *              they fit there, else with its bytes copied, a line of one run without emphasis written as its range alone.
 *
 * Authors: Bahey Shalash
 * Version: 0.2
 * Date: 24/11/2026
 */

import CoreGraphics

/// A block's lines and runs as they are measured. A run's bytes are a range of the storage the measured text is in, or,
/// from `syntheticOffset` on, of `synthetic`: text the measuring made (a soft hyphen shown as `-`). A line is its runs,
/// one after the other; its width is the width the measuring gave it.
struct DiagramTextMeasuringScratch {
    struct Line {
        var firstRun: Int32
        var runCount: Int32
        var width: CGFloat
    }

    /// Offsets from this one on are of `synthetic` (no storage reaches it).
    static let syntheticOffset: Int32 = 1 << 30

    var lines = DiagramTextScratchList<Line>()
    var runs = DiagramTextScratchList<DiagramTextRunRecord>()
    var synthetic = DiagramTextScratchList<UInt8>(capacity: 64)
    /// A text measured and not kept (a piece with its soft hyphen shown, to see whether it fits).
    var probe = DiagramTextScratchList<UInt8>(capacity: 64)
    /// The spans of the line being measured, and of the line being filled while it wraps.
    var lineSpans = DiagramTextScratchList<DiagramTextRunRecord>()
    var filled = DiagramTextScratchList<DiagramWrappedSpan>()
    /// Each line's bytes once written, and where a run's bytes are once copied.
    var lineRanges = DiagramTextScratchList<DiagramTextLineRecord>()
    var pieces: [Range<Int>] = []
    var hasEmphasis = false

    func free() {
        lines.free()
        runs.free()
        synthetic.free()
        probe.free()
        lineSpans.free()
        filled.free()
        lineRanges.free()
    }

    mutating func removeAll() {
        lines.removeAll()
        runs.removeAll()
        synthetic.removeAll()
        lineSpans.removeAll()
        filled.removeAll()
        hasEmphasis = false
    }

    /// A line of `runs` already measured, `width` wide.
    mutating func addLine(runs added: UnsafeBufferPointer<DiagramTextRunRecord>, width: CGFloat) {
        lines.append(Line(firstRun: Int32(runs.count), runCount: Int32(added.count), width: width))
        for run in added where !run.style.isEmpty { hasEmphasis = true }
        runs.append(contentsOf: added)
    }

    /// A line of one run, or of none when the run is empty and `isEmptyLine`.
    mutating func addLine(run: DiagramTextRunRecord, width: CGFloat) {
        lines.append(Line(firstRun: Int32(runs.count), runCount: 1, width: width))
        if !run.style.isEmpty { hasEmphasis = true }
        runs.append(run)
    }

    mutating func addEmptyLine(width: CGFloat) {
        lines.append(Line(firstRun: Int32(runs.count), runCount: 0, width: width))
    }

    /// Appends synthetic text: `bytes`, then `suffix`; returns its range.
    mutating func appendSynthetic(_ bytes: UnsafeBufferPointer<UInt8>, suffix: UInt8? = nil) -> (start: Int32, end: Int32) {
        let start = Self.syntheticOffset + Int32(synthetic.count)
        synthetic.append(contentsOf: bytes)
        if let suffix { synthetic.append(suffix) }
        return (start, Self.syntheticOffset + Int32(synthetic.count))
    }

    /// The bytes of a range of the source or of the synthetic text.
    func bytes(_ start: Int32, _ end: Int32, source: UnsafePointer<UInt8>) -> UnsafeBufferPointer<UInt8> {
        guard start >= Self.syntheticOffset else { return UnsafeBufferPointer(start: source + Int(start), count: Int(end - start)) }
        return UnsafeBufferPointer(start: synthetic.start + Int(start - Self.syntheticOffset), count: Int(end - start))
    }
}

extension DiagramTextThreadState {
    /// `body` with this thread's measuring scratch, emptied; a measuring that starts while another runs gets its own.
    func withMeasuringScratch<Result>(_ body: (inout DiagramTextMeasuringScratch) -> Result) -> Result {
        guard !isMeasuring else {
            var own = DiagramTextMeasuringScratch()
            defer { own.free() }
            return body(&own)
        }
        isMeasuring = true
        defer { isMeasuring = false }
        measuring.removeAll()
        return body(&measuring)
    }

    /// `body` with this thread's label decoder; a decoding that starts while another runs gets its own.
    func withDecoder<Result>(_ body: (inout DiagramLabelByteDecoder) -> Result) -> Result {
        guard !isDecoding else {
            var own = DiagramLabelByteDecoder()
            return body(&own)
        }
        isDecoding = true
        defer { isDecoding = false }
        return body(&decoder)
    }
}
