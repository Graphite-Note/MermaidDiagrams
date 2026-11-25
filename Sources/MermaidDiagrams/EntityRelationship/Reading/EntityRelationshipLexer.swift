/**
 * File: EntityRelationshipLexer.swift
 * -----------------------------------
 * Layer: Core
 * Description: The tokens of an entity relationship diagram's statements outside its entities' blocks, read on the
 *              text's borrowed bytes as Mermaid's lexer reads them: names as byte ranges, symbols, cardinalities,
 *              lines, keywords, accessibility text and directions.
 *
 * Authors: felixchvl, Bahey Shalash
 * Version: 0.2
 * Date: 25/11/2026
 */

import Foundation

/// Reads the tokens of an entity relationship diagram's statements from its UTF-8 bytes, outside an entity's `{ … }`,
/// as Mermaid's lexer does: accessibility text and `direction` first, then symbols, numbers (where `1` is a
/// cardinality when a name or a line follows it), the words of cardinalities, lines and keywords wherever they stand,
/// and names. Spaces, tabs, carriage returns and `%%` comments are skipped; a line break is a token.
struct EntityRelationshipLexer {
    var bytes: GraphDiagramBytes

    /// Skips what separates tokens and reads the token there, with the position of its first byte, for the line and
    /// the text an error reports.
    mutating func readToken() throws(MermaidDiagramReadError) -> (token: EntityRelationshipToken, start: Int) {
        skipSeparators()
        let start = bytes.position
        guard let byte = bytes.peek() else { return (.endOfText, start) }
        return (try token(startingWith: byte), start)
    }

    private mutating func skipSeparators() {
        while let byte = bytes.peek() {
            if MermaidByte.isSpace(byte) || byte == MermaidByte.carriageReturn {
                bytes.advance()
            } else if bytes.isAtCommentStart {
                bytes.skipToEndOfLine()
            } else {
                return
            }
        }
    }

    private mutating func token(startingWith byte: UInt8) throws(MermaidDiagramReadError) -> EntityRelationshipToken {
        let lowercased = MermaidByte.lowercased(byte)
        if lowercased == UInt8(ascii: "a"), let accessibilityText = try readAccessibilityText() { return accessibilityText }
        if lowercased == UInt8(ascii: "d"), let direction = readDirection() { return .direction(direction) }
        if let symbol = readSymbol(byte) { return symbol }
        if byte == MermaidByte.quotationMark { return try readQuotedText() }
        if MermaidByte.isDigit(byte) { return readNumber(startingWith: byte) }
        if let word = EntityRelationshipWords.readToken(&bytes) { return word }
        guard Self.isNameByte(byte) else {
            bytes.advance()
            return .unexpectedCharacter
        }
        let start = bytes.position
        while let next = bytes.peek(), Self.isNameByte(next) { bytes.advance() }
        return .name(MermaidTextRange(start: start, end: bytes.position), form: .bare)
    }

    /// A line break, a brace, a bracket, `:::`, `:` or `,`; nil for any other byte.
    private mutating func readSymbol(_ byte: UInt8) -> EntityRelationshipToken? {
        let token: EntityRelationshipToken
        switch byte {
        case MermaidByte.newline:
            while bytes.peek() == MermaidByte.newline { bytes.advance() }
            return .lineBreak
        case MermaidByte.openingBrace: token = .openingBrace
        case MermaidByte.openingBracket: token = .openingBracket
        case MermaidByte.closingBracket: token = .closingBracket
        case MermaidByte.comma: token = .comma
        case MermaidByte.colon:
            if bytes.isAt(MermaidByte.colon, MermaidByte.colon, MermaidByte.colon) {
                bytes.advance(by: 3)
                return .classSeparator
            }
            token = .colon
        default: return nil
        }
        bytes.advance()
        return token
    }

