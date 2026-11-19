/**
 * File: C4Parser.swift
 * --------------------
 * Layer: Core
 * Description: Reads a C4 diagram's tokens as the parser Jison generates from Mermaid's c4Diagram.jison does (Pele's
 *              parser.ts): what it accepts, and its calls into the model in the order of the grammar's actions, with
 *              boundaries nested through a counter, not recursion.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 19/11/2026
 */

/// Reads a C4 diagram from its keyword on. A statement is a title, an accessibility statement or a macro, each on its
/// own line; a boundary's macro opens a block in braces. An error names the line its token is on and what the grammar
/// expected there.
struct C4Parser {
    /// Where the statement loop stands: a statement required; only a macro next (the first statement of a boundary, or
    /// one written straight after a title); a statement or the end of a block; after a title or an accessibility
    /// statement; after a macro.
    private enum Expectation {
        case statement, macro, statementOrEnd, afterTitle, afterMacro
    }

    private let units: [UInt16]
    private let tokens: C4Tokens
    /// The line of the text the keyword is on.
    private let firstLine: Int
    private var index = 0
    private var builder: C4DiagramBuilder

    static func parse(keyword: String, endingAt cursor: MermaidTextCursor, limits: MermaidDiagramLimits) throws(MermaidDiagramReadError) -> C4Diagram {
        let units = Array(cursor.text(from: cursor.position - keyword.utf8.count, to: cursor.bytes.count).utf16)
        var parser = C4Parser(units: units, firstLine: cursor.line, limits: limits)
        try parser.readDiagram()
        return parser.builder.diagram
    }

    private init(units: [UInt16], firstLine: Int, limits: MermaidDiagramLimits) {
        self.units = units
        self.firstLine = firstLine
        tokens = C4Lexer.tokens(of: units)
        builder = C4DiagramBuilder(limits: limits)
    }

    private var current: C4TokenKind { index < tokens.kinds.count ? tokens.kinds[index] : .end }

    private mutating func readDiagram() throws(MermaidDiagramReadError) {
        let header = current
        guard header >= .context, header <= .deployment else { throw failure(expecting: .header) }
        builder.diagram.level = C4DiagramLevel(rawValue: text(at: index)) ?? .context
        index += 1
        try expect(.newline, .lineBreak)
        try readStatements()
    }

    private mutating func readStatements() throws(MermaidDiagramReadError) {
        var depth = 0
        var expectation = Expectation.statement
        while true {
            let token = current
            switch expectation {
            case .afterTitle, .afterMacro:
                if token == .newline {
                    index += 1
                    expectation = .statementOrEnd
                    continue
                }
                if expectation == .afterTitle, token.isMacro {
                    expectation = .macro
                    continue
                }
            default:
                if token.isMacro {
                    let opensBoundary = try readMacro(token)
                    if opensBoundary { depth += 1 }
                    expectation = opensBoundary ? .macro : .afterMacro
                    continue
                }
                if token.isTitleOrAccessibility, expectation != .macro {
                    try readTitleOrAccessibility(token)
                    expectation = .afterTitle
                    continue
                }
                guard expectation == .statementOrEnd else { throw failure(expecting: .statement) }
            }
            guard try readEndOfBlock(depth: depth) else { return }
            depth -= 1
            expectation = .afterMacro
        }
    }

    /// A boundary's closing brace, true, or the end of the text at the top level, false.
    private mutating func readEndOfBlock(depth: Int) throws(MermaidDiagramReadError) -> Bool {
        if depth > 0 {
            guard current == .closingBrace else { throw failure(expecting: .lineBreakOrClosingBrace) }
            index += 1
            builder.closeBoundary()
            return true
        }
        guard current == .endOfFile else { throw failure(expecting: .lineBreakOrEnd) }
        index += 1
        try expect(.end, .end)
        return false
    }

    private mutating func readTitleOrAccessibility(_ token: C4TokenKind) throws(MermaidDiagramReadError) {
        switch token {
        case .title:
            builder.diagram.title = text(at: index, droppingFirst: 6)
            index += 1
        case .accessibilityDescriptionStatement:
            builder.setAccessibilityDescription(text(at: index, droppingFirst: 15))
            index += 1
        case .accessibilityDescriptionMultilineValue:
            builder.setAccessibilityDescription(C4Characters.trimmed(text(at: index)))
            index += 1
        default:
            index += 1
            let isTitle = token == .accessibilityTitle
            guard current == (isTitle ? .accessibilityTitleValue : .accessibilityDescriptionValue) else { throw failure(expecting: .accessibilityValue) }
            let value = C4Characters.trimmed(text(at: index))
            index += 1
            // The grammar hands `accTitle:` to the title, so it becomes the visible title.
            if isTitle { builder.diagram.title = value } else { builder.setAccessibilityDescription(value) }
        }
    }

