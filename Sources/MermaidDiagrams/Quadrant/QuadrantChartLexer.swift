/**
 * File: QuadrantChartLexer.swift
 * ------------------------------
 * Layer: Core
 * Description: Cuts a quadrant chart's statements into tokens as Mermaid's quadrant grammar does (Pele's port of its
 *              lexer): comments, titles, accessibility statements, keywords, texts, points and punctuation, each
 *              token holding the ranges of its text's bytes rather than a String, read on the borrowed bytes with
 *              lines counted only where a token starts.
 *
 * Authors: Félix Chevalier, Bahey Shalash
 * Version: 0.5
 * Date: 25/11/2026
 */

/// Cuts a quadrant chart's statements into tokens as Mermaid's quadrant grammar does (Pele's port of its lexer):
/// `%%` comments anywhere, `title` and the rest of its line, accessibility statements, the keywords `x-axis`,
/// `y-axis`, `quadrant-1` to `quadrant-4` and the arrow `-->` with the spaces around them, `classDef`, text in
/// quotation marks or Markdown quotation marks, `:::` and a class's name, a point's `: [x, y]`
/// (`QuadrantChartPointSyntax`), and otherwise runs of letters, digits and characters beyond ASCII, and single
/// characters. Keywords are read without regard to case. A character no rule takes is an error, as in Mermaid.
///
/// The bytes are read where they lie, by offset. A token's line is counted forward from the last token's
/// (`ChartLineCounter`); a cursor follows the offset only for an accessibility statement or an error, so that both
/// are read as the cursor reads them, moving forward only, so the whole text is stepped once.
struct QuadrantChartLexer {
    private let bytes: UnsafeBufferPointer<UInt8>
    private var position: Int
    private var lines: ChartLineCounter
    /// A cursor over the same bytes, moved forward to the offset only when a statement or an error is read with it.
    private var followingCursor: MermaidTextCursor
    private var output = QuadrantChartTokens()

    /// The tokens of the statements after the cursor, which is just past the `quadrantChart` keyword, each holding the
    /// ranges of the bytes of its text.
    static func tokens(after cursor: MermaidTextCursor) throws(MermaidDiagramReadError) -> QuadrantChartTokens {
        try cursor.bytes.withUnsafeBufferPointer { buffer throws(MermaidDiagramReadError) in
            var lexer = QuadrantChartLexer(bytes: buffer, cursor: cursor)
            while lexer.position < buffer.count { try lexer.readToken(startingWith: buffer[lexer.position]) }
            return lexer.output
        }
    }

    private init(bytes: UnsafeBufferPointer<UInt8>, cursor: MermaidTextCursor) {
        self.bytes = bytes
        position = cursor.position
        lines = ChartLineCounter(position: cursor.position, line: cursor.line)
        followingCursor = cursor
        // About one token for every three bytes: room for them is made once.
        output.tokens.reserveCapacity((bytes.count - cursor.position) / 3 + 8)
    }

    private func byte(at offset: Int) -> UInt8? {
        let index = position + offset
        return index < bytes.count ? bytes[index] : nil
    }

    private mutating func advance(by count: Int = 1) {
        position = min(bytes.count, position + count)
    }

    private mutating func readToken(startingWith byte: UInt8) throws(MermaidDiagramReadError) {
        let start = position
        if skipComment(startingWith: byte) { return }
        if byte == MermaidByte.newline || byte == MermaidByte.carriageReturn {
            while let next = self.byte(at: 0), next == MermaidByte.newline || next == MermaidByte.carriageReturn { position += 1 }
            return append(.lineBreak, from: start)
        }
        // Each keyword is tried only where its first letter is, in either case: the rules are tried in the same order.
        let lowercased = MermaidByte.lowercased(byte)
        if lowercased == UInt8(ascii: "t"), let title = readTitle() { return append(.title, content: title, from: start) }
        if lowercased == UInt8(ascii: "a"), let index = try readAccessibilityStatement() {
            return append(.accessibility, second: MermaidTextRange(start: index, end: index), from: start)
        }
        if let keyword = readKeywordWithSpaces() { return append(keyword, from: start) }
        if lowercased == UInt8(ascii: "c"), isAtWord("classdef") {
            advance(by: 8)
            return append(.classDefinition, from: start)
        }
        if byte == MermaidByte.quotationMark { return try readString(from: start) }
        if byte == MermaidByte.colon, self.byte(at: 1) == MermaidByte.colon, self.byte(at: 2) == MermaidByte.colon {
            return try readClassName(from: start)
        }
        if let coordinates = try readPoint() { return append(.point, content: coordinates.x, second: coordinates.y, from: start) }
        try readRunOrCharacter(startingWith: byte, from: start)
    }

