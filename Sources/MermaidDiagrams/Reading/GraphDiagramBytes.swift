/**
 * File: GraphDiagramBytes.swift
 * -----------------------------
 * Layer: Core
 * Description: A position in a diagram's text borrowed as bytes for its reading, which a state or class diagram's
 *              reader moves along: peeking, skipping spaces and lines, comparing short literals, and the line of a
 *              position counted only when an error reports it.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 25/11/2026
 */

/// The bytes of a diagram's text, valid while the reading that borrowed them runs, and a position in them. Unlike
/// `MermaidTextCursor` it counts no lines as it moves: an error asks for the line of its position, which counts the
/// line feeds before it, as the cursor counted them.
struct GraphDiagramBytes {
    let buffer: UnsafeBufferPointer<UInt8>
    var position: Int
    /// Whether every byte of the text is ASCII, where a byte is a character and Swift's String comparisons and
    /// Foundation's searches find what a byte comparison finds.
    let isASCII: Bool

    init(_ buffer: UnsafeBufferPointer<UInt8>, position: Int) {
        self.buffer = buffer
        self.position = min(position, buffer.count)
        isASCII = GraphDiagramNameTable.isASCII(buffer)
    }

    var isAtEnd: Bool { position >= buffer.count }

    /// The byte `offset` past the position, or nil past the end.
    @inline(__always) func peek(_ offset: Int = 0) -> UInt8? {
        let index = position &+ offset
        return index < buffer.count ? buffer[index] : nil
    }

    /// The byte `offset` past the position, or 0 past the end (no text read here holds a zero byte that matters).
    @inline(__always) func byte(_ offset: Int = 0) -> UInt8 {
        let index = position &+ offset
        return index < buffer.count ? buffer[index] : 0
    }

    @inline(__always) mutating func advance(by count: Int = 1) {
        position = min(buffer.count, position &+ count)
    }

    /// Whether the bytes at the position are `first` then `second`.
    @inline(__always) func isAt(_ first: UInt8, _ second: UInt8) -> Bool {
        position &+ 1 < buffer.count && buffer[position] == first && buffer[position &+ 1] == second
    }

    /// Whether the bytes at the position are `first`, `second` then `third`.
    @inline(__always) func isAt(_ first: UInt8, _ second: UInt8, _ third: UInt8) -> Bool {
        position &+ 2 < buffer.count && buffer[position] == first && buffer[position &+ 1] == second && buffer[position &+ 2] == third
    }

    /// Whether `%%`, which starts a comment, is at the position.
    @inline(__always) var isAtCommentStart: Bool { isAt(MermaidByte.percent, MermaidByte.percent) }

    /// Whether the bytes at the position are `literal`, ASCII letters compared without regard to case (`literal` is
    /// lowercase).
    func hasCaseInsensitivePrefix(_ literal: StaticString) -> Bool {
        let count = literal.utf8CodeUnitCount
        guard position + count <= buffer.count else { return false }
        let literalBytes = literal.utf8Start
        for offset in 0..<count where MermaidByte.lowercased(buffer[position + offset]) != literalBytes[offset] { return false }
        return true
    }

    /// Skips spaces and tabs, never a line break.
    @inline(__always) mutating func skipSpaces() {
        while position < buffer.count, MermaidByte.isSpace(buffer[position]) { position &+= 1 }
    }

    /// Skips spaces, tabs, carriage returns and line breaks.
    @inline(__always) mutating func skipWhitespace() {
        while position < buffer.count, case let byte = buffer[position],
              MermaidByte.isSpace(byte) || byte == MermaidByte.newline || byte == MermaidByte.carriageReturn {
            position &+= 1
        }
    }

    /// Moves to the line break that ends the current line, or to the end.
    @inline(__always) mutating func skipToEndOfLine() {
        while position < buffer.count, buffer[position] != MermaidByte.newline { position &+= 1 }
    }

    /// The run of ASCII letters at the position, which the position moves past; empty when there is none.
    mutating func readWord() -> MermaidTextRange {
        let start = position
        while position < buffer.count, MermaidByte.isLetter(buffer[position]) { position &+= 1 }
        return MermaidTextRange(start: start, end: position)
    }

    /// The text of `range`.
    func text(_ range: MermaidTextRange) -> String {
        String(decoding: UnsafeBufferPointer(rebasing: buffer[range.lowerBound..<range.upperBound]), as: UTF8.self)
    }

    /// `start..<end` without the spaces, tabs and line breaks at either end (`MermaidTextCursor.trimmedText`).
    func trimmed(from start: Int, to end: Int) -> MermaidTextRange {
        var first = start
        var last = end
        while first < last, MermaidByte.isWhitespace(buffer[first]) { first += 1 }
        while last > first, MermaidByte.isWhitespace(buffer[last - 1]) { last -= 1 }
        return MermaidTextRange(start: first, end: last)
    }

    /// The 1-based line of the position, as `MermaidTextCursor.line` counts it.
    var line: Int { MermaidSourceText.line(at: position, in: buffer) }

    /// The first characters at the position, for an error that shows what could not be read (`MermaidTextCursor.excerpt`).
    func excerpt() -> String {
        MermaidSourceText.excerpt(at: position, in: buffer)
    }
}
