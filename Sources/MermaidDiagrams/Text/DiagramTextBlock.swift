/**
 * File: DiagramTextBlock.swift
 * ----------------------------
 * Layer: Core
 * Description: Lines of a diagram's text measured in a font and placed around a center, wrapped at a width as Pele's
 *              layoutLabel wraps them, a text of more than one line set 1.3 times its size apart; kept as byte ranges
 *              and records of a text storage, its lines made as Strings only when read.
 *
 * Authors: Félix Chevalier, Bahey Shalash
 * Version: 0.5
 * Date: 24/11/2026
 */

import CoreGraphics

/// Lines of text placed in a diagram: each line's width in the font it was measured in, and where the block's center is.
/// Lines are drawn centered on the block's center, one `lineHeight` apart: the measurer's line height (1.5 times the size)
/// for a single line, 1.3 times the size, rounded, for a text of more than one (Pele's `WRAPPED_LINE_HEIGHT`).
///
/// The lines are UTF-8 bytes and records in a `DiagramTextStorage` the block refers to, shared with the other blocks and
/// labels its thread wrote: a copy retains one reference. `lineCount`, `lineWidth(at:)` and `withUTF8(ofLine:_:)` read
/// them as they are; `lines`, `lineWidths` and `lineRuns` make Strings and lists each time they are read.
public struct DiagramTextBlock: Equatable, Sendable {
    let storage: DiagramTextStorage
    let record: DiagramTextRecord
    public let fontSize: CGFloat
    public let lineHeight: CGFloat
    public internal(set) var center: CGPoint

    init(storage: DiagramTextStorage, record: DiagramTextRecord, fontSize: CGFloat, lineHeight: CGFloat, center: CGPoint = .zero) {
        self.storage = storage
        self.record = record
        self.fontSize = fontSize
        self.lineHeight = lineHeight
        self.center = center
    }

    /// How many lines the block has.
    public var lineCount: Int { Int(record.lineCount) }

    /// The width of line `index` in the font it was measured in; `index` is below `lineCount`, as an array's would be.
    public func lineWidth(at index: Int) -> CGFloat {
        precondition(index >= 0 && index < lineCount, "line index out of range")
        return record.isOneLine ? record.widestLineWidth : lineRecord(at: index).width
    }

    /// The UTF-8 bytes of line `index`, valid in `body` only; `index` is below `lineCount`, as an array's would be.
    public func withUTF8<Result>(ofLine index: Int, _ body: (UnsafeBufferPointer<UInt8>) throws -> Result) rethrows -> Result {
        precondition(index >= 0 && index < lineCount, "line index out of range")
        let range = lineRange(at: index)
        return try withExtendedLifetime(storage) { try body(storage.bytes(from: range.start, to: range.end)) }
    }

    /// The lines, made as Strings when read.
    public var lines: [String] {
        (0..<lineCount).map { index in line(at: index) }
    }

    /// Each line's width, in a list made when read.
    public var lineWidths: [CGFloat] {
        (0..<lineCount).map { index in lineWidth(at: index) }
    }

    /// Each line's pieces in their emphasis, one after the other from the line's start, or nil when every line is in the
    /// text's own font. A line's runs hold its characters, and their widths add up to its width. Made when read.
    public var lineRuns: [[DiagramTextRun]]? {
        record.hasEmphasis ? (0..<lineCount).map { index in runs(ofLine: index) } : nil
    }

    public var size: CGSize {
        CGSize(width: record.widestLineWidth, height: CGFloat(lineCount) * lineHeight)
    }

    /// Line `index` as a String.
    func line(at index: Int) -> String {
        withUTF8(ofLine: index) { bytes in String(decoding: bytes, as: UTF8.self) }
    }

    /// Where line `index`'s bytes are in the storage.
    @inline(__always)
    func lineRange(at index: Int) -> (start: Int32, end: Int32) {
        guard !record.isOneLine else { return (record.first, record.end) }
        let line = lineRecord(at: index)
        return (line.start, line.end)
    }

    @inline(__always)
    func lineRecord(at index: Int) -> DiagramTextLineRecord {
        storage.record(at: record.first, index: index, as: DiagramTextLineRecord.self)
    }

    /// The run records of line `index`, when the block has emphasis.
    func runRecords(ofLine index: Int) -> (first: Int32, count: Int) {
        let line = lineRecord(at: index)
        return (line.firstRun, Int(line.runCount))
    }

    /// Pele's distance between the lines of a text of more than one line, as a multiple of the size
    /// (text/label.ts `WRAPPED_LINE_HEIGHT`), which makes the lines read as one block.
    static let severalLinesHeightRatio: CGFloat = 1.3

    /// The distance between lines of a text of `lineCount` lines, as Pele's `layoutLabel` sets it: the measurer's own for
    /// one line or none, 1.3 times the size, rounded, for more.
    static func lineHeight(lineCount: Int, measurer: some DiagramTextMeasuring) -> CGFloat {
        lineCount > 1 ? (measurer.fontSize * severalLinesHeightRatio).rounded() : measurer.lineHeight
    }

    /// The runs of line `index`: its own, or the line as one run in the text's own font.
    func runs(ofLine index: Int) -> [DiagramTextRun] {
        guard record.hasEmphasis else {
            let text = line(at: index)
            return text.isEmpty ? [] : [DiagramTextRun(text: text, style: [], width: lineWidth(at: index))]
        }
        let (first, count) = runRecords(ofLine: index)
        return (0..<count).map { runIndex in
            let run = storage.record(at: first, index: runIndex, as: DiagramTextRunRecord.self)
            return DiagramTextRun(text: String(decoding: storage.bytes(from: run.start, to: run.end), as: UTF8.self), style: run.style,
                                  width: run.width)
        }
    }

    /// Blocks are equal when their lines, widths, runs, sizes and places are, the lines and runs compared as Strings are.
    public static func == (left: DiagramTextBlock, right: DiagramTextBlock) -> Bool {
        guard left.fontSize == right.fontSize, left.lineHeight == right.lineHeight, left.center == right.center,
              left.lineCount == right.lineCount, left.record.hasEmphasis == right.record.hasEmphasis else { return false }
        for index in 0..<left.lineCount {
            guard left.lineWidth(at: index) == right.lineWidth(at: index) else { return false }
            let isSame = left.withUTF8(ofLine: index) { leftBytes in
                right.withUTF8(ofLine: index) { rightBytes in DiagramTextBytes.areEqualAsText(leftBytes, rightBytes) }
            }
            guard isSame else { return false }
        }
        return !left.record.hasEmphasis || left.lineRuns == right.lineRuns
    }
}

extension DiagramTextBlock {
    func translated(by offset: CGVector) -> DiagramTextBlock {
        var moved = self
        moved.center = center.translated(by: offset)
        return moved
    }

    /// The block's rectangle around its center.
    var frame: CGRect {
        CGRect(x: center.x - size.width / 2, y: center.y - size.height / 2, width: size.width, height: size.height)
    }
}
