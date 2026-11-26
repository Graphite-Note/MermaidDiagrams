/**
 * File: ChartByteCursor.swift
 * ---------------------------
 * Layer: Core
 * Description: A position in a diagram's borrowed UTF-8 bytes for a chart's lexer, moved as MermaidTextCursor moves,
 *              whose line is counted only when it is asked for.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 25/11/2026
 */

/// A position in a diagram's bytes, borrowed for the time of a read, that moves as `MermaidTextCursor` moves (`advance`
/// stops at the end, `skipToEndOfLine` stops at a line feed) without testing each byte it passes for a line feed: its
/// line is counted forward when asked for (`ChartLineCounter`), which a lexer asks at the start of each token, so each
/// byte is stepped once more at most.
struct ChartByteCursor {
    let bytes: UnsafeBufferPointer<UInt8>
    private(set) var position: Int
    private var lines: ChartLineCounter

    /// At `cursor`'s position and line, over `bytes`, which are `cursor`'s.
    init(_ cursor: MermaidTextCursor, bytes: UnsafeBufferPointer<UInt8>) {
        self.bytes = bytes
        position = cursor.position
        lines = ChartLineCounter(position: cursor.position, line: cursor.line)
    }

    /// The line of the position: one more than the cursor's line for each line feed before it. A position before one
    /// asked for earlier is given that one's line, which a reader moving forward never asks.
    var line: Int {
        mutating get { lines.line(at: position, in: bytes) }
    }

    func peek(_ offset: Int = 0) -> UInt8? {
        let index = position + offset
        return index < bytes.count ? bytes[index] : nil
    }

    mutating func advance(by count: Int = 1) {
        position = min(bytes.count, position + count)
    }

    func hasPrefix(_ literal: [UInt8]) -> Bool {
        guard position + literal.count <= bytes.count else { return false }
        for (offset, byte) in literal.enumerated() where bytes[position + offset] != byte { return false }
        return true
    }

    /// Whether `literal`, lowercase, is at the position, ASCII letters compared without regard to case.
    func hasCaseInsensitivePrefix(_ literal: [UInt8]) -> Bool {
        guard position + literal.count <= bytes.count else { return false }
        for (offset, byte) in literal.enumerated() where MermaidByte.lowercased(bytes[position + offset]) != byte { return false }
        return true
    }

    mutating func skipToEndOfLine() {
        while position < bytes.count, bytes[position] != MermaidByte.newline { position += 1 }
    }
}