    /// `accTitle: text` or `accDescr: text` to the end of the line, or `accDescr { text }` over several lines; nil
    /// when the word is not followed by `:` (or `{`), and is a name.
    private mutating func readAccessibilityText() throws(MermaidDiagramReadError) -> EntityRelationshipToken? {
        let isTitle = bytes.hasCaseInsensitivePrefix("acctitle")
        guard isTitle || bytes.hasCaseInsensitivePrefix("accdescr") else { return nil }
        let keywordStart = bytes.position
        var lookahead = bytes
        lookahead.advance(by: 8)
        Self.skipWhitespaceAndLineBreaks(&lookahead)
        if lookahead.peek() == MermaidByte.colon {
            lookahead.advance()
            // As in Mermaid, the text after the colon may start on the next line.
            Self.skipWhitespaceAndLineBreaks(&lookahead)
            let text = DiagramLabelDecoder.decodingEntities(lookahead.readRestOfLine().trimmingCharacters(in: .whitespaces))
            bytes = lookahead
            return isTitle ? .accessibilityTitle(text) : .accessibilityDescription(text)
        }
        guard !isTitle, lookahead.peek() == MermaidByte.openingBrace else { return nil }
        lookahead.advance()
        let start = lookahead.position
        while let byte = lookahead.peek(), byte != MermaidByte.closingBrace { lookahead.advance() }
        guard !lookahead.isAtEnd else { throw .invalidSyntax(line: bytes.line(at: keywordStart), problem: .unclosedAccessibilityDescription) }
        let text = Self.descriptionLines(lookahead.text(from: start, to: lookahead.position))
        lookahead.advance()
        bytes = lookahead
        return .accessibilityDescription(text)
    }

    /// The text of `accDescr { … }` as Mermaid keeps it: trimmed, each line after the first without its indentation,
    /// blank lines dropped.
    private static func descriptionLines(_ text: String) -> String {
        let lines = text.trimmingCharacters(in: .whitespacesAndNewlines).components(separatedBy: "\n")
        let laterLines = lines.dropFirst().map { line in String(line.drop(while: \.isWhitespace)) }.filter { line in !line.isEmpty }
        return DiagramLabelDecoder.decodingEntities(([lines[0]] + laterLines).joined(separator: "\n"))
    }

    /// `direction` and whitespace, then `TB`, `BT`, `RL` or `LR` in any case; the rest of the line goes with it. Nil
    /// when the word is not followed by one of the four, and is a name.
    private mutating func readDirection() -> FlowchartDirection? {
        guard bytes.hasCaseInsensitivePrefix("direction") else { return nil }
        var lookahead = bytes
        lookahead.advance(by: 9)
        guard let separator = lookahead.peek(), Self.isWhitespace(separator) else { return nil }
        Self.skipWhitespaceAndLineBreaks(&lookahead)
        let direction: FlowchartDirection
        if lookahead.hasCaseInsensitivePrefix("tb") {
            direction = .topToBottom
        } else if lookahead.hasCaseInsensitivePrefix("bt") {
            direction = .bottomToTop
        } else if lookahead.hasCaseInsensitivePrefix("rl") {
            direction = .rightToLeft
        } else if lookahead.hasCaseInsensitivePrefix("lr") {
            direction = .leftToRight
        } else {
            return nil
        }
        lookahead.skipToEndOfLine()
        bytes = lookahead
        return direction
    }

    /// Text between quotation marks: a name when it is not empty and holds no `%`, `\`, line break, vertical tab or
    /// backspace, else text only a label may be. It may run over several lines.
    private mutating func readQuotedText() throws(MermaidDiagramReadError) -> EntityRelationshipToken {
        let opening = bytes.position
        bytes.advance()
        let start = bytes.position
        var isName = true
        while let byte = bytes.peek(), byte != MermaidByte.quotationMark {
            if Self.isByteNoQuotedNameHolds(byte) { isName = false }
            bytes.advance()
        }
        guard !bytes.isAtEnd else { throw .invalidSyntax(line: bytes.line(at: opening), problem: .unclosedQuotation) }
        let range = MermaidTextRange(start: start, end: bytes.position)
        bytes.advance()
        return isName && !range.isEmpty ? .name(range, form: .quoted) : .quotedText(range)
    }

