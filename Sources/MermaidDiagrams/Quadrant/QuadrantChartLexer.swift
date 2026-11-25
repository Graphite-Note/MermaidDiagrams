/**
 * File: QuadrantChartLexer.swift
 * ------------------------------
 * Layer: Core
 * Description: Cuts a quadrant chart's statements into tokens as Mermaid's quadrant grammar does (Pele's port of its
 *              lexer): comments, titles, accessibility statements, keywords, texts, points and punctuation, each
 *              token holding the ranges of its text's bytes rather than a String.
 *
 * Authors: Félix Chevalier, Bahey Shalash
 * Version: 0.4
 * Date: 25/11/2026
 */

/// Cuts a quadrant chart's statements into tokens as Mermaid's quadrant grammar does (Pele's port of its lexer):
/// `%%` comments anywhere, `title` and the rest of its line, accessibility statements, the keywords `x-axis`,
/// `y-axis`, `quadrant-1` to `quadrant-4` and the arrow `-->` with the spaces around them, `classDef`, text in
/// quotation marks or Markdown quotation marks, `:::` and a class's name, a point's `: [x, y]`
/// (`QuadrantChartPointSyntax`), and otherwise runs of letters, digits and characters beyond ASCII, and single
/// characters. Keywords are read without regard to case. A character no rule takes is an error, as in Mermaid.
struct QuadrantChartLexer {
    private var cursor: MermaidTextCursor
    private var output = QuadrantChartTokens()

    /// The tokens of the statements after the cursor, which is just past the `quadrantChart` keyword, each holding the
    /// ranges of the bytes of its text.
    static func tokens(after cursor: MermaidTextCursor) throws(MermaidDiagramReadError) -> QuadrantChartTokens {
        var lexer = QuadrantChartLexer(cursor: cursor)
        while let byte = lexer.cursor.peek() { try lexer.readToken(startingWith: byte) }
        return lexer.output
    }

    private init(cursor: MermaidTextCursor) {
        self.cursor = cursor
        // About one token for every three bytes: room for them is made once.
        output.tokens.reserveCapacity((cursor.bytes.count - cursor.position) / 3 + 8)
    }

    private mutating func readToken(startingWith byte: UInt8) throws(MermaidDiagramReadError) {
        let start = TokenStart(position: cursor.position, line: cursor.line)
        if skipComment(startingWith: byte) { return }
        if byte == MermaidByte.newline || byte == MermaidByte.carriageReturn {
            while let next = cursor.peek(), next == MermaidByte.newline || next == MermaidByte.carriageReturn { cursor.advance() }
            return append(.lineBreak, from: start)
        }
        // Each keyword is tried only where its first letter is, in either case: the rules are tried in the same order.
        let lowercased = MermaidByte.lowercased(byte)
        if lowercased == Self.titleKeyword[0], let title = readTitle() { return append(.title, content: title, from: start) }
        if lowercased == Self.accessibilityKeywordStart, let statement = try MermaidAccessibilityStatement.read(&cursor) {
            output.statements.append(statement)
            let index = output.statements.count - 1
            return append(.accessibility, second: MermaidTextRange(start: index, end: index), from: start)
        }
        if let keyword = readKeywordWithSpaces() { return append(keyword, from: start) }
        if lowercased == Self.classDefinitionKeyword[0], isAtWord(Self.classDefinitionKeyword) {
            cursor.advance(by: Self.classDefinitionKeyword.count)
            return append(.classDefinition, from: start)
        }
        if byte == MermaidByte.quotationMark { return try readString(from: start) }
        if byte == MermaidByte.colon, cursor.hasPrefix(Self.classMarker) { return try readClassName(from: start) }
        if let coordinates = try QuadrantChartPointSyntax.readPoint(&cursor) {
            return append(.point, content: coordinates.x, second: coordinates.y, from: start)
        }
        try readRunOrCharacter(startingWith: byte, from: start)
    }

    /// Where a token starts: its position and line, kept without copying the cursor at every token.
    private struct TokenStart {
        let position: Int
        let line: Int
    }

    private mutating func append(_ kind: QuadrantChartTokenKind, content: MermaidTextRange = .empty, second: MermaidTextRange = .empty,
                                 from start: TokenStart) {
        output.tokens.append(QuadrantChartToken(kind: kind, start: start.position, end: cursor.position, line: start.line, content: content, second: second))
    }

