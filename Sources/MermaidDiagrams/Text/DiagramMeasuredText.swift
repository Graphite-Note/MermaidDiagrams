/**
 * File: DiagramMeasuredText.swift
 * -------------------------------
 * Layer: Core
 * Description: A text measured into a layout's own list of lines: its first line there, how many, its size, its line
 *              height and its center; each line a range of the source's bytes, or of bytes the list derived when the
 *              text needed decoding, with its width and, for emphasis only, its runs; lines of bytes that do not
 *              outlive the measuring copied into the derived bytes.
 *
 * Authors: Bahey Shalash
 * Version: 0.3
 * Date: 26/11/2026
 */

import CoreGraphics

/// A text measured by `DiagramFlatTextMeasuring`: `lineCount` lines from `firstLine` of the `DiagramMeasuredLines` it
/// was measured into, set `lineHeight` apart around `center` as a `DiagramTextBlock` sets its lines. A few numbers: it
/// copies without reference counting.
struct DiagramMeasuredText: Equatable, Sendable {
    var firstLine: Int32
    var lineCount: Int32
    /// The widest line's width.
    var width: CGFloat
    var height: CGFloat
    var lineHeight: CGFloat
    var fontSize: CGFloat
    /// Whether its lines keep their runs in their emphasis, as a block's `lineRuns` does.
    var hasEmphasis = false
    var center: CGPoint = .zero

    var size: CGSize { CGSize(width: width, height: height) }

    /// The text's rectangle around its center.
    var frame: CGRect {
        CGRect(x: center.x - width / 2, y: center.y - height / 2, width: width, height: height)
    }

    /// The lines of `lines` the text holds.
    var lineIndices: Range<Int> { Int(firstLine)..<Int(firstLine + lineCount) }
}

/// A measured line: its bytes (a range of the source, or of the derived bytes from `DiagramMeasuredLines.derivedOffset`
/// on), its width, and its runs in `DiagramMeasuredLines.runs` when its text has emphasis (`runCount` zero otherwise).
struct DiagramMeasuredLine: Equatable, Sendable {
    var start: Int32
    var end: Int32
    var width: CGFloat
    var firstRun: Int32 = 0
    var runCount: Int32 = 0
}

/// The lines of the texts a layout measures, in lists it keeps and reuses: a text measured from the source refers to
/// the source's bytes; a text the full path decoded (an entity, emphasis, a byte past ASCII) has its lines' bytes copied
/// into `derived`.
struct DiagramMeasuredLines: Sendable {
    /// Offsets from this one on are of `derived`; a source must be shorter.
    static let derivedOffset: Int32 = 1 << 30

    private(set) var lines: [DiagramMeasuredLine] = []
    /// The runs of lines with emphasis, their bytes in `derived`.
    private(set) var runs: [DiagramTextRunRecord] = []
    private(set) var derived: [UInt8] = []

    init() {}

    var count: Int { lines.count }

    subscript(index: Int) -> DiagramMeasuredLine { lines[index] }

    /// Every line, run and derived byte taken out, the memory kept for the next texts.
    mutating func removeAll() {
        lines.removeAll(keepingCapacity: true)
        runs.removeAll(keepingCapacity: true)
        derived.removeAll(keepingCapacity: true)
    }

    /// Room made for `lineCount` lines and `derivedByteCount` derived bytes, so that a layout that knows about how many
    /// texts it measures grows its lists once.
    mutating func reserveCapacity(lines lineCount: Int, derivedBytes derivedByteCount: Int) {
        lines.reserveCapacity(lineCount)
        derived.reserveCapacity(derivedByteCount)
    }

    /// Lines from `count` on taken out: a measuring that left the fast path undoes the lines it added.
    mutating func removeLines(from count: Int) {
        lines.removeSubrange(count...)
    }

    /// A line of the source's bytes from `start` to `end`.
    @inline(__always)
    mutating func appendLine(start: Int, end: Int, width: CGFloat) {
        lines.append(DiagramMeasuredLine(start: Int32(truncatingIfNeeded: start), end: Int32(truncatingIfNeeded: end), width: width))
    }

