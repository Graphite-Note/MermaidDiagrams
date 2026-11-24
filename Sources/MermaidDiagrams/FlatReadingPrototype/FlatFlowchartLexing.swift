/**
 * File: FlatFlowchartLexing.swift
 * -------------------------------
 * Layer: Core (design prototype, not for merging as is)
 * Description: The tests Pele's flowchart lexer makes at a token's start, on a pointer to the text's bytes: the same
 *              tests as FlowchartLexerText and FlowchartIdentifierSyntax, with the far look-aheads (a direction statement
 *              later on the line, a link identifier's `@`) answered from lists made only when the text holds them.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 24/11/2026
 */

/// A reading failed or met what the prototype does not read: the caller reads the text again with the present reader,
/// which gives the diagram or the error with its line.
struct FlatReadingBailOut: Error {}

/// The text's bytes, with a 0 for any position outside them (a text holding a 0 byte is not read by the prototype).
struct FlatBytes {
    let base: UnsafePointer<UInt8>
    let count: Int
    /// Increasing positions, empty when the text holds no `direction`: where `direction`, white space and a direction start.
    let directionStatementStarts: UnsafeBufferPointer<Int>
    /// Increasing positions, empty when the text holds no such `@`: where an `@` neither `{` nor `"` follows stands.
    let linkIdentifierEnds: UnsafeBufferPointer<Int>

    @inline(__always) subscript(_ position: Int) -> UInt8 {
        position >= 0 && position < count ? base[position] : 0
    }

    var buffer: UnsafeBufferPointer<UInt8> { UnsafeBufferPointer(start: base, count: count) }

    @inline(__always) func hasText(_ literal: StaticString, at position: Int) -> Bool {
        let length = literal.utf8CodeUnitCount
        guard position >= 0, position + length <= count else { return false }
        let literalBytes = literal.utf8Start
        for offset in 0..<length where base[position + offset] != literalBytes[offset] { return false }
        return true
    }

    @inline(__always) static func isWord(_ byte: UInt8) -> Bool {
        (byte >= 0x61 && byte <= 0x7A) || (byte >= 0x41 && byte <= 0x5A) || (byte >= 0x30 && byte <= 0x39) || byte == 0x5F
    }

    @inline(__always) func isKeyword(_ word: StaticString, at position: Int) -> Bool {
        hasText(word, at: position) && !Self.isWord(self[position + word.utf8CodeUnitCount])
    }

    /// JavaScript's white space at `position`: its length in bytes, 0 for none.
    @inline(__always) func whitespaceLength(at position: Int) -> Int {
        let byte = self[position]
        if byte == 0x20 || (byte >= 0x09 && byte <= 0x0D) { return 1 }
        guard byte >= 0xC2 else { return 0 }
        return JavaScriptWhitespace.length(in: buffer, at: position)
    }

    func endOfSpaces(from position: Int) -> Int {
        var end = position
        while case let length = whitespaceLength(at: end), length > 0 { end += length }
        return end
    }

    private func isWordAndSpace(_ word: StaticString, at position: Int) -> Bool {
        hasText(word, at: position) && endOfSpaces(from: position + word.utf8CodeUnitCount) > position + word.utf8CodeUnitCount
    }

    /// FlowchartLexerText.startsKeywordOrAccessibility.
    func startsKeywordOrAccessibility(at position: Int) -> Bool {
        switch self[position] {
        case 0x61: // a
            if hasText("accTitle", at: position) { return self[endOfSpaces(from: position + 8)] == MermaidByte.colon }
            if hasText("accDescr", at: position) {
                let after = self[endOfSpaces(from: position + 8)]
                return after == MermaidByte.colon || after == MermaidByte.openingBrace
            }
            return false
        case MermaidByte.atSign: return self[position + 1] == MermaidByte.openingBrace
        case 0x63: // c
            return isWordAndSpace("call", at: position) || isKeyword("classDef", at: position) || isKeyword("class", at: position)
                || isWordAndSpace("click", at: position)
        case 0x73: return isKeyword("style", at: position) || isKeyword("swimlane-beta", at: position) || isKeyword("subgraph", at: position)
        case 0x6C: return isKeyword("linkStyle", at: position)
        case 0x69: return isKeyword("interpolate", at: position)
        case 0x68: return hasText("href", at: position) && whitespaceLength(at: position + 4) > 0
        case 0x66: return isKeyword("flowchart-elk", at: position) || isKeyword("flowchart", at: position)
        case 0x67: return isKeyword("graph", at: position)
        case 0x65: return isKeyword("end", at: position)
        case MermaidByte.underscore:
            return isKeyword("_self", at: position) || isKeyword("_blank", at: position) || isKeyword("_parent", at: position)
                || isKeyword("_top", at: position)
        default: return false
        }
    }