    /// `%%` and the rest of its line, or a character other than `}` followed by `%%` and the rest of the line: Mermaid's
    /// second comment rule takes that character with it, a line break included.
    private mutating func skipComment(startingWith byte: UInt8) -> Bool {
        if byte == MermaidByte.percent, cursor.peek(1) == MermaidByte.percent {
            cursor.skipToEndOfLine()
            return true
        }
        guard byte != MermaidByte.closingBrace, cursor.peek(1) == MermaidByte.percent, cursor.peek(2) == MermaidByte.percent else { return false }
        cursor.advance(by: 3)
        cursor.skipToEndOfLine()
        return true
    }

    /// `title` with no letter, digit or underscore after it, then the rest of its line, which is the title as written:
    /// its range.
    private mutating func readTitle() -> MermaidTextRange? {
        guard isAtWord(Self.titleKeyword) else { return nil }
        cursor.advance(by: Self.titleKeyword.count)
        let start = cursor.position
        cursor.skipToEndOfLine()
        return MermaidTextRange(start: start, end: cursor.position)
    }

    /// After any spaces: `x-axis`, `y-axis`, `quadrant-1` to `quadrant-4`, `quadrantChart`, or two or more hyphens and
    /// `>`, each taking the spaces after it too. Nil, with the cursor where it was, when none is there.
    private mutating func readKeywordWithSpaces() -> QuadrantChartTokenKind? {
        guard let byte = cursor.peek(), Self.canStartKeyword(byte) else { return nil }
        var offset = 0
        while cursor.peek(offset) == MermaidByte.space { offset += 1 }
        guard let (kind, length) = keyword(at: offset) else { return nil }
        offset += length
        while cursor.peek(offset) == MermaidByte.space { offset += 1 }
        cursor.advance(by: offset)
        return kind
    }

    /// Whether `byte` may start a keyword with the spaces before it: a space, `x`, `y`, `-` or `q` in either case.
    private static func canStartKeyword(_ byte: UInt8) -> Bool {
        switch MermaidByte.lowercased(byte) {
        case MermaidByte.space, UInt8(ascii: "x"), UInt8(ascii: "y"), MermaidByte.hyphen, UInt8(ascii: "q"): true
        default: false
        }
    }

    /// The keyword or arrow `offset` bytes after the cursor and its length in bytes, or nil.
    private func keyword(at offset: Int) -> (QuadrantChartTokenKind, Int)? {
        if hasCaseInsensitivePrefix(Self.xAxisKeyword, at: offset) { return (.xAxis, Self.xAxisKeyword.count) }
        if hasCaseInsensitivePrefix(Self.yAxisKeyword, at: offset) { return (.yAxis, Self.yAxisKeyword.count) }
        if cursor.peek(offset) == MermaidByte.hyphen {
            var hyphenCount = 0
            while cursor.peek(offset + hyphenCount) == MermaidByte.hyphen { hyphenCount += 1 }
            return hyphenCount >= 2 && cursor.peek(offset + hyphenCount) == MermaidByte.greaterThan ? (.axisArrow, hyphenCount + 1) : nil
        }
        guard hasCaseInsensitivePrefix(Self.quadrantKeyword, at: offset) else { return nil }
        let quadrantLength = Self.quadrantKeyword.count
        if cursor.peek(offset + quadrantLength) == MermaidByte.hyphen, let digit = cursor.peek(offset + quadrantLength + 1),
           (Self.firstQuadrantDigit...Self.lastQuadrantDigit).contains(digit) {
            return (QuadrantChartTokenKind.quadrants[Int(digit - Self.firstQuadrantDigit)], quadrantLength + 2)
        }
        return hasCaseInsensitivePrefix(Self.chartKeyword, at: offset + quadrantLength) ? (.chartKeyword, quadrantLength + Self.chartKeyword.count) : nil
    }

    /// Whether `literal` (lowercase) is `offset` bytes after the cursor, ASCII letters compared without regard to case.
    private func hasCaseInsensitivePrefix(_ literal: [UInt8], at offset: Int) -> Bool {
        for (index, byte) in literal.enumerated() {
            guard let written = cursor.peek(offset + index), MermaidByte.lowercased(written) == byte else { return false }
        }
        return true
    }

    /// Text in quotation marks, which may span lines, or a Markdown string between "` and `". Empty text makes no
    /// token, as in Mermaid's grammar; a quotation without its end is an error.
    private mutating func readString(from start: TokenStart) throws(MermaidDiagramReadError) {
        let isMarkdown = cursor.peek(1) == MermaidByte.graveAccent
        cursor.advance(by: isMarkdown ? 2 : 1)
        let textStart = cursor.position
        while let byte = cursor.peek(), byte != MermaidByte.quotationMark, !(isMarkdown && byte == MermaidByte.graveAccent) { cursor.advance() }
        guard !cursor.isAtEnd else { throw .invalidSyntax(line: start.line, problem: .unclosedQuotation) }
        let text = MermaidTextRange(start: textStart, end: cursor.position)
        if isMarkdown {
            guard cursor.peek() == MermaidByte.graveAccent, cursor.peek(1) == MermaidByte.quotationMark else {
                throw .invalidSyntax(line: cursor.line, problem: .unexpectedText(cursor.excerpt()))
            }
            cursor.advance()
        }
        cursor.advance()
        guard !text.isEmpty else { return }
        append(isMarkdown ? .markdownString : .string, content: text, from: start)
    }

