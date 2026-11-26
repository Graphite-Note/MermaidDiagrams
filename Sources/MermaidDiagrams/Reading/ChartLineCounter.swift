/**
 * File: ChartLineCounter.swift
 * ----------------------------
 * Layer: Core
 * Description: Counts the lines of a diagram's bytes forward, from one offset asked for to the next, so that a reader
 *              stepping its bytes by offset gives each token the line a cursor would have counted to it.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 25/11/2026
 */

/// The line of an offset in a diagram's bytes, counted forward from the offset asked for before: a reader that reads by
/// offset and asks for the lines of increasing offsets steps each byte once, as `MermaidTextCursor.advance` would have.
/// An offset before the last one asked for is given the last one's line, which a reader moving forward never asks.
struct ChartLineCounter {
    private var position: Int
    private var line: Int

    /// Counting starts at `position`, which is on `line`.
    init(position: Int, line: Int) {
        self.position = position
        self.line = line
    }

    /// The line `target` is on: one more than the line counting started on for each line feed before it.
    mutating func line(at target: Int, in bytes: UnsafeBufferPointer<UInt8>) -> Int {
        let end = min(target, bytes.count)
        while position < end {
            if bytes[position] == MermaidByte.newline { line += 1 }
            position += 1
        }
        return line
    }
}