    /// A line of `bytes` copied into the derived bytes, with the runs of its emphasis, if any, each run's bytes copied.
    mutating func appendDerivedLine(_ bytes: UnsafeBufferPointer<UInt8>, width: CGFloat, runs lineRuns: [(bytes: UnsafeBufferPointer<UInt8>, width: CGFloat, style: DiagramTextStyle)]) {
        let start = appendDerived(bytes)
        var line = DiagramMeasuredLine(start: start, end: start + Int32(bytes.count), width: width)
        if !lineRuns.isEmpty {
            line.firstRun = Int32(runs.count)
            line.runCount = Int32(lineRuns.count)
            for run in lineRuns {
                let runStart = appendDerived(run.bytes)
                runs.append(DiagramTextRunRecord(start: runStart, end: runStart + Int32(run.bytes.count), width: run.width, style: run.style))
            }
        }
        lines.append(line)
    }

    /// The lines of `text` that are ranges of `source` copied into the derived bytes, for a text measured from bytes that
    /// do not outlive the measuring (a String's).
    mutating func deriveLines(of text: DiagramMeasuredText, source: UnsafeBufferPointer<UInt8>) {
        for index in text.lineIndices where lines[index].start < Self.derivedOffset {
            let line = lines[index]
            precondition(line.start >= 0 && line.start <= line.end && Int(line.end) <= source.count, "line outside its source")
            // Appended from `source` itself: reading it through `withBytes` borrowed a copy of these lists, so that each
            // append copied the derived bytes whole.
            let start = appendDerived(UnsafeBufferPointer(rebasing: source[Int(line.start)..<Int(line.end)]))
            lines[index].start = start
            lines[index].end = start + (line.end - line.start)
        }
    }

    /// A source of no bytes, for texts whose lines are all derived bytes.
    static var noSource: UnsafeBufferPointer<UInt8> { UnsafeBufferPointer(start: nil, count: 0) }

    private mutating func appendDerived(_ bytes: UnsafeBufferPointer<UInt8>) -> Int32 {
        precondition(derived.count + bytes.count < Int(Self.derivedOffset), "derived text too long for its offsets")
        let start = Self.derivedOffset + Int32(derived.count)
        derived.append(contentsOf: bytes)
        return start
    }

    /// The bytes from `start` to `end`, of `source` or of the derived bytes, valid in `body` only.
    func withBytes<Result>(from start: Int32, to end: Int32, source: UnsafeBufferPointer<UInt8>, _ body: (UnsafeBufferPointer<UInt8>) throws -> Result)
        rethrows -> Result {
        guard start >= Self.derivedOffset else {
            precondition(start >= 0 && start <= end && Int(end) <= source.count, "line outside its source")
            return try body(UnsafeBufferPointer(rebasing: source[Int(start)..<Int(end)]))
        }
        return try derived.withUnsafeBufferPointer { derived in
            try body(UnsafeBufferPointer(rebasing: derived[Int(start - Self.derivedOffset)..<Int(end - Self.derivedOffset)]))
        }
    }

    /// The UTF-8 bytes of line `index`, valid in `body` only.
    func withUTF8<Result>(ofLine index: Int, source: UnsafeBufferPointer<UInt8>, _ body: (UnsafeBufferPointer<UInt8>) throws -> Result) rethrows -> Result {
        let line = lines[index]
        return try withBytes(from: line.start, to: line.end, source: source, body)
    }

    /// Line `index` as a String, made when asked.
    func text(ofLine index: Int, source: UnsafeBufferPointer<UInt8>) -> String {
        withUTF8(ofLine: index, source: source) { bytes in String(decoding: bytes, as: UTF8.self) }
    }

    /// The runs of line `index` in their emphasis, made when asked; none for a line of a text without emphasis.
    func runs(ofLine index: Int) -> [DiagramTextRun] {
        let line = lines[index]
        return (Int(line.firstRun)..<Int(line.firstRun + line.runCount)).map { runIndex in
            let run = runs[runIndex]
            return withBytes(from: run.start, to: run.end, source: UnsafeBufferPointer(start: nil, count: 0)) { bytes in
                DiagramTextRun(text: String(decoding: bytes, as: UTF8.self), style: run.style, width: run.width)
            }
        }
    }
}