    /// `1+` and `0+`; a number with a decimal part; `1` as exactly one where a name, a quotation or a line follows it,
    /// or alone as a name; else the digits, which name an entity.
    private mutating func readNumber(startingWith first: UInt8) -> EntityRelationshipToken {
        let next = bytes.peek(1)
        if next == Self.plus, first == Self.digitOne || first == Self.digitZero {
            bytes.advance(by: 2)
            return .cardinality(first == Self.digitOne ? .oneOrMore : .zeroOrMore)
        }
        var length = 1
        while let byte = bytes.peek(length), MermaidByte.isDigit(byte) { length += 1 }
        if bytes.peek(length) == MermaidByte.period, let decimal = bytes.peek(length + 1), MermaidByte.isDigit(decimal) {
            length += 2
            while let byte = bytes.peek(length), MermaidByte.isDigit(byte) { length += 1 }
        } else if first == Self.digitOne, oneIsACardinality() {
            bytes.advance()
            return .cardinality(.exactlyOne)
        } else if first == Self.digitOne, next.map(EntityRelationshipWords.isWordByte) != true {
            length = 1
        }
        let start = bytes.position
        bytes.advance(by: length)
        return .name(MermaidTextRange(start: start, end: bytes.position), form: .number)
    }

    /// Whether the `1` at the position is followed by whitespace and then a letter, a digit, `_` or a quotation mark,
    /// or by a line (`--`, `..`, `.-`, `-.`).
    private func oneIsACardinality() -> Bool {
        guard let next = bytes.peek(1) else { return false }
        if Self.isWhitespace(next) {
            var offset = 2
            while let byte = bytes.peek(offset), Self.isWhitespace(byte) { offset += 1 }
            guard let following = bytes.peek(offset) else { return false }
            return EntityRelationshipWords.isWordByte(following) || following == MermaidByte.quotationMark || following == Self.apostrophe
        }
        guard next == MermaidByte.hyphen || next == MermaidByte.period, let following = bytes.peek(2) else { return false }
        return following == MermaidByte.hyphen || following == MermaidByte.period
    }

    /// A byte of a bare name: a letter, a digit, `_`, `-`, `*`, `.`, or any byte of a character beyond ASCII.
    @inline(__always) static func isNameByte(_ byte: UInt8) -> Bool {
        EntityRelationshipWords.isWordByte(byte) || byte == MermaidByte.hyphen || byte == asterisk || byte == MermaidByte.period || byte >= 0x80
    }

    /// A space, a tab, a line break, a vertical tab, a form feed or a carriage return.
    @inline(__always) static func isWhitespace(_ byte: UInt8) -> Bool {
        byte == MermaidByte.space || (byte >= MermaidByte.tab && byte <= MermaidByte.carriageReturn)
    }

    private static func skipWhitespaceAndLineBreaks(_ bytes: inout GraphDiagramBytes) {
        while let byte = bytes.peek(), isWhitespace(byte) { bytes.advance() }
    }

    /// `%`, `\`, a carriage return, a line feed, a vertical tab or a backspace, which no quoted name holds.
    @inline(__always) private static func isByteNoQuotedNameHolds(_ byte: UInt8) -> Bool {
        byte == UInt8(ascii: "%") || byte == UInt8(ascii: "\\") || byte == MermaidByte.carriageReturn || byte == MermaidByte.newline || byte == 0x0B
            || byte == 0x08
    }

    private static let plus = UInt8(ascii: "+")
    private static let asterisk = UInt8(ascii: "*")
    private static let apostrophe = UInt8(ascii: "'")
    private static let digitZero = UInt8(ascii: "0")
    private static let digitOne = UInt8(ascii: "1")
}
