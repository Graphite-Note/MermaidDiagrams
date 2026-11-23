/**
 * File: FlowchartIdentifierSyntax.swift
 * -------------------------------------
 * Layer: Core
 * Description: Reads a flowchart identifier as Pele's grammar does: its idString, a run of the tokens its lexer makes
 *              that an identifier takes.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 23/11/2026
 */

/// A flowchart identifier as Pele reads it (flowchart/parser.ts `idString`): one or more tokens in a row of the kinds
/// an identifier takes, `NUM`, `NODE_STRING`, `DOWN`, `MINUS`, `DEFAULT`, `COMMA`, `COLON`, `AMP`, `BRKT`, `MULT` and
/// `UNICODE_TEXT`, each found as flowchart/lexer.ts finds the token at that place. So `a.graph.node`, `node-graph`,
/// `#node`, `:node`, `&`, `odd-` (before `>`) and `default.node` are identifiers; a keyword, a link (`-->`), a link's
/// identifier (`e1@`), a bracket, `:::`, a space or a character that is neither ASCII nor a letter ends one.
enum FlowchartIdentifierSyntax {
    /// Reads an identifier at the cursor and moves past it, or returns nil and leaves the cursor when none starts there.
    static func readIdentifier(_ cursor: inout MermaidTextCursor) -> String? {
        let start = cursor.position
        var end = start
        while let pieceEnd = endOfIdentifierPiece(in: cursor.bytes, at: end) { end = pieceEnd }
        guard end > start else { return nil }
        cursor.advance(by: end - start)
        return cursor.text(from: start, to: end)
    }

    /// Where the token at `position` ends when it is one an identifier takes; nil for any other token, or none.
    static func endOfIdentifierPiece(in bytes: [UInt8], at position: Int) -> Int? {
        guard position < bytes.count else { return nil }
        let text = FlowchartLexerText(bytes: bytes)
        let byte = bytes[position]
        // In the lexer's order: a quotation mark opens a string, `default` is a token of its own before any other
        // check, then keywords, a direction statement anywhere on the line and a link's identifier end the identifier.
        if byte == MermaidByte.quotationMark { return nil }
        if byte == UInt8(ascii: "d"), text.isKeyword(defaultWord, at: position) { return position + defaultWord.count }
        if text.startsKeywordOrAccessibility(at: position) || text.startsDirectionStatement(at: position)
            || text.startsLinkIdentifier(at: position) { return nil }
        if MermaidByte.isDigit(byte) {
            var end = position + 1
            while end < bytes.count, MermaidByte.isDigit(bytes[end]) { end += 1 }
            return end
        }
        switch byte {
        case UInt8(ascii: "#"), MermaidByte.ampersand, MermaidByte.comma, UInt8(ascii: "*"): return position + 1
        case MermaidByte.colon: return text.byte(at: position + 1) == MermaidByte.colon && text.byte(at: position + 2) == MermaidByte.colon ? nil : position + 1
        case MermaidByte.letterX, MermaidByte.letterO, MermaidByte.period:
            return text.startsLink(at: position) ? nil : text.endOfNodeString(at: position)
        case MermaidByte.hyphen: return text.startsLink(at: position) ? nil : text.endOfNodeString(at: position) ?? position + 1
        case UInt8(ascii: "\\"): return text.byte(at: position + 1) == MermaidByte.verticalBar ? nil : text.endOfNodeString(at: position)
        case UInt8(ascii: "v"): return FlowchartLexerText.isWord(text.byte(at: position + 1)) ? text.endOfNodeString(at: position) : position + 1
        default: break
        }
        if byte < 0x80 { return JavaScriptWhitespace.length(in: bytes, at: position) > 0 ? nil : text.endOfNodeString(at: position) }
        // Beyond ASCII: one letter of the lexer's table is `UNICODE_TEXT`; anything else is no token Pele reads.
        guard let (scalar, length) = text.scalar(at: position), scalar.value <= 0xFFFF,
              AgentFlowCharacter.isUnicodeLetter(Int(scalar.value)) else { return nil }
        return position + length
    }

    private static let defaultWord = Array("default".utf8)
}
