/**
 * File: FlowchartIdentifierSyntax.swift
 * -------------------------------------
 * Layer: Core
 * Description: Reads a flowchart identifier as Pele's grammar does: its idString, a run of the tokens its lexer makes
 *              that an identifier takes; and finds those tokens, and the ones a style takes, where Pele's lexer would.
 *
 * Authors: Bahey Shalash
 * Version: 0.3
 * Date: 24/11/2026
 */

/// The tokens of Pele's flowchart lexer (flowchart/tokens.ts) that make identifiers (`ID`) and styles (`STYLE_PART`).
enum FlowchartPieceToken {
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
enum FlowchartIdentifierSyntax {
    /// Where the identifier from `start` ends; `start` when none starts there.
    static func endOfIdentifier(in bytes: FlowchartBytes, from start: Int) -> Int {
        var end = start
        while let (token, tokenEnd) = token(in: bytes, at: end), token.isIdentifierPiece { end = tokenEnd }
        return end
    }

    /// The token Pele's lexer reads at `position` in its initial state and where it ends, when it is one an identifier
    /// or a style takes; nil for any other token, or none.
    static func token(in bytes: FlowchartBytes, at position: Int) -> (FlowchartPieceToken, Int)? {
        guard position < bytes.count else { return nil }
        let byte = bytes.base[position]
        // In the lexer's order: a quotation mark opens a string, `default` and `style` are tokens of their own before any
        // other check, then keywords, a direction statement anywhere on the line and a link's identifier.
        if byte == MermaidByte.quotationMark { return nil }
        if byte == UInt8(ascii: "d"), bytes.isKeyword("default", at: position) { return (.defaultKeyword, position + 7) }
        if byte == UInt8(ascii: "s"), bytes.isKeyword("style", at: position) { return (.styleKeyword, position + 5) }
        if bytes.startsKeywordOrAccessibility(at: position) || bytes.startsDirectionStatement(at: position)
            || bytes.endOfLinkIdentifier(at: position) != nil { return nil }
        if MermaidByte.isDigit(byte) {
            var end = position + 1
            while end < bytes.count, MermaidByte.isDigit(bytes.base[end]) { end += 1 }
            return (.number, end)
        }
        switch byte {
        case UInt8(ascii: "#"): return (.numberSign, position + 1)
        case MermaidByte.ampersand: return (.ampersand, position + 1)
        case MermaidByte.comma: return (.comma, position + 1)
        case UInt8(ascii: "*"): return (.asterisk, position + 1)
        case MermaidByte.colon:
            return bytes[position + 1] == MermaidByte.colon && bytes[position + 2] == MermaidByte.colon ? nil : (.colon, position + 1)
        case MermaidByte.letterX, MermaidByte.letterO, MermaidByte.period:
            return bytes.startsLink(at: position) ? nil : bytes.endOfNodeString(at: position).map { end in (.nodeString, end) }
        case MermaidByte.hyphen:
            if bytes.startsLink(at: position) { return nil }
            return bytes.endOfNodeString(at: position).map { end in (.nodeString, end) } ?? (.minus, position + 1)
        case UInt8(ascii: "\\"):
            return bytes[position + 1] == MermaidByte.verticalBar ? nil : bytes.endOfNodeString(at: position).map { end in (.nodeString, end) }
        case UInt8(ascii: "v") where !FlowchartBytes.isWord(bytes[position + 1]): return (.down, position + 1)
        default: break
        }
        if bytes.whitespaceLength(at: position) > 0 { return space(in: bytes, at: position) }
        if byte < 0x80 { return bytes.endOfNodeString(at: position).map { end in (.nodeString, end) } }
        // Beyond ASCII: one letter of the lexer's table is `UNICODE_TEXT`; anything else is no token Pele reads.
        guard let (scalar, length) = bytes.scalar(at: position), scalar.value <= 0xFFFF,
              AgentFlowCharacter.isUnicodeLetter(Int(scalar.value)) else { return nil }
        return (.unicodeText, position + length)
    }

    /// `SPACE` (`[^\S\n\r]+`), unless a link starts after the white space or it is a line break.
    private static func space(in bytes: FlowchartBytes, at position: Int) -> (FlowchartPieceToken, Int)? {
        let afterSpaces = bytes.endOfSpaces(from: position)
        if afterSpaces < bytes.count, bytes.startsLink(at: afterSpaces) || bytes.hasText("~~~", at: afterSpaces) { return nil }
        var end = position
        while end < bytes.count, bytes.base[end] != MermaidByte.newline, bytes.base[end] != MermaidByte.carriageReturn,
              case let length = bytes.whitespaceLength(at: end), length > 0 { end += length }
        return end > position ? (.space, end) : nil
    }
}
