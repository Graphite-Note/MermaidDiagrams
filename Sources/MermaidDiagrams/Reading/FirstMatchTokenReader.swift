/**
 * File: FirstMatchTokenReader.swift
 * ---------------------------------
 * Layer: Core
 * Description: Reads the tokens of a Langium grammar's text one after the other for a hand-written parser, with the
 *              line of each failure, and the values of the title and accessibility statements those grammars share.
 *
 * Authors: Bahey Shalash
 * Version: 0.3
 * Date: 25/11/2026
 */

/// The tokens of a text and the one being read. A failure is placed on the line of the token where reading stopped, or
/// after the last token at the end of the text, as Chevrotain's messages place it.
struct FirstMatchTokenReader<Kind: Equatable & Sendable> {
    let bytes: [UInt8]
    let tokens: [FirstMatchToken<Kind>]
    /// Where the text read starts: the end of the diagram's keyword.
    let start: Int
    private(set) var index = 0

    init(bytes: [UInt8], tokens: [FirstMatchToken<Kind>], start: Int) {
        self.bytes = bytes
        self.tokens = tokens
        self.start = start
    }

    /// The kind of the token being read, or nil at the end.
    var kind: Kind? {
        index < tokens.count ? tokens[index].kind : nil
    }

    var isAtEnd: Bool { index >= tokens.count }

    /// The text of the token being read; empty at the end.
    var text: String {
        guard index < tokens.count else { return "" }
        return String(decoding: bytes[tokens[index].start..<tokens[index].end], as: UTF8.self)
    }

    /// The bytes of the token being read; empty at the end.
    var tokenBytes: ArraySlice<UInt8> {
        guard index < tokens.count else { return [] }
        return bytes[tokens[index].start..<tokens[index].end]
    }

    /// Where the token being read starts, or the end of the last token at the end.
    var position: Int {
        if index < tokens.count { return tokens[index].start }
        return tokens.last?.end ?? start
    }

    /// The text of the token being read, moving past it.
    mutating func take() -> String {
        let taken = text
        index += 1
        return taken
    }

    /// Moves past the token being read when it is of `kind`.
    mutating func accept(_ kind: Kind) -> Bool {
        guard self.kind == kind else { return false }
        index += 1
        return true
    }

    /// The text of the token being read when it is of `kind`, moving past it; else `problem` on its line.
    mutating func expect(_ kind: Kind, else problem: MermaidSyntaxProblem) throws(MermaidDiagramReadError) -> String {
        guard self.kind == kind else { throw failure(problem) }
        return take()
    }

    /// `problem` on the line of the token being read.
    func failure(_ problem: MermaidSyntaxProblem) -> MermaidDiagramReadError {
        .invalidSyntax(line: Self.line(of: position, in: bytes), problem: problem)
    }

    /// The 1-based line of `position` in `bytes`.
    static func line(of position: Int, in bytes: [UInt8]) -> Int {
        1 + bytes[..<min(position, bytes.count)].reduce(0) { count, byte in byte == MermaidByte.newline ? count + 1 : count }
    }

    /// The first characters at `position`, for an error that shows what could not be read.
    static func excerpt(at position: Int, in bytes: [UInt8]) -> String {
        var cursor = MermaidTextCursor(bytes: bytes)
        cursor.advance(by: position)
        return cursor.excerpt()
    }
}

/// The values of the title and accessibility statements of Langium's grammars, as Mermaid's value converters give them.
enum FirstMatchStatementValues {
    /// After `title`, trimmed, each run of two or more blanks one space.
    static func title(of statement: String) -> String {
        single(String(text(after: "title", in: statement)))
    }

    /// After `accTitle` and its colon, trimmed, runs of blanks one space.
    static func accessibilityTitle(of statement: String) -> String {
        let afterKeyword = text(after: "accTitle", in: statement)
        return single(String(afterKeyword.drop { character in character != ":" }.dropFirst()))
    }

    /// After `accDescr` and its colon as for a title; or the text between its braces, each line trimmed, blank lines
    /// left out, and runs of blanks one space.
    static func accessibilityDescription(of statement: String) -> String {
        let afterKeyword = text(after: "accDescr", in: statement)
        let written = afterKeyword.drop { character in character == " " || character == "\t" }
        if written.first == ":" { return single(String(written.dropFirst())) }
        let inside = afterKeyword.drop { character in character != "{" }.dropFirst().prefix { character in character != "}" }
        // `\r\n` is one Character in Swift: it breaks a line as `\n` and `\r` do, as Pele makes every line break `\n` first.
        let lines = inside.split(omittingEmptySubsequences: false) { character in character == "\n" || character == "\r" || character == "\r\n" }
            .map { line in trimmed(String(line)) }
            .filter { line in !line.isEmpty }
        return lines.map(collapsingBlanks).joined(separator: "\n")
    }

    /// The text after the first `keyword` in `statement`.
    /// A statement of ASCII alone, as nearly all are, is searched on its bytes, where Foundation's search finds the same
    /// place; any other through Foundation, which compares characters as Unicode makes them equal.
    private static func text(after keyword: String, in statement: String) -> Substring {
        let utf8 = statement.utf8
        if let search = utf8.withContiguousStorageIfAvailable({ bytes in asciiSearch(for: keyword, in: bytes) }), search.isASCII {
            guard let end = search.end else { return "" }
            return statement[utf8.index(utf8.startIndex, offsetBy: end)...]
        }
        guard let range = statement.range(of: keyword) else { return "" }
        return statement[range.upperBound...]
    }

    /// Whether `bytes` and `keyword` are ASCII alone, and if so where the first `keyword` in `bytes` ends, nil when it is
    /// not there (or empty, which Foundation finds nowhere).
    private static func asciiSearch(for keyword: String, in bytes: UnsafeBufferPointer<UInt8>) -> (isASCII: Bool, end: Int?) {
        var combined: UInt8 = 0
        for byte in bytes { combined |= byte }
        for byte in keyword.utf8 { combined |= byte }
        guard combined < 0x80 else { return (false, nil) }
        let needle = Array(keyword.utf8)
        guard !needle.isEmpty else { return (true, nil) }
        var start = 0
        while start + needle.count <= bytes.count {
            var offset = 0
            while offset < needle.count, bytes[start + offset] == needle[offset] { offset += 1 }
            if offset == needle.count { return (true, start + needle.count) }
            start += 1
        }
        return (true, nil)
    }

    private static func single(_ text: String) -> String {
        collapsingBlanks(trimmed(text))
    }

    /// The text without JavaScript's whitespace at either end, as `trim` leaves it.
    static func trimmed(_ text: String) -> String {
        String(decoding: JavaScriptWhitespace.trimmed(Array(text.utf8)[...]), as: UTF8.self)
    }

    /// Each run of two or more spaces and tabs as one space.
    private static func collapsingBlanks(_ text: String) -> String {
        guard MermaidByte.hasBlankRun(text), text.contains("  ") || text.contains("\t") else { return text }
        var result = ""
        var blankRun = ""
        for character in text {
            if character == " " || character == "\t" {
                blankRun.append(character)
                continue
            }
            result += blankRun.count >= 2 ? " " : blankRun
            blankRun = ""
            result.append(character)
        }
        return result + (blankRun.count >= 2 ? " " : blankRun)
    }
}
