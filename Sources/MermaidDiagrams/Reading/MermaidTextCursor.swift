/**
 * File: MermaidTextCursor.swift
 * -----------------------------
 * Layer: Core
 * Description: A position in a diagram's UTF-8 bytes, with its line, and the text the diagram's configuration is read from.
 *
 * Authors: Félix Chevalier, Bahey Shalash
 * Version: 0.5
 * Date: 23/11/2026
 */

/// A position in a diagram's UTF-8 bytes, with the line it is on. Readers move it forward only; a lookahead copies it.
struct MermaidTextCursor {
    /// The text the diagram's statements are read from, preprocessed as Pele does (`MermaidPreprocessing`).
    let bytes: [UInt8]
    /// The text as written and its front matter, behind one reference, nil when they are `bytes` and not looked at: so
    /// that copying the cursor, as every lookahead does, retains no more than its bytes and that reference.
    private let source: MermaidCursorSource?
    private(set) var position: Int
    /// The 1-based line of `position` in the diagram's text.
    private(set) var line: Int

    /// The text as written, line breaks made line feeds, with its front matter and directives, which a type's options
    /// are read from (`MermaidConfigurationOptions`).
    var sourceBytes: [UInt8] { source?.bytes ?? bytes }
    /// The front matter of `sourceBytes` once the reader has found and read it; nil when it has not looked.
    var readFrontMatter: MermaidReadFrontMatter? { source?.readFrontMatter }

    init(bytes: [UInt8]) {
        self.bytes = bytes
        source = nil
        position = 0
        line = 1
    }

    init(bytes: [UInt8], sourceBytes: [UInt8], readFrontMatter: MermaidReadFrontMatter? = nil) {
        self.bytes = bytes
        source = MermaidCursorSource(bytes: sourceBytes, readFrontMatter: readFrontMatter)
        position = 0
        line = 1
    }

    var isAtEnd: Bool { position >= bytes.count }

    /// A place the cursor was at, to come back to: a lookahead that keeps it costs no copy of the cursor.
    struct Mark {
        fileprivate let position: Int
        fileprivate let line: Int
    }

    /// The place the cursor is at.
    var mark: Mark { Mark(position: position, line: line) }

    /// Moves the cursor back to a place it was at.
    mutating func move(to mark: Mark) {
        position = mark.position
        line = mark.line
    }

    /// The byte `offset` places ahead, or nil past the end.
    func peek(_ offset: Int = 0) -> UInt8? {
        let index = position + offset
        return index < bytes.count ? bytes[index] : nil
    }

    mutating func advance(by count: Int = 1) {
        let end = min(bytes.count, position + count)
        while position < end {
            if bytes[position] == MermaidByte.newline { line += 1 }
            position += 1
        }
    }

    /// Whether the bytes at the position are `literal`, compared exactly.
    func hasPrefix(_ literal: [UInt8]) -> Bool {
        guard position + literal.count <= bytes.count else { return false }
        for offset in literal.indices where bytes[position + offset] != literal[offset] { return false }
        return true
    }

    /// Whether the bytes at the position are `literal` with ASCII letters compared without regard to case.
    func hasCaseInsensitivePrefix(_ literal: [UInt8]) -> Bool {
        guard position + literal.count <= bytes.count else { return false }
        for (offset, byte) in literal.enumerated() where MermaidByte.lowercased(bytes[position + offset]) != byte { return false }
        return true
    }

    /// Skips spaces and tabs, never a line break.
    mutating func skipSpaces() {
        while position < bytes.count, MermaidByte.isSpace(bytes[position]) { position += 1 }
    }

    /// Skips spaces, tabs, carriage returns and line breaks.
    mutating func skipWhitespace() {
        while position < bytes.count, case let byte = bytes[position], MermaidByte.isWhitespace(byte) {
            if byte == MermaidByte.newline { line += 1 }
            position += 1
        }
    }

    /// Moves to the line break that ends the current line, or to the end.
    mutating func skipToEndOfLine() {
        while position < bytes.count, bytes[position] != MermaidByte.newline { position += 1 }
    }

    /// The text of the bytes from `start` to `end`.
    func text(from start: Int, to end: Int) -> String {
        String(decoding: bytes[start..<end], as: UTF8.self)
    }

    /// The text of the bytes from `start` to `end` without the spaces, tabs and line breaks at either end.
    func trimmedText(from start: Int, to end: Int) -> String {
        var first = start
        var last = end
        while first < last, MermaidByte.isWhitespace(bytes[first]) { first += 1 }
        while last > first, MermaidByte.isWhitespace(bytes[last - 1]) { last -= 1 }
        return text(from: first, to: last)
    }

    /// The text from the position to the end of its line, without the line break and trailing spaces; moves past it.
    mutating func readRestOfLine() -> String {
        let start = position
        skipToEndOfLine()
        var end = position
        while end > start, MermaidByte.isSpace(bytes[end - 1]) || bytes[end - 1] == MermaidByte.carriageReturn { end -= 1 }
        return text(from: start, to: end)
    }

    /// Reads a run of identifier bytes (`MermaidByte.isIdentifierByte`), with a `-` kept only where a letter, digit or
    /// underscore follows it, so that `step-1` is one identifier and `A-->B` stops before the link. Nil when there is none.
    mutating func readIdentifier() -> String? {
        let start = position
        while let byte = peek() {
            if MermaidByte.isIdentifierByte(byte) {
                advance()
            } else if byte == MermaidByte.hyphen, position > start, let next = peek(1), MermaidByte.isIdentifierByte(next) {
                advance()
            } else {
                break
            }
        }
        return position > start ? text(from: start, to: position) : nil
    }

    /// Where the run of ASCII letters from the position ends; the position when there is none.
    func endOfLetters() -> Int {
        var end = position
        while end < bytes.count, MermaidByte.isLetter(bytes[end]) { end += 1 }
        return end
    }

    /// Whether the bytes from `start` to `end` are `literal`.
    func bytes(from start: Int, to end: Int, equal literal: [UInt8]) -> Bool {
        guard end - start == literal.count else { return false }
        for offset in literal.indices where bytes[start + offset] != literal[offset] { return false }
        return true
    }

    /// Reads ASCII letters only, for a keyword. Nil when there is none.
    mutating func readWord() -> String? {
        let start = position
        while let byte = peek(), MermaidByte.isLetter(byte) { advance() }
        return position > start ? text(from: start, to: position) : nil
    }

    /// The first characters at the position, for an error that shows what could not be read.
    func excerpt(maximumBytes: Int = 24) -> String {
        var end = min(bytes.count, position + maximumBytes)
        if let lineEnd = bytes[position..<end].firstIndex(of: MermaidByte.newline) { end = lineEnd }
        // Never cut a character in two.
        while end < bytes.count, end > position, bytes[end] & 0xC0 == 0x80 { end -= 1 }
        return text(from: position, to: end)
    }
}

/// The text a cursor's diagram was written as and the front matter the reader found in it, shared by every copy of the
/// cursor and never changed.
private final class MermaidCursorSource {
    let bytes: [UInt8]
    let readFrontMatter: MermaidReadFrontMatter?

    init(bytes: [UInt8], readFrontMatter: MermaidReadFrontMatter?) {
        self.bytes = bytes
        self.readFrontMatter = readFrontMatter
    }
}
