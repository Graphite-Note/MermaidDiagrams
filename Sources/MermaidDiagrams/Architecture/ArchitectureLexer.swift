/**
 * File: ArchitectureLexer.swift
 * -----------------------------
 * Layer: Core
 * Description: Reads an architecture diagram's text into tokens as Mermaid's Langium lexer does with Pele's
 *              ARCHITECTURE_TOKENS: the terminals tried in order, the first that matches taken unless an identifier
 *              matches more, white space, front matter, directives and comments hidden.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 19/11/2026
 */

/// A token of an architecture diagram, Pele's `T`.
enum ArchitectureToken: Equatable {
    case junction, service, column, group, align, row
    /// `in`, before a parent group.
    case inGroup
    /// `--`.
    case dashes
    case colon
    /// `-`, around an edge's title.
    case dash
    case side(ArchitectureSide)
    /// `{group}`.
    case groupModifier
    /// `<` or `>`.
    case into
    case accessibilityDescription(String)
    case accessibilityTitle(String)
    case title(String)
    case string(String)
    case identifier(String)
    case newline
    /// `(name)`: the name.
    case icon(String)
    /// `[text]`: the text as written, brackets included.
    case label(String)
}

/// Reads an architecture diagram's tokens after its keyword, in Pele's order: the keywords (an identifier that reads
/// longer is an identifier), `--`, `in`, `:`, `-`, the sides (before identifiers, so `Bob` is the side `B` and `ob`, as
/// in Mermaid), `{group}`, `<` and `>`, the accessibility statements, `title`, strings, identifiers, line breaks, then
/// an icon in parentheses and a title in brackets. Text no terminal reads is an error where it starts.
enum ArchitectureLexer {
    static func tokens(after cursor: MermaidTextCursor) throws(MermaidDiagramReadError) -> [(token: ArchitectureToken, start: Int, end: Int)] {
        var terminals = PlaneMapTerminals(bytes: cursor.bytes)
        var position = cursor.position
        var tokens: [(token: ArchitectureToken, start: Int, end: Int)] = []
        while position < cursor.bytes.count {
            let start = position
            guard let (token, end) = match(at: start, terminals: &terminals) else {
                throw .invalidSyntax(line: PlaneMapByte.line(of: start, in: cursor.bytes), problem: .unexpectedText(PlaneMapByte.excerpt(at: start, in: cursor.bytes)))
            }
            position = end
            guard let token else { continue }
            tokens.append((token, start, end))
        }
        return tokens
    }

    /// The token at `start` and its end, nil for a hidden one; nil altogether where nothing matches.
    private static func match(at start: Int, terminals: inout PlaneMapTerminals) -> (ArchitectureToken?, Int)? {
        guard let current = terminals.byte(start) else { return nil }
        switch current {
        case PlaneMapByte.space, PlaneMapByte.tab:
            var end = start + 1
            while let next = terminals.byte(end), PlaneMapByte.isBlank(next) { end += 1 }
            return (nil, end)
        case PlaneMapByte.hyphen:
            if let end = terminals.endOfFrontMatter(at: start) { return (nil, end) }
            return terminals.hasPrefix("--", at: start) ? (.dashes, start + 2) : (.dash, start + 1)
        case PlaneMapByte.colon: return (.colon, start + 1)
        case PlaneMapByte.lessThan, PlaneMapByte.greaterThan: return (.into, start + 1)
        case PlaneMapByte.openingBrace: return terminals.hasPrefix("{group}", at: start) ? (.groupModifier, start + 7) : nil
        case PlaneMapByte.lineFeed: return (.newline, start + 1)
        case PlaneMapByte.carriageReturn:
            return (.newline, terminals.byte(start + 1) == PlaneMapByte.lineFeed ? start + 2 : start + 1)
        case PlaneMapByte.percent:
            if let end = terminals.endOfDirective(at: start) { return (nil, end) }
            return terminals.endOfComment(at: start).map { end in (nil, end) }
        case PlaneMapByte.quotationMark, PlaneMapByte.apostrophe:
            return terminals.endOfString(at: start).map { end in (.string(PlaneMapTerminalValues.string(terminals.text(from: start, to: end))), end) }
        case PlaneMapByte.openingParenthesis: return icon(at: start, terminals: terminals)
        case PlaneMapByte.openingBracket: return label(at: start, terminals: terminals)
        case UInt8(ascii: "L"): return (.side(.left), start + 1)
        case UInt8(ascii: "R"): return (.side(.right), start + 1)
        case UInt8(ascii: "T"): return (.side(.top), start + 1)
        case UInt8(ascii: "B"): return (.side(.bottom), start + 1)
        default: return word(at: start, terminals: &terminals)
        }
    }

