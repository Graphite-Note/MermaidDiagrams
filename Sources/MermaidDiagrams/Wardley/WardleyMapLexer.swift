/**
 * File: WardleyMapLexer.swift
 * ---------------------------
 * Layer: Core
 * Description: Reads a Wardley map's text into tokens as Mermaid's Langium lexer does with Pele's WARDLEY_TOKENS: the
 *              terminals tried in order, the first that matches taken, `-` giving way to a longer arrow or front matter.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 19/11/2026
 */

/// The kinds of a Wardley map's tokens.
enum WardleyMapTokenKind: Equatable {
    case openingBracket, comma, closingBracket, atSign, slash, openingParenthesis, closingParenthesis, minus, openingBrace, closingBrace
    /// Digits, a point and digits.
    case decimal
    /// `->`.
    case arrow
    /// `+<>`, `+>` or `+<`.
    case linkPort
    /// `-->`, `-.->`, `>`, or `+'label'` and `<>`, `<` or `>`.
    case linkArrow
    /// `;` and the rest of the line.
    case linkLabel
    /// `build`, `buy`, `outsource` or `market`.
    case sourcing
    /// A second `wardley-beta`, which no statement takes.
    case wardleyKeyword
    case size, evolution, anchor, component, label, inertia, evolve, pipeline, note, annotations, annotation, accelerator, deaccelerator
    /// A name of words separated by spaces.
    case name
    case accessibilityDescription, accessibilityTitle, title
    /// A whole number without a point after it.
    case wholeNumber
    case string
    /// Word characters and hyphens.
    case identifier
    case newline
}

/// A token: its kind and where it lies in the diagram's bytes.
struct WardleyMapToken {
    let kind: WardleyMapTokenKind
    let start: Int
    let end: Int
}

/// Reads a Wardley map's tokens after its `wardley-beta` keyword, every terminal of Pele's table in its order; spaces and
/// tabs, front matter, directives and `%%` comments are hidden, and any other text is an error where it starts.
enum WardleyMapLexer {
    static func tokens(after cursor: MermaidTextCursor) throws(MermaidDiagramReadError) -> [WardleyMapToken] {
        var terminals = PlaneMapTerminals(bytes: cursor.bytes)
        var position = cursor.position
        var tokens: [WardleyMapToken] = []
        while position < cursor.bytes.count {
            let start = position
            guard let (kind, end) = match(at: start, terminals: &terminals) else {
                throw .invalidSyntax(line: PlaneMapByte.line(of: start, in: cursor.bytes), problem: .unexpectedText(PlaneMapByte.excerpt(at: start, in: cursor.bytes)))
            }
            position = end
            if let kind { tokens.append(WardleyMapToken(kind: kind, start: start, end: end)) }
        }
        return tokens
    }

    /// The token at `start` and its end, nil for a hidden one; nil altogether where no terminal matches.
    private static func match(at start: Int, terminals: inout PlaneMapTerminals) -> (WardleyMapTokenKind?, Int)? {
        guard let current = terminals.byte(start) else { return nil }
        if let kind = punctuation[current] { return (kind, start + 1) }
        switch current {
        case PlaneMapByte.hyphen: return matchHyphen(at: start, terminals: &terminals)
        case PlaneMapByte.space, PlaneMapByte.tab: return (nil, WardleyMapWords.endOfBlanks(in: terminals, from: start))
        case PlaneMapByte.plus, PlaneMapByte.greaterThan: return WardleyMapWords.endOfLink(in: terminals, at: start)
        case PlaneMapByte.semicolon:
            let end = terminals.lineEnd(from: start + 1)
            return end > start + 1 ? (.linkLabel, end) : nil
        case PlaneMapByte.quotationMark, PlaneMapByte.apostrophe: return terminals.endOfString(at: start).map { end in (.string, end) }
        case PlaneMapByte.lineFeed, PlaneMapByte.carriageReturn: return terminals.endOfLineBreak(at: start).map { end in (.newline, end) }
        case PlaneMapByte.percent:
            if let end = terminals.endOfDirective(at: start) { return (nil, end) }
            return terminals.endOfComment(at: start).map { end in (nil, end) }
        default:
            if PlaneMapByte.isDigit(current) { return WardleyMapWords.matchNumber(in: terminals, at: start) }
            return WardleyMapWords.matchWord(in: &terminals, at: start)
        }
    }

    /// `-`, unless `->`, `-->`, `-.->` or front matter is longer.
    private static func matchHyphen(at start: Int, terminals: inout PlaneMapTerminals) -> (WardleyMapTokenKind?, Int)? {
        if terminals.byte(start + 1) == PlaneMapByte.greaterThan { return (.arrow, start + 2) }
        if terminals.hasPrefix("-->", at: start) { return (.linkArrow, start + 3) }
        if terminals.hasPrefix("-.->", at: start) { return (.linkArrow, start + 4) }
        if let end = terminals.endOfFrontMatter(at: start) { return (nil, end) }
        return (.minus, start + 1)
    }

    private static let punctuation: [UInt8: WardleyMapTokenKind] = [
        PlaneMapByte.openingBracket: .openingBracket, PlaneMapByte.comma: .comma, PlaneMapByte.closingBracket: .closingBracket, PlaneMapByte.atSign: .atSign,
        PlaneMapByte.slash: .slash, PlaneMapByte.openingParenthesis: .openingParenthesis, PlaneMapByte.closingParenthesis: .closingParenthesis,
        PlaneMapByte.openingBrace: .openingBrace, PlaneMapByte.closingBrace: .closingBrace,
    ]
}