    @inline(__always) func isLineTerminator(at position: Int) -> Bool {
        let byte = self[position]
        if byte == MermaidByte.newline || byte == MermaidByte.carriageReturn { return true }
        return byte == 0xE2 && self[position + 1] == 0x80 && (self[position + 2] == 0xA8 || self[position + 2] == 0xA9)
    }

    /// Whether a direction statement starts from `position` up to its line's end.
    @inline(__always) func startsDirectionStatement(at position: Int) -> Bool {
        guard !directionStatementStarts.isEmpty else { return false }
        guard let start = directionStatementStarts.first(where: { start in start >= position }) else { return false }
        for index in position..<start where isLineTerminator(at: index) { return false }
        return true
    }

    /// FlowchartLexerText.endOfLinkIdentifier: past the last `@` of the word from `position`.
    @inline(__always) func endOfLinkIdentifier(at position: Int) -> Int? {
        guard !linkIdentifierEnds.isEmpty else { return nil }
        guard self[position] != MermaidByte.quotationMark, position < count, whitespaceLength(at: position) == 0 else { return nil }
        var wordEnd = position
        while wordEnd < count, self[wordEnd] != MermaidByte.quotationMark, whitespaceLength(at: wordEnd) == 0 { wordEnd += 1 }
        guard let last = linkIdentifierEnds.last(where: { end in end < wordEnd }), last > position else { return nil }
        return last + 1
    }

    /// FlowchartLexerText.startsLink.
    func startsLink(at position: Int) -> Bool {
        var start = position
        let mark = self[start]
        if mark == MermaidByte.letterX || mark == MermaidByte.letterO || mark == MermaidByte.lessThan { start += 1 }
        switch self[start] {
        case MermaidByte.hyphen: return run(of: MermaidByte.hyphen, at: start) >= 2 || isDottedLink(markedAt: position) || self[start + 1] == MermaidByte.period
        case MermaidByte.equals: return run(of: MermaidByte.equals, at: start) >= 2
        case MermaidByte.period: return isDottedLink(markedAt: position)
        default: return false
        }
    }

    private func isDottedLink(markedAt position: Int) -> Bool {
        let mark = self[position]
        if mark == MermaidByte.letterX || mark == MermaidByte.letterO || mark == MermaidByte.lessThan, isDotted(from: position + 1) { return true }
        return isDotted(from: position)
    }

    private func isDotted(from start: Int) -> Bool {
        var index = start
        if self[index] == MermaidByte.hyphen { index += 1 }
        let periods = run(of: MermaidByte.period, at: index)
        return periods > 0 && self[index + periods] == MermaidByte.hyphen
    }

    @inline(__always) func run(of sign: UInt8, at position: Int) -> Int {
        var count = 0
        while self[position + count] == sign { count += 1 }
        return count
    }

    /// FlowchartLexerText.endOfNodeString.
    @inline(__always) func endOfNodeString(at position: Int) -> Int? {
        var end = position
        while end < count {
            let byte = base[end]
            if byte < 0x80, Self.isNodeStringByte(byte) {
                end += 1
            } else if byte == MermaidByte.hyphen, case let next = end + 1 < count ? base[end + 1] : MermaidByte.newline,
                      next != MermaidByte.greaterThan, next != MermaidByte.hyphen, next != MermaidByte.period {
                end += 1
            } else {
                break
            }
        }
        return end > position ? end : nil
    }

    /// `A-Za-z0-9!"#$%&'*+.`?\_/` as two masks.
    @inline(__always) static func isNodeStringByte(_ byte: UInt8) -> Bool {
        byte < 64 ? (lowNodeStringBytes &>> UInt64(byte)) & 1 != 0 : byte < 128 && (highNodeStringBytes &>> UInt64(byte - 64)) & 1 != 0
    }

