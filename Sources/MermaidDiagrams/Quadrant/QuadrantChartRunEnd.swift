/**
 * File: QuadrantChartRunEnd.swift
 * -------------------------------
 * Layer: Core
 * Description: Where a run of spaces or of a point's white space ends, remembered for the quadrant chart lexer's
 *              look-aheads, so that a long run is stepped once instead of once for each of its bytes.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 25/11/2026
 */

/// The end of the last run of spaces (or of a point's white space, `QuadrantChartPointSyntax.isWhitespace`) looked
/// for: every byte from where it was looked for to its end is one, and the byte at its end is not. The quadrant lexer
/// looks ahead over the run at each of its bytes (for a keyword after spaces, for a point's colon after white space),
/// and each byte of the run makes a token alone, so without it a run of n bytes is stepped n²/2 times.
struct QuadrantChartRunEnd {
    /// Whether the run is of a point's white space; otherwise of spaces alone.
    private let isPointWhitespace: Bool
    /// None remembered at first: no offset is from `start` to `end`.
    private var start = 1
    private var end = 0

    init(isPointWhitespace: Bool) {
        self.isPointWhitespace = isPointWhitespace
    }

    /// The offset of the first byte from `offset` on that is not in the run, `bytes.count` for none.
    mutating func end(from offset: Int, in bytes: UnsafeBufferPointer<UInt8>) -> Int {
        // From any byte of the remembered run, the run ends where it ended.
        if start <= offset, offset <= end { return end }
        var index = offset
        while index < bytes.count, isInRun(bytes[index]) { index += 1 }
        start = offset
        end = index
        return index
    }

    private func isInRun(_ byte: UInt8) -> Bool {
        isPointWhitespace ? QuadrantChartPointSyntax.isWhitespace(byte) : byte == MermaidByte.space
    }
}
