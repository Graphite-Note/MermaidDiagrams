/**
 * File: ReferenceBlockPreparedSource.swift
 * ----------------------------------------
 * Layer: Tests
 * Description: MermaidDiagrams 0.7.0's BlockPreparedSource, frozen as main 2a0cc65 had it: the reference the block reader is
 *              proven against (BlockReadingEquivalenceTests).
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 24/11/2026
 */

@testable import MermaidDiagrams
/// What Pele's preprocessing does to a block diagram's text before its lexer reads it: a line break written `\r\n`
/// becomes `\n` and a `\r` alone becomes one; a comment line (`RE_COMMENT`, `^\s*%%(?!{)[^\n]+\n?`: `%%` and at
/// least one more character) is taken out with its line break, and with the white space and blank lines before it on
/// their own lines, so that a quoted text that runs over a comment line has no line of it. A line of a directive
/// (`%%{init: …}%%`) goes the same way, as Pele's directive step takes its text out. The line breaks taken out are
/// counted where they were, so an error names the line as written.
struct ReferenceBlockPreparedSource {
    /// The text the lexer reads.
    private(set) var bytes: [UInt8]
    /// Where the lexer starts, the diagram's keyword, in `bytes` as in the text written.
    let start: Int
    /// Each place in `bytes` where line breaks were taken out, in order, with how many were taken out there.
    private var removedLineBreaks: [(offset: Int, count: Int)] = []

    /// `written` from `start` on: before `start` only a `\r` changes, to a line break alone and to a space before one, so
    /// `start` is the same in both.
    init(_ written: [UInt8], from start: Int) {
        self.start = start
        guard written.contains(PlaneMapByte.percent) || written.contains(PlaneMapByte.carriageReturn) else {
            bytes = written
            return
        }
        var normalized = written
        // A `\r` left is the first byte of a `\r\n`, which the copy from `start` on leaves out.
        for index in normalized.indices where normalized[index] == PlaneMapByte.carriageReturn {
            guard index + 1 < normalized.count, normalized[index + 1] == PlaneMapByte.lineFeed else {
                normalized[index] = PlaneMapByte.lineFeed
                continue
            }
            if index < start { normalized[index] = PlaneMapByte.space }
        }
        bytes = Array(normalized[..<min(max(start, 0), normalized.count)])
        bytes.reserveCapacity(normalized.count)
        removeComments(from: normalized, at: bytes.count)
    }

    /// The line, counted from 1 in the text as written, of the byte at `offset` in `bytes`.
    func line(of offset: Int) -> Int {
        var line = PlaneMapByte.line(of: offset, in: bytes)
        for removal in removedLineBreaks where removal.offset <= offset { line += removal.count }
        return line
    }

    /// Copies `normalized` from `position` on into `bytes`, leaving out each comment line: at a line's start, the run of
    /// white space (blank lines included) that ends in `%%` and one more character on that line is taken out, to the end
    /// of that line and its line break. A run that ends in anything else is copied whole, so each byte is looked at once.
    /// The `\r` of each `\r\n` is left out.
    private mutating func removeComments(from normalized: [UInt8], at position: Int) {
        var index = position
        var isLineStart = position == 0 || normalized[position - 1] == PlaneMapByte.lineFeed
        while index < normalized.count {
            guard isLineStart else {
                if normalized[index] != PlaneMapByte.carriageReturn { bytes.append(normalized[index]) }
                isLineStart = normalized[index] == PlaneMapByte.lineFeed
                index += 1
                continue
            }
            var first = index
            while first < normalized.count, PlaneMapByte.isSpace(normalized[first]) { first += 1 }
            if let end = Self.commentEnd(in: normalized, at: first) {
                let lineBreaks = normalized[index..<end].reduce(0) { count, byte in byte == PlaneMapByte.lineFeed ? count + 1 : count }
                if lineBreaks > 0 { removedLineBreaks.append((bytes.count, lineBreaks)) }
                index = end
                continue
            }
            let copiedEnd = min(first + 1, normalized.count)
            bytes.append(contentsOf: normalized[index..<copiedEnd].lazy.filter { byte in byte != PlaneMapByte.carriageReturn })
            isLineStart = normalized[copiedEnd - 1] == PlaneMapByte.lineFeed
            index = copiedEnd
        }
    }

    /// Where the comment whose `%%` is at `first` ends, after its line break; nil when no comment is there.
    private static func commentEnd(in bytes: [UInt8], at first: Int) -> Int? {
        guard first + 2 < bytes.count, bytes[first] == PlaneMapByte.percent, bytes[first + 1] == PlaneMapByte.percent,
              bytes[first + 2] != PlaneMapByte.lineFeed else { return nil }
        let lineEnd = bytes[(first + 2)...].firstIndex(of: PlaneMapByte.lineFeed)
        return lineEnd.map { lineEnd in lineEnd + 1 } ?? bytes.count
    }
}