    private mutating func append(_ kind: QuadrantChartTokenKind, content: MermaidTextRange = .empty, second: MermaidTextRange = .empty, from start: Int) {
        let line = lines.line(at: start, in: bytes)
        output.tokens.append(QuadrantChartToken(kind: kind, start: start, end: position, line: line, content: content, second: second))
    }

    /// `%%` and the rest of its line, or a character other than `}` followed by `%%` and the rest of the line: Mermaid's
    /// second comment rule takes that character with it, a line break included.
    private mutating func skipComment(startingWith byte: UInt8) -> Bool {
        if byte == MermaidByte.percent, self.byte(at: 1) == MermaidByte.percent {
            skipToEndOfLine()
            return true
        }
        guard byte != MermaidByte.closingBrace, self.byte(at: 1) == MermaidByte.percent, self.byte(at: 2) == MermaidByte.percent else { return false }
        advance(by: 3)
        skipToEndOfLine()
        return true
    }

    private mutating func skipToEndOfLine() {
        while position < bytes.count, bytes[position] != MermaidByte.newline { position += 1 }
    }

    /// `title` with no letter, digit or underscore after it, then the rest of its line, which is the title as written:
    /// its range.
    private mutating func readTitle() -> MermaidTextRange? {
        guard isAtWord("title") else { return nil }
        advance(by: 5)
        let start = position
        skipToEndOfLine()
        return MermaidTextRange(start: start, end: position)
    }

    /// `accTitle` or `accDescr` and what follows, read by the cursor brought to the offset: the statement's index among
    /// the lexer's statements, or nil when none is there.
    private mutating func readAccessibilityStatement() throws(MermaidDiagramReadError) -> Int? {
        guard hasCaseInsensitivePrefix("acctitle", at: 0) || hasCaseInsensitivePrefix("accdescr", at: 0) else { return nil }
        bringCursorToOffset()
        guard let statement = try MermaidAccessibilityStatement.read(&followingCursor) else { return nil }
        position = followingCursor.position
        output.statements.append(statement)
        return output.statements.count - 1
    }

    /// After any spaces: `x-axis`, `y-axis`, `quadrant-1` to `quadrant-4`, `quadrantChart`, or two or more hyphens and
    /// `>`, each taking the spaces after it too. Nil, with the offset where it was, when none is there.
    private mutating func readKeywordWithSpaces() -> QuadrantChartTokenKind? {
        guard let byte = byte(at: 0), Self.canStartKeyword(byte) else { return nil }
        var offset = 0
        while self.byte(at: offset) == MermaidByte.space { offset += 1 }
        guard let (kind, length) = keyword(at: offset) else { return nil }
        offset += length
        while self.byte(at: offset) == MermaidByte.space { offset += 1 }
        advance(by: offset)
        return kind
    }

    /// Whether `byte` may start a keyword with the spaces before it: a space, `x`, `y`, `-` or `q` in either case.
    private static func canStartKeyword(_ byte: UInt8) -> Bool {
        switch MermaidByte.lowercased(byte) {
        case MermaidByte.space, UInt8(ascii: "x"), UInt8(ascii: "y"), MermaidByte.hyphen, UInt8(ascii: "q"): true
        default: false
        }
    }