    private static let lowNodeStringBytes: UInt64 = Array("0123456789!\"#$%&'*+./?".utf8).reduce(0) { mask, byte in mask | 1 &<< UInt64(byte) }
    private static let highNodeStringBytes: UInt64 = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz`\\_".utf8).reduce(0) { mask, byte in
        mask | 1 &<< UInt64(byte - 64)
    }

    /// FlowchartIdentifierSyntax.endOfIdentifier: past the run of the lexer's tokens an identifier takes.
    func endOfIdentifier(from start: Int) -> Int {
        var end = start
        while let (token, tokenEnd) = token(at: end), token.isIdentifierPiece { end = tokenEnd }
        return end
    }

    /// FlowchartIdentifierSyntax.token: the token Pele's lexer makes at `position` of those an identifier or a style
    /// takes, and its end; nil for any other token.
    func token(at position: Int) -> (FlowchartPieceToken, Int)? {
        guard position < count else { return nil }
        let byte = base[position]
        if byte == MermaidByte.quotationMark { return nil }
        if byte == 0x64, isKeyword("default", at: position) { return (.defaultKeyword, position + 7) }
        if byte == 0x73, isKeyword("style", at: position) { return (.styleKeyword, position + 5) }
        if startsKeywordOrAccessibility(at: position) || startsDirectionStatement(at: position) || endOfLinkIdentifier(at: position) != nil { return nil }
        if byte >= 0x30, byte <= 0x39 {
            var end = position + 1
            while end < count, base[end] >= 0x30, base[end] <= 0x39 { end += 1 }
            return (.number, end)
        }
        switch byte {
        case 0x23: return (.numberSign, position + 1)
        case MermaidByte.ampersand: return (.ampersand, position + 1)
        case MermaidByte.comma: return (.comma, position + 1)
        case 0x2A: return (.asterisk, position + 1)
        case MermaidByte.colon: return self[position + 1] == MermaidByte.colon && self[position + 2] == MermaidByte.colon ? nil : (.colon, position + 1)
        case MermaidByte.letterX, MermaidByte.letterO, MermaidByte.period:
            return startsLink(at: position) ? nil : endOfNodeString(at: position).map { end in (.nodeString, end) }
        case MermaidByte.hyphen:
            if startsLink(at: position) { return nil }
            return endOfNodeString(at: position).map { end in (.nodeString, end) } ?? (.minus, position + 1)
        case 0x5C: return self[position + 1] == MermaidByte.verticalBar ? nil : endOfNodeString(at: position).map { end in (.nodeString, end) }
        case 0x76 where !Self.isWord(self[position + 1]): return (.down, position + 1)
        default: break
        }
        if whitespaceLength(at: position) > 0 { return space(at: position) }
        if byte < 0x80 { return endOfNodeString(at: position).map { end in (.nodeString, end) } }
        var iterator = buffer[position...].makeIterator()
        var decoder = UTF8()
        guard case .scalarValue(let scalar) = decoder.decode(&iterator), scalar.value <= 0xFFFF,
              AgentFlowCharacter.isUnicodeLetter(Int(scalar.value)) else { return nil }
        return (.unicodeText, position + UTF8.width(scalar))
    }

    private func space(at position: Int) -> (FlowchartPieceToken, Int)? {
        let afterSpaces = endOfSpaces(from: position)
        if afterSpaces < count, startsLink(at: afterSpaces) || hasText("~~~", at: afterSpaces) { return nil }
        var end = position
        while end < count, base[end] != MermaidByte.newline, base[end] != MermaidByte.carriageReturn, case let length = whitespaceLength(at: end),
              length > 0 { end += length }
        return end > position ? (.space, end) : nil
    }

    // MARK: Styles

    /// FlowchartStyleGrammar.isReadByPele, on these bytes.
    func isStyleReadByPele(keywordIsClass: Bool, keywordIsLinkStyle: Bool, from start: Int, to end: Int) -> Bool {
        var position = start
        guard skipSpaceToken(at: &position, before: end) else { return false }
        if keywordIsLinkStyle { return isLinkStyleReadByPele(from: position, to: end) }
        let identifierEnd = endOfIdentifier(from: position)
        guard identifierEnd > position, identifierEnd <= end else { return false }
        position = identifierEnd
        guard skipSpaceToken(at: &position, before: end) else { return false }
        if keywordIsClass {
            let classEnd = endOfIdentifier(from: position)
            return classEnd > position && classEnd == end
        }
        return endOfStyles(from: position, before: end) == end
    }

    private func isLinkStyleReadByPele(from start: Int, to end: Int) -> Bool {
        var position = start
        if let (token, tokenEnd) = token(at: position), token == .defaultKeyword {
            position = tokenEnd
        } else {
            while true {
                guard let (token, tokenEnd) = token(at: position), token == .number else { return false }
                position = tokenEnd
                guard position < end, base[position] == MermaidByte.comma else { break }
                position += 1
            }
        }
        guard skipSpaceToken(at: &position, before: end) else { return false }
        guard isKeyword("interpolate", at: position) else { return endOfStyles(from: position, before: end) == end }
        position += 11
        guard skipSpaceToken(at: &position, before: end) else { return false }
        let nameStart = position
        while position < end, let (token, tokenEnd) = token(at: position), token.isIdentifierPiece, token != .defaultKeyword, tokenEnd <= end {
            position = tokenEnd
        }
        guard position > nameStart else { return false }
        if position == end { return true }
        guard skipSpaceToken(at: &position, before: end) else { return false }
        return endOfStyles(from: position, before: end) == end
    }

    private func skipSpaceToken(at position: inout Int, before end: Int) -> Bool {
        guard let (token, tokenEnd) = token(at: position), token == .space, tokenEnd <= end else { return false }
        position = tokenEnd
        return true
    }

    private func endOfStyles(from start: Int, before end: Int) -> Int? {
        var position = start
        while true {
            let styleStart = position
            while position < end, let (token, tokenEnd) = token(at: position), token.isStylePiece, tokenEnd <= end { position = tokenEnd }
            guard position > styleStart else { return nil }
            guard position < end, base[position] == MermaidByte.comma else { return position }
            position += 1
        }
    }
}
