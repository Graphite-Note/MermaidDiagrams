/**
 * File: GraphDiagramBytesReading.swift
 * ------------------------------------
 * Layer: Core
 * Description: What the entity relationship and class readers read on a diagram's borrowed bytes as they read on
 *              MermaidTextCursor in 0.7.0: literals compared exactly or without regard to case, the rest of a line,
 *              the text between two positions, and a position's line and excerpt for an error.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 25/11/2026
 */

extension GraphDiagramBytes {
    /// Whether the bytes at the position are `literal`, compared exactly.
    @inline(__always) func hasPrefix(_ literal: StaticString) -> Bool {
        let count = literal.utf8CodeUnitCount
        guard position + count <= buffer.count else { return false }
        let literalBytes = literal.utf8Start
        for offset in 0..<count where buffer[position + offset] != literalBytes[offset] { return false }
        return true
    }

    /// Whether the bytes at the position are `literal`, lowercase ASCII, with ASCII letters compared without regard to
    /// case (`MermaidTextCursor.hasCaseInsensitivePrefix`).
    func hasCaseInsensitivePrefix(_ literal: [UInt8]) -> Bool {
        guard position + literal.count <= buffer.count else { return false }
        for offset in 0..<literal.count where MermaidByte.lowercased(buffer[position + offset]) != literal[offset] { return false }
        return true
    }

    /// The text of the bytes from `start` to `end`.
    func text(from start: Int, to end: Int) -> String {
        String(decoding: UnsafeBufferPointer(rebasing: buffer[start..<end]), as: UTF8.self)
    }

    /// The text from the position to the end of its line, without the line break and trailing spaces; moves past it
    /// (`MermaidTextCursor.readRestOfLine`).
    mutating func readRestOfLine() -> String {
        text(readRestOfLineRange())
    }

    /// The bytes `readRestOfLine` reads, without making their text.
    mutating func readRestOfLineRange() -> MermaidTextRange {
        let start = position
        skipToEndOfLine()
        var end = position
        while end > start, MermaidByte.isSpace(buffer[end - 1]) || buffer[end - 1] == MermaidByte.carriageReturn { end -= 1 }
        return MermaidTextRange(start: start, end: end)
    }

    /// The 1-based line of `offset`, counted only when an error asks for it.
    func line(at offset: Int) -> Int {
        MermaidSourceText.line(at: offset, in: buffer)
    }

    /// The first characters at `offset`, for an error that shows what could not be read.
    func excerpt(at offset: Int) -> String {
        MermaidSourceText.excerpt(at: offset, in: buffer)
    }
}
