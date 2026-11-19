/**
 * File: CynefinLexer.swift
 * ------------------------
 * Layer: Core
 * Description: Reads a Cynefin framework's text into tokens as Mermaid's Langium lexer does with Pele's CYNEFIN_TOKENS:
 *              the terminals tried in order, the first that matches taken, white space, front matter, directives and
 *              comments hidden.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 19/11/2026
 */

/// Reads a Cynefin framework's tokens after its keyword: `-->`, `:`, the five domains' names, accessibility statements,
/// titles, strings and line breaks, in Pele's order; spaces and tabs, front matter, directives and `%%` comments are
/// hidden; any other text is an error where it starts.
enum CynefinLexer {
    static func tokens(after cursor: MermaidTextCursor, limits: MermaidDiagramLimits) throws(MermaidDiagramReadError) -> [(token: CynefinToken, start: Int)] {
        var terminals = PlaneMapTerminals(bytes: cursor.bytes)
        var position = try afterKeyword(cursor)
        var tokens: [(token: CynefinToken, start: Int)] = []
        while position < cursor.bytes.count {
            let start = position
            guard let (token, end) = match(at: start, terminals: &terminals) else {
                throw .invalidSyntax(line: PlaneMapByte.line(of: start, in: cursor.bytes), problem: .unexpectedText(PlaneMapByte.excerpt(at: start, in: cursor.bytes)))
            }
            position = end
            guard let token else { continue }
            tokens.append((token, start))
        }
        return tokens
    }

    /// After `cynefin-beta`: a colon, which the keyword may carry, or white space, a comment or the end.
    private static func afterKeyword(_ cursor: MermaidTextCursor) throws(MermaidDiagramReadError) -> Int {
        guard let next = cursor.peek() else { return cursor.position }
        if next == PlaneMapByte.colon { return cursor.position + 1 }
        guard PlaneMapByte.isSpace(next) || (next == PlaneMapByte.percent && cursor.peek(1) == PlaneMapByte.percent) else {
            throw .invalidSyntax(line: cursor.line, problem: .unexpectedText(cursor.excerpt()))
        }
        return cursor.position
    }

    /// The token at `start` and its end, nil for a hidden one; nil altogether where no terminal matches.
    private static func match(at start: Int, terminals: inout PlaneMapTerminals) -> (CynefinToken?, Int)? {
        guard let current = terminals.byte(start) else { return nil }
        switch current {
        case PlaneMapByte.space, PlaneMapByte.tab:
            var end = start + 1
            while let next = terminals.byte(end), PlaneMapByte.isBlank(next) { end += 1 }
            return (nil, end)
        case PlaneMapByte.hyphen:
            if terminals.hasPrefix("-->", at: start) { return (.arrow, start + 3) }
            return terminals.endOfFrontMatter(at: start).map { end in (nil, end) }
        case PlaneMapByte.colon: return (.colon, start + 1)
        case PlaneMapByte.lineFeed, PlaneMapByte.carriageReturn: return terminals.endOfLineBreak(at: start).map { end in (.newline, end) }
        case PlaneMapByte.percent:
            if let end = terminals.endOfDirective(at: start) { return (nil, end) }
            return terminals.endOfComment(at: start).map { end in (nil, end) }
        case PlaneMapByte.quotationMark, PlaneMapByte.apostrophe:
            return terminals.endOfString(at: start).map { end in (.string(PlaneMapTerminalValues.string(terminals.text(from: start, to: end))), end) }
        default:
            return matchWord(at: start, terminals: &terminals)
        }
    }

    /// A domain's name, an accessibility statement or a title.
    private static func matchWord(at start: Int, terminals: inout PlaneMapTerminals) -> (CynefinToken?, Int)? {
        for domain in domainsInPatternOrder where terminals.hasPrefix(domain.rawValue, at: start) {
            return (.domain(domain), start + domain.rawValue.utf8.count)
        }
        if let end = terminals.endOfAccessibilityDescription(at: start) {
            return (.accessibilityDescription(PlaneMapTerminalValues.accessibilityDescription(terminals.text(from: start, to: end))), end)
        }
        if let end = terminals.endOfAccessibilityTitle(at: start) {
            return (.accessibilityTitle(PlaneMapTerminalValues.accessibilityTitle(terminals.text(from: start, to: end))), end)
        }
        if let end = terminals.endOfTitle(at: start) {
            return (.title(PlaneMapTerminalValues.title(terminals.text(from: start, to: end))), end)
        }
        return nil
    }

    /// The domains in the order of Pele's `complex|complicated|clear|chaotic|confusion`.
    private static let domainsInPatternOrder: [CynefinDomain] = [.complex, .complicated, .clear, .chaotic, .confusion]
}
