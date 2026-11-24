/**
 * File: ReferenceFlowchartIdentifierSyntax.swift
 * ----------------------------------------------
 * Layer: Tests
 * Description: MermaidDiagrams 0.7.0's FlowchartIdentifierSyntax, frozen as the reference the flat reader is proven against
 *              (FlowchartModelEquivalenceTests): reads a flowchart identifier as Pele's grammar does: its idString, a run of the tokens its lexer makes that an identifier takes; and finds those tokens, and the ones a style takes, where Pele's lexer would.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 24/11/2026
 */

@testable import MermaidDiagrams

/// The tokens of Pele's flowchart lexer (flowchart/tokens.ts) that make identifiers (`ID`) and styles (`STYLE_PART`).
enum ReferenceFlowchartPieceToken {
    case number
    case nodeString
    case down
    case minus
    case defaultKeyword
    case comma
    case colon
    case ampersand
    case numberSign
    case asterisk
    case unicodeText
    case styleKeyword
    case space

    /// flowchart/parser.ts `ID`.
    var isIdentifierPiece: Bool {
        switch self {
        case .styleKeyword, .space: false
        default: true
        }
    }

    /// flowchart/parser.ts `STYLE_PART`: `NUM`, `NODE_STRING`, `COLON`, `SPACE`, `BRKT` and `STYLE`.
    var isStylePiece: Bool {
        switch self {
        case .number, .nodeString, .colon, .space, .numberSign, .styleKeyword: true
        default: false
        }
    }
}

/// A flowchart identifier as Pele reads it (flowchart/parser.ts `idString`): one or more tokens in a row of the kinds
/// an identifier takes, `NUM`, `NODE_STRING`, `DOWN`, `MINUS`, `DEFAULT`, `COMMA`, `COLON`, `AMP`, `BRKT`, `MULT` and
/// `UNICODE_TEXT`, each found as flowchart/lexer.ts finds the token at that place. So `a.graph.node`, `node-graph`,
/// `#node`, `:node`, `&`, `odd-` (before `>`) and `default.node` are identifiers; a keyword, a link (`-->`), a link's
/// identifier (`e1@`), a bracket, `:::`, a space or a character that is neither ASCII nor a letter ends one.
enum ReferenceFlowchartIdentifierSyntax {
    /// Reads an identifier at the cursor and moves past it, or returns nil and leaves the cursor when none starts there;
    /// `text` is the cursor's text as the lexer tests it.
    static func readIdentifier(_ cursor: inout ReferenceMermaidTextCursor, in text: ReferenceFlowchartLexerText) -> String? {
        let start = cursor.position
        let end = endOfIdentifier(in: text, from: start)
        guard end > start else { return nil }
        cursor.advance(by: end - start)
        return cursor.text(from: start, to: end)
    }

    /// Where the identifier from `start` ends; `start` when none starts there.
    static func endOfIdentifier(in text: ReferenceFlowchartLexerText, from start: Int) -> Int {
        var end = start
        while let (token, tokenEnd) = token(in: text, at: end), token.isIdentifierPiece { end = tokenEnd }
        return end
    }

    /// The token Pele's lexer reads at `position` in its initial state and where it ends, when it is one an identifier
    /// or a style takes; nil for any other token, or none.
    static func token(in text: ReferenceFlowchartLexerText, at position: Int) -> (ReferenceFlowchartPieceToken, Int)? {
        let bytes = text.bytes
        guard position < bytes.count else { return nil }
        let byte = bytes[position]
        // In the lexer's order: a quotation mark opens a string, `default` and `style` are tokens of their own before any
        // other check, then keywords, a direction statement anywhere on the line and a link's identifier.
        if byte == MermaidByte.quotationMark { return nil }
        if byte == UInt8(ascii: "d"), text.isKeyword(defaultWord, at: position) { return (.defaultKeyword, position + defaultWord.count) }
        if byte == UInt8(ascii: "s"), text.isKeyword(styleWord, at: position) { return (.styleKeyword, position + styleWord.count) }
        if text.startsKeywordOrAccessibility(at: position) || text.startsDirectionStatement(at: position)
            || text.startsLinkIdentifier(at: position) { return nil }
        if MermaidByte.isDigit(byte) {
            var end = position + 1
            while end < bytes.count, MermaidByte.isDigit(bytes[end]) { end += 1 }
            return (.number, end)
        }
        if let single = singleCharacterTokens[byte] {
            if byte == MermaidByte.colon, text.byte(at: position + 1) == MermaidByte.colon, text.byte(at: position + 2) == MermaidByte.colon { return nil }
            return (single, position + 1)
        }
        switch byte {
        case MermaidByte.letterX, MermaidByte.letterO, MermaidByte.period:
            return text.startsLink(at: position) ? nil : text.endOfNodeString(at: position).map { end in (.nodeString, end) }
        case MermaidByte.hyphen:
            if text.startsLink(at: position) { return nil }
            return text.endOfNodeString(at: position).map { end in (.nodeString, end) } ?? (.minus, position + 1)
        case UInt8(ascii: "\\"):
            return text.byte(at: position + 1) == MermaidByte.verticalBar ? nil : text.endOfNodeString(at: position).map { end in (.nodeString, end) }
        case UInt8(ascii: "v") where !ReferenceFlowchartLexerText.isWord(text.byte(at: position + 1)): return (.down, position + 1)
        default: break
        }
        if JavaScriptWhitespace.length(in: bytes, at: position) > 0 { return space(in: text, at: position) }
        if byte < 0x80 { return text.endOfNodeString(at: position).map { end in (.nodeString, end) } }
        // Beyond ASCII: one letter of the lexer's table is `UNICODE_TEXT`; anything else is no token Pele reads.
        guard let (scalar, length) = text.scalar(at: position), scalar.value <= 0xFFFF,
              AgentFlowCharacter.isUnicodeLetter(Int(scalar.value)) else { return nil }
        return (.unicodeText, position + length)
    }

    /// `SPACE` (`[^\S\n\r]+`), unless a link starts after the white space or it is a line break.
    private static func space(in text: ReferenceFlowchartLexerText, at position: Int) -> (ReferenceFlowchartPieceToken, Int)? {
        let afterSpaces = text.endOfSpaces(from: position)
        if afterSpaces < text.bytes.count, text.startsLink(at: afterSpaces) || text.hasText(invisibleLink, at: afterSpaces) { return nil }
        var end = position
        while end < text.bytes.count, text.bytes[end] != MermaidByte.newline, text.bytes[end] != MermaidByte.carriageReturn,
              case let length = JavaScriptWhitespace.length(in: text.bytes, at: end), length > 0 { end += length }
        return end > position ? (.space, end) : nil
    }

    private static let singleCharacterTokens: [UInt8: ReferenceFlowchartPieceToken] = [
        UInt8(ascii: "#"): .numberSign, MermaidByte.ampersand: .ampersand, MermaidByte.comma: .comma, UInt8(ascii: "*"): .asterisk,
        MermaidByte.colon: .colon,
    ]
    private static let defaultWord = Array("default".utf8)
    private static let styleWord = Array("style".utf8)
    private static let invisibleLink = Array("~~~".utf8)
}