    /// A keyword, an accessibility statement, a title or an identifier.
    private static func word(at start: Int, terminals: inout PlaneMapTerminals) -> (ArchitectureToken?, Int)? {
        let identifierEnd = endOfIdentifier(at: start, terminals: terminals)
        for (keyword, token) in keywords where terminals.hasPrefix(keyword, at: start) {
            let end = start + keyword.utf8.count
            if let identifierEnd, identifierEnd > end { return (.identifier(terminals.text(from: start, to: identifierEnd)), identifierEnd) }
            return (token, end)
        }
        if let end = terminals.endOfAccessibilityDescription(at: start) {
            return (.accessibilityDescription(PlaneMapTerminalValues.accessibilityDescription(terminals.text(from: start, to: end))), end)
        }
        if let end = terminals.endOfAccessibilityTitle(at: start) {
            return (.accessibilityTitle(PlaneMapTerminalValues.accessibilityTitle(terminals.text(from: start, to: end))), end)
        }
        if let end = endOfTitle(at: start, terminals: terminals) { return (.title(PlaneMapTerminalValues.title(terminals.text(from: start, to: end))), end) }
        return identifierEnd.map { end in (.identifier(terminals.text(from: start, to: end)), end) }
    }

    /// The words of Pele's table, in its order (`architecture-beta` is read as the diagram's keyword).
    private static let keywords: [(String, ArchitectureToken)] = [
        ("junction", .junction), ("service", .service), ("column", .column), ("group", .group), ("align", .align), ("row", .row), ("in", .inGroup),
    ]

    /// `[\w]([-\w]*\w)?`: a word character, then word characters and hyphens ending on a word character.
    static func endOfIdentifier(at start: Int, terminals: PlaneMapTerminals) -> Int? {
        guard let first = terminals.byte(start), PlaneMapByte.isWord(first) else { return nil }
        var end = start + 1
        var lastWord = end
        while let next = terminals.byte(end), PlaneMapByte.isWord(next) || next == PlaneMapByte.hyphen {
            end += 1
            if PlaneMapByte.isWord(next) { lastWord = end }
        }
        return lastWord
    }

    /// Pele's `titleBefore`: `title` and a blank and the rest of the line up to a comment, or `title` alone when no
    /// identifier's rest (`[-\w]*\w`) follows it.
    private static func endOfTitle(at start: Int, terminals: PlaneMapTerminals) -> Int? {
        guard terminals.hasPrefix("title", at: start) else { return nil }
        if let separator = terminals.byte(start + 5), PlaneMapByte.isBlank(separator) { return terminals.endBeforeComment(from: start + 6) }
        var index = start + 5
        while let next = terminals.byte(index), PlaneMapByte.isWord(next) || next == PlaneMapByte.hyphen {
            if PlaneMapByte.isWord(next) { return nil }
            index += 1
        }
        return start + 5
    }

    /// `\([\w-:]+\)`: the name inside.
    private static func icon(at start: Int, terminals: PlaneMapTerminals) -> (ArchitectureToken?, Int)? {
        var end = start + 1
        while let next = terminals.byte(end), PlaneMapByte.isWord(next) || next == PlaneMapByte.hyphen || next == PlaneMapByte.colon { end += 1 }
        guard end > start + 1, terminals.byte(end) == PlaneMapByte.closingParenthesis else { return nil }
        return (.icon(terminals.text(from: start + 1, to: end)), end + 1)
    }

    /// `\[("…"|'…'|[^\[\]\r\n]+)\]`, a quoted form taking escapes and line breaks, tried before the plain one.
    private static func label(at start: Int, terminals: PlaneMapTerminals) -> (ArchitectureToken?, Int)? {
        if let quoteEnd = terminals.endOfString(at: start + 1), terminals.byte(quoteEnd) == PlaneMapByte.closingBracket {
            return (.label(terminals.text(from: start, to: quoteEnd + 1)), quoteEnd + 1)
        }
        var end = start + 1
        while let next = terminals.byte(end), next != PlaneMapByte.openingBracket, next != PlaneMapByte.closingBracket, !PlaneMapByte.isLineBreak(next) {
            end += 1
        }
        guard end > start + 1, terminals.byte(end) == PlaneMapByte.closingBracket else { return nil }
        return (.label(terminals.text(from: start, to: end + 1)), end + 1)
    }
}