    /// The keyword or arrow `offset` bytes after the offset and its length in bytes, or nil.
    private func keyword(at offset: Int) -> (QuadrantChartTokenKind, Int)? {
        if hasCaseInsensitivePrefix("x-axis", at: offset) { return (.xAxis, 6) }
        if hasCaseInsensitivePrefix("y-axis", at: offset) { return (.yAxis, 6) }
        if byte(at: offset) == MermaidByte.hyphen {
            var hyphenCount = 0
            while byte(at: offset + hyphenCount) == MermaidByte.hyphen { hyphenCount += 1 }
            return hyphenCount >= 2 && byte(at: offset + hyphenCount) == MermaidByte.greaterThan ? (.axisArrow, hyphenCount + 1) : nil
        }
        guard hasCaseInsensitivePrefix("quadrant", at: offset) else { return nil }
        if byte(at: offset + 8) == MermaidByte.hyphen, let digit = byte(at: offset + 9), digit >= UInt8(ascii: "1"), digit <= UInt8(ascii: "4") {
            return (QuadrantChartTokenKind.quadrants[Int(digit - UInt8(ascii: "1"))], 10)
        }
        return hasCaseInsensitivePrefix("chart", at: offset + 8) ? (.chartKeyword, 13) : nil
    }

    /// Whether `literal` (lowercase ASCII) is `offset` bytes after the offset, ASCII letters compared without regard to case.
    private func hasCaseInsensitivePrefix(_ literal: StaticString, at offset: Int) -> Bool {
        let count = literal.utf8CodeUnitCount
        guard position + offset + count <= bytes.count else { return false }
        let letters = literal.utf8Start
        for index in 0..<count where MermaidByte.lowercased(bytes[position + offset + index]) != letters[index] { return false }
        return true
    }

    /// Whether `word` (lowercase) is at the offset in any case, with no letter, digit or underscore after it.
    private func isAtWord(_ word: StaticString) -> Bool {
        guard hasCaseInsensitivePrefix(word, at: 0) else { return false }
        return !(byte(at: word.utf8CodeUnitCount).map(Self.isWordByte) ?? false)
    }

    static func isWordByte(_ byte: UInt8) -> Bool {
        MermaidByte.isLetter(byte) || MermaidByte.isDigit(byte) || byte == MermaidByte.underscore
    }

    /// Moves the cursor that follows the offset forward to it.
    private mutating func bringCursorToOffset() {
        followingCursor.advance(by: position - followingCursor.position)
    }

    /// The error of `problem` at the offset, on the line the cursor counts there.
    private mutating func failure(_ problem: MermaidSyntaxProblem) -> MermaidDiagramReadError {
        bringCursorToOffset()
        return .invalidSyntax(line: followingCursor.line, problem: problem)
    }

    /// The error of text no rule takes at the offset: its first characters, as the cursor's excerpt gives them.
    private mutating func unexpectedText() -> MermaidDiagramReadError {
        bringCursorToOffset()
        return .invalidSyntax(line: followingCursor.line, problem: .unexpectedText(followingCursor.excerpt()))
    }
}

extension QuadrantChartLexer {
    /// Text in quotation marks, which may span lines, or a Markdown string between "` and `". Empty text makes no
    /// token, as in Mermaid's grammar; a quotation without its end is an error.
    private mutating func readString(from start: Int) throws(MermaidDiagramReadError) {
        let isMarkdown = byte(at: 1) == MermaidByte.graveAccent
        advance(by: isMarkdown ? 2 : 1)
        let textStart = position
        while position < bytes.count, bytes[position] != MermaidByte.quotationMark, !(isMarkdown && bytes[position] == MermaidByte.graveAccent) {
            position += 1
        }
        guard position < bytes.count else { throw .invalidSyntax(line: lines.line(at: start, in: bytes), problem: .unclosedQuotation) }
        let text = MermaidTextRange(start: textStart, end: position)
        if isMarkdown {
            guard byte(at: 0) == MermaidByte.graveAccent, byte(at: 1) == MermaidByte.quotationMark else { throw unexpectedText() }
            advance()
        }
        advance()
        guard !text.isEmpty else { return }
        append(isMarkdown ? .markdownString : .string, content: text, from: start)
    }

    /// `:::` and a class's name: letters, digits and underscores, at least one.
    private mutating func readClassName(from start: Int) throws(MermaidDiagramReadError) {
        advance(by: 3)
        let nameStart = position
        while position < bytes.count, Self.isWordByte(bytes[position]) { position += 1 }
        guard position > nameStart else { throw unexpectedText() }
        append(.className, content: MermaidTextRange(start: nameStart, end: position), from: start)
    }