    /// A macro and its arguments, handed to the builder; true when it opens a boundary, whose brace is read here.
    private mutating func readMacro(_ token: C4TokenKind) throws(MermaidDiagramReadError) -> Bool {
        index += 1
        var arguments = try readArguments()
        switch token {
        case .person ... .externalComponentQueue:
            try builder.addShape(Self.shapeKinds[token.rawValue - C4TokenKind.person.rawValue], arguments: arguments)
        case .enterpriseBoundary ... .rightNode:
            try builder.addBoundary(token, arguments: arguments)
            try readBoundaryOpening()
            return true
        case .relation ... .relationIndex:
            // RelIndex takes a sequence number first, which Mermaid ignores.
            if token == .relationIndex, !arguments.isEmpty { arguments.removeFirst() }
            try builder.addRelation(Self.relationKinds[token.rawValue - C4TokenKind.relation.rawValue], arguments: arguments)
        case .updateElementStyle: builder.updateElementStyle(arguments)
        case .updateRelationStyle: builder.updateRelationStyle(arguments)
        default: builder.updateLayoutConfiguration(arguments)
        }
        return false
    }

    /// `{` and a line break, or a line break, `{` and an optional line break.
    private mutating func readBoundaryOpening() throws(MermaidDiagramReadError) {
        if current == .openingBrace {
            index += 1
            try expect(.newline, .lineBreak)
        } else if current == .newline {
            index += 1
            try expect(.openingBrace, .openingBrace)
            if current == .newline { index += 1 }
        } else {
            throw failure(expecting: .lineBreakOrOpeningBrace)
        }
    }

    /// One argument or more: quoted or bare text (trimmed), empty ones, and `$key="value"`.
    private mutating func readArguments() throws(MermaidDiagramReadError) -> [C4Argument] {
        var arguments: [C4Argument] = []
        while true {
            switch current {
            case .string:
                arguments.append(.positional(C4Characters.trimmed(text(at: index))))
                index += 1
            case .emptyArgument:
                arguments.append(.positional(""))
                index += 1
            case .namedArgumentKey:
                index += 1
                guard current == .namedArgumentValue else { throw failure(expecting: .namedValue) }
                let key = C4Characters.trimmed(text(at: index - 1))
                arguments.append(.named(C4NamedArgument(key: key, value: C4Characters.trimmed(text(at: index)))))
                index += 1
            default:
                guard !arguments.isEmpty else { throw failure(expecting: .arguments) }
                return arguments
            }
        }
    }

    private mutating func expect(_ kind: C4TokenKind, _ expected: C4ExpectedSyntax) throws(MermaidDiagramReadError) {
        guard current == kind else { throw failure(expecting: expected) }
        index += 1
    }

    private func text(at tokenIndex: Int, droppingFirst droppedCount: Int = 0) -> String {
        let start = min(tokens.starts[tokenIndex] + droppedCount, tokens.ends[tokenIndex])
        return String(decoding: units[start..<tokens.ends[tokenIndex]], as: UTF16.self)
    }

    /// The line the token at `tokenIndex` starts on, in the whole text.
    private func line(at tokenIndex: Int) -> Int {
        let offset = tokenIndex < tokens.starts.count ? tokens.starts[tokenIndex] : units.count
        return firstLine + units[..<min(offset, units.count)].count { unit in unit == C4Characters.lineFeed }
    }

    private func failure(expecting expected: C4ExpectedSyntax) -> MermaidDiagramReadError {
        let token = current
        let problem: C4SyntaxProblem = token == .error ? .unrecognizedText : .unexpectedToken(found: token.grammarName, expected: expected)
        return .invalidSyntax(line: line(at: index), problem: .c4(problem))
    }

    /// Mermaid's `typeC4Shape` of each shape macro, from `Person` on.
    private static let shapeKinds: [C4ShapeKind] = C4ShapeKind.allCases
    private static let relationKinds: [C4RelationKind] = [.relation, .bidirectional, .relationUp, .relationDown, .relationLeft, .relationRight,
                                                          .relationBack, .relation]
}

/// An argument of a macro: positional text, or a `$key="value"` argument.
enum C4Argument: Equatable {
    case positional(String)
    case named(C4NamedArgument)
}