    /// `:::` and a class's name: letters, digits and underscores, at least one.
    private mutating func readClassName(from start: TokenStart) throws(MermaidDiagramReadError) {
        cursor.advance(by: Self.classMarker.count)
        let nameStart = cursor.position
        while let byte = cursor.peek(), Self.isWordByte(byte) { cursor.advance() }
        guard cursor.position > nameStart else { throw .invalidSyntax(line: cursor.line, problem: .unexpectedText(cursor.excerpt())) }
        append(.className, content: MermaidTextRange(start: nameStart, end: cursor.position), from: start)
    }

    /// A run of letters, of digits or of bytes beyond ASCII, or one character that makes a token alone.
    private mutating func readRunOrCharacter(startingWith byte: UInt8, from start: TokenStart) throws(MermaidDiagramReadError) {
        if MermaidByte.isLetter(byte) {
            skipRun(of: MermaidByte.isLetter)
            return append(.letters, from: start)
        }
        if byte >= Self.firstByteBeyondASCII {
            skipRun { next in next >= Self.firstByteBeyondASCII }
            return append(.otherCharacters, from: start)
        }
        if MermaidByte.isDigit(byte) {
            skipRun(of: MermaidByte.isDigit)
            return append(.digits, from: start)
        }
        guard let kind = Self.singleCharacterKinds[Int(byte)] else { throw .invalidSyntax(line: cursor.line, problem: .unexpectedText(cursor.excerpt())) }
        cursor.advance()
        append(kind, from: start)
    }

    private mutating func skipRun(of isInRun: (UInt8) -> Bool) {
        while let byte = cursor.peek(), isInRun(byte) { cursor.advance() }
    }

    /// Whether `word` (lowercase) is at the cursor in any case, with no letter, digit or underscore after it.
    private func isAtWord(_ word: [UInt8]) -> Bool {
        guard cursor.hasCaseInsensitivePrefix(word) else { return false }
        return !(cursor.peek(word.count).map(Self.isWordByte) ?? false)
    }

    static func isWordByte(_ byte: UInt8) -> Bool {
        MermaidByte.isLetter(byte) || MermaidByte.isDigit(byte) || byte == MermaidByte.underscore
    }

    /// `singleCharacters` by byte, read without hashing at every token.
    private static let singleCharacterKinds: [QuadrantChartTokenKind?] = (0...255).map { byte in singleCharacters[UInt8(byte)] }

    /// The characters that make a token alone, and the token each makes.
    private static let singleCharacters: [UInt8: QuadrantChartTokenKind] = {
        var kinds: [UInt8: QuadrantChartTokenKind] = [
            MermaidByte.colon: .colon, MermaidByte.comma: .comma, MermaidByte.hyphen: .hyphen, numberSign: .numberSign,
            MermaidByte.semicolon: .semicolon, MermaidByte.ampersand: .ampersand, asterisk: .asterisk,
        ]
        for character in "+=_.!$%'`?\\/".utf8 { kinds[character] = .otherPunctuation }
        for space in [MermaidByte.space, MermaidByte.tab, verticalTab, formFeed] { kinds[space] = .space }
        return kinds
    }()

    private static let titleKeyword = Array("title".utf8)
    /// The first letter of `accTitle` and `accDescr`, lowercased.
    private static let accessibilityKeywordStart = UInt8(ascii: "a")
    private static let classDefinitionKeyword = Array("classdef".utf8)
    private static let xAxisKeyword = Array("x-axis".utf8)
    private static let yAxisKeyword = Array("y-axis".utf8)
    private static let quadrantKeyword = Array("quadrant".utf8)
    private static let chartKeyword = Array("chart".utf8)
    private static let classMarker = Array(":::".utf8)
    private static let firstQuadrantDigit = UInt8(ascii: "1")
    private static let lastQuadrantDigit = UInt8(ascii: "4")
    private static let firstByteBeyondASCII: UInt8 = 0x80
    private static let numberSign = UInt8(ascii: "#")
    private static let asterisk = UInt8(ascii: "*")
    private static let verticalTab: UInt8 = 0x0B
    private static let formFeed: UInt8 = 0x0C
}