    /// A run of letters, of digits or of bytes beyond ASCII, or one character that makes a token alone.
    private mutating func readRunOrCharacter(startingWith byte: UInt8, from start: Int) throws(MermaidDiagramReadError) {
        if MermaidByte.isLetter(byte) {
            while position < bytes.count, MermaidByte.isLetter(bytes[position]) { position += 1 }
            return append(.letters, from: start)
        }
        if byte >= 0x80 {
            while position < bytes.count, bytes[position] >= 0x80 { position += 1 }
            return append(.otherCharacters, from: start)
        }
        if MermaidByte.isDigit(byte) {
            while position < bytes.count, MermaidByte.isDigit(bytes[position]) { position += 1 }
            return append(.digits, from: start)
        }
        guard let kind = Self.singleCharacterKinds[Int(byte)] else { throw unexpectedText() }
        position += 1
        append(kind, from: start)
    }

    /// `singleCharacters` by byte, read without hashing at every token.
    private static let singleCharacterKinds: [QuadrantChartTokenKind?] = (0...255).map { byte in singleCharacters[UInt8(byte)] }

    /// The characters that make a token alone, and the token each makes.
    private static let singleCharacters: [UInt8: QuadrantChartTokenKind] = {
        var kinds: [UInt8: QuadrantChartTokenKind] = [
            MermaidByte.colon: .colon, MermaidByte.comma: .comma, MermaidByte.hyphen: .hyphen, UInt8(ascii: "#"): .numberSign,
            MermaidByte.semicolon: .semicolon, MermaidByte.ampersand: .ampersand, UInt8(ascii: "*"): .asterisk,
        ]
        for character in "+=_.!$%'`?\\/".utf8 { kinds[character] = .otherPunctuation }
        for space in [MermaidByte.space, MermaidByte.tab, 0x0B, 0x0C] { kinds[space] = .space }
        return kinds
    }()
}

extension QuadrantChartLexer {
    /// A point's `: [x, y]` at the offset (`QuadrantChartPointSyntax`): the coordinates as written, moving past them, or
    /// nil, with the offset where it was, when no point starts there. Brackets that do not hold two coordinates are an
    /// error.
    private mutating func readPoint() throws(MermaidDiagramReadError) -> (x: MermaidTextRange, y: MermaidTextRange)? {
        guard let first = byte(at: 0), first == MermaidByte.colon || QuadrantChartPointSyntax.isWhitespace(first) else { return nil }
        var offset = 0
        while let next = byte(at: offset), QuadrantChartPointSyntax.isWhitespace(next) { offset += 1 }
        guard byte(at: offset) == MermaidByte.colon else { return nil }
        offset += 1
        while let next = byte(at: offset), QuadrantChartPointSyntax.isWhitespace(next) { offset += 1 }
        guard byte(at: offset) == MermaidByte.openingBracket else { return nil }
        advance(by: offset + 1)
        skipPointWhitespace()
        let xCoordinate = try readCoordinate()
        skipPointWhitespace()
        try expectInPoint(MermaidByte.comma)
        skipPointWhitespace()
        let yCoordinate = try readCoordinate()
        skipPointWhitespace()
        try expectInPoint(MermaidByte.closingBracket)
        while byte(at: 0) == MermaidByte.space { position += 1 }
        return (xCoordinate, yCoordinate)
    }

    /// `1`, or `0`, then any character but a line break and digits when they follow it.
    private mutating func readCoordinate() throws(MermaidDiagramReadError) -> MermaidTextRange {
        let start = position
        if byte(at: 0) == UInt8(ascii: "1") {
            position += 1
        } else if byte(at: 0) == UInt8(ascii: "0") {
            position += 1
            if let next = byte(at: 0), next != MermaidByte.newline, next != MermaidByte.carriageReturn, let digit = byte(at: 1), MermaidByte.isDigit(digit) {
                position += 2
                while position < bytes.count, MermaidByte.isDigit(bytes[position]) { position += 1 }
            }
        } else {
            throw failure(.expectedPointCoordinates)
        }
        return MermaidTextRange(start: start, end: position)
    }

    private mutating func expectInPoint(_ expected: UInt8) throws(MermaidDiagramReadError) {
        guard byte(at: 0) == expected else { throw failure(.expectedPointCoordinates) }
        position += 1
    }

    private mutating func skipPointWhitespace() {
        while position < bytes.count, QuadrantChartPointSyntax.isWhitespace(bytes[position]) { position += 1 }
    }
}
