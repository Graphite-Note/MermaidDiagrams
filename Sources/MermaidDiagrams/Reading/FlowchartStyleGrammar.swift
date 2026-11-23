/**
 * File: FlowchartStyleGrammar.swift
 * ---------------------------------
 * Layer: Core
 * Description: Whether a flowchart's `style`, `classDef`, `class` or `linkStyle` statement is written as Pele's parser reads it,
 *              token by token as its lexer makes them.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 23/11/2026
 */

/// The grammar of flowchart/parser.ts for the statements that style nodes and edges: `style` and `classDef` take a
/// space, an identifier, a space and styles (`stylesOpt`: runs of `STYLE_PART` tokens, numbers, node strings, colons,
/// spaces, `#` and the word `style`, separated by commas); `class` takes a space, an identifier, a space and an
/// identifier; `linkStyle` takes edge numbers or `default`, then styles or an `interpolate` curve.
/// Anything else before the statement's end, a parenthesis (`fill:rgb(1,2,3)`), a link or a bracket, is refused there,
/// as Pele refuses it.
enum FlowchartStyleGrammar {
    /// Whether the statement after `keyword`, from `start` to `end` (a line break, a semicolon or the text's end), is
    /// one Pele reads; other statements are not checked.
    static func isReadByPele(keyword: String, in bytes: [UInt8], from start: Int, to end: Int) -> Bool {
        guard keyword == "style" || keyword == "classDef" || keyword == "class" || keyword == "linkStyle" else { return true }
        var position = start
        guard skipSpace(in: bytes, at: &position, before: end) else { return false }
        if keyword == "linkStyle" { return isLinkStyleReadByPele(in: bytes, from: position, to: end) }
        let identifierEnd = FlowchartIdentifierSyntax.endOfIdentifier(in: bytes, from: position)
        guard identifierEnd > position, identifierEnd <= end else { return false }
        position = identifierEnd
        guard skipSpace(in: bytes, at: &position, before: end) else { return false }
        if keyword == "class" {
            let classEnd = FlowchartIdentifierSyntax.endOfIdentifier(in: bytes, from: position)
            return classEnd > position && classEnd == end
        }
        return endOfStyles(in: bytes, from: position, before: end) == end
    }

    /// `linkStyle`'s rest after its first space (`linkStyleStatement`): `default` or numbers separated by commas, a space,
    /// then styles, or `interpolate`, a space, a curve's name (`alphaNum`) and, after a space, styles.
    private static func isLinkStyleReadByPele(in bytes: [UInt8], from start: Int, to end: Int) -> Bool {
        var position = start
        if let (token, tokenEnd) = FlowchartIdentifierSyntax.token(in: bytes, at: position), token == .defaultKeyword {
            position = tokenEnd
        } else {
            while true {
                guard let (token, tokenEnd) = FlowchartIdentifierSyntax.token(in: bytes, at: position), token == .number else { return false }
                position = tokenEnd
                guard position < end, bytes[position] == MermaidByte.comma else { break }
                position += 1
            }
        }
        guard skipSpace(in: bytes, at: &position, before: end) else { return false }
        let text = FlowchartLexerText(bytes: bytes)
        guard text.isKeyword(interpolate, at: position) else { return endOfStyles(in: bytes, from: position, before: end) == end }
        position += interpolate.count
        guard skipSpace(in: bytes, at: &position, before: end) else { return false }
        let nameStart = position
        while position < end, let (token, tokenEnd) = FlowchartIdentifierSyntax.token(in: bytes, at: position), token.isIdentifierPiece,
              token != .defaultKeyword, tokenEnd <= end { position = tokenEnd }
        guard position > nameStart else { return false }
        if position == end { return true }
        guard skipSpace(in: bytes, at: &position, before: end) else { return false }
        return endOfStyles(in: bytes, from: position, before: end) == end
    }

    private static let interpolate = Array("interpolate".utf8)

    /// One `SPACE` token at `position`, which the position moves past.
    private static func skipSpace(in bytes: [UInt8], at position: inout Int, before end: Int) -> Bool {
        guard let (token, tokenEnd) = FlowchartIdentifierSyntax.token(in: bytes, at: position), token == .space, tokenEnd <= end else { return false }
        position = tokenEnd
        return true
    }

    /// Where `stylesOpt` from `start` ends: styles of one or more pieces each, separated by commas; nil when a style
    /// has no piece (`fill:red,` before the statement's end).
    private static func endOfStyles(in bytes: [UInt8], from start: Int, before end: Int) -> Int? {
        var position = start
        while true {
            let styleStart = position
            while position < end, let (token, tokenEnd) = FlowchartIdentifierSyntax.token(in: bytes, at: position), token.isStylePiece,
                  tokenEnd <= end { position = tokenEnd }
            guard position > styleStart else { return nil }
            guard position < end, bytes[position] == MermaidByte.comma else { return position }
            position += 1
        }
    }
}
