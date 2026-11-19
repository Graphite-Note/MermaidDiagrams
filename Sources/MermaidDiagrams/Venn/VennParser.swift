/**
 * File: VennParser.swift
 * ----------------------
 * Layer: Core
 * Description: Reads a Venn diagram's statements after its `venn-beta` keyword as Mermaid's Venn grammar does (Pele's
 *              parser.ts and db.ts): titles, sets, unions, texts and styles.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 19/11/2026
 */

/// Reads a Venn diagram's statements, as Mermaid's grammar does. A token is read only when the grammar must look at one
/// to decide, because the lexer asks whether an indented `text` continues a set, and the statements read so far are what
/// tell it. Each statement may follow another on the same line; a line break is a statement that does nothing.
struct VennParser {
    private var lexer: VennLexer
    private let bytes: [UInt8]
    private let limits: MermaidDiagramLimits
    private var peeked: VennToken?
    private var diagram = VennDiagram()
    /// The sets declared by `set`, which a union may name.
    private var knownSets: Set<String> = []
    /// The sets of the last set or union, which an indented text belongs to.
    private var currentSets: [String]?
    /// Whether an indented `text` continues the set or union before it.
    private var indentMode = false
    /// The members of unions and the style statements read, bounded by the limits' edges.
    private var edgeCount = 0

    static func parse(_ cursor: MermaidTextCursor, limits: MermaidDiagramLimits) throws(MermaidDiagramReadError) -> VennDiagram {
        var parser = VennParser(lexer: VennLexer(bytes: cursor.bytes, position: cursor.position), bytes: cursor.bytes, limits: limits)
        try parser.readStatements()
        return parser.diagram
    }

    private init(lexer: VennLexer, bytes: [UInt8], limits: MermaidDiagramLimits) {
        self.lexer = lexer
        self.bytes = bytes
        self.limits = limits
    }

    private mutating func peek() -> VennToken {
        if let peeked { return peeked }
        let token = lexer.next(indentMode: &indentMode)
        peeked = token
        return token
    }

    private mutating func take() -> VennToken {
        let token = peek()
        peeked = nil
        return token
    }

    private mutating func readStatements() throws(MermaidDiagramReadError) {
        while true {
            let statement = peek()
            switch statement.kind {
            case .endOfText: return
            case .newline: _ = take()
            case .title:
                _ = take()
                diagram.title = Self.unquoted(String(statement.text.dropFirst(Self.titleKeywordLength)))
            case .set:
                _ = take()
                try readSubset(identifiers: [try readIdentifier()], isUnion: false, statement: statement)
            case .union:
                _ = take()
                try readSubset(identifiers: try readIdentifiers(), isUnion: true, statement: statement)
            case .text:
                _ = take()
                let sets = try readIdentifiers()
                try readText(sets: sets)
            case .indentedText:
                _ = take()
                guard let currentSets else { throw problem(.textWithoutSet, at: statement) }
                try readText(sets: currentSets)
            case .style:
                _ = take()
                try readStyle()
            default:
                throw failure(.expectedStatement)
            }
        }
    }

    /// A label in brackets and a size after a colon, both optional; a union names two or more sets `set` declared. Its
    /// errors are on the line of `statement`, found only when one is thrown.
    private mutating func readSubset(identifiers: [String], isUnion: Bool, statement: VennToken) throws(MermaidDiagramReadError) {
        let label = peek().kind == .bracketLabel ? take().text : nil
        var size: Double?
        if peek().kind == .colon {
            _ = take()
            guard peek().kind == .number else { throw failure(.expectedSize) }
            size = Double(take().text) ?? .nan
        }
        if isUnion {
            guard identifiers.count >= 2 else { throw problem(.unionOfOneSet, at: statement) }
            let unknown = identifiers.map(Self.unquoted).filter { identifier in !knownSets.contains(identifier) }
            guard unknown.isEmpty else { throw problem(.unknownSetIdentifiers(unknown), at: statement) }
            try countEdges(identifiers.count)
        }
        try countNode()
        let sets = Self.sortedIdentifiers(identifiers)
        currentSets = sets
        if sets.count == 1 { knownSets.insert(sets[0]) }
        let count = Double(identifiers.count)
        diagram.subsets.append(VennSubset(sets: sets, size: size ?? 10 / (count * count), label: label.flatMap(Self.nonEmptyUnquoted)))
        indentMode = true
    }

    /// A text's identifier (a word, quoted text or a number), and the label in brackets an identifier that is no number
    /// may carry.
    private mutating func readText(sets: [String]) throws(MermaidDiagramReadError) {
        let identifier = peek()
        guard identifier.kind == .identifier || identifier.kind == .string || identifier.kind == .number else { throw failure(.expectedTextIdentifier) }
        _ = take()
        let label = identifier.kind != .number && peek().kind == .bracketLabel ? take().text : nil
        try countNode()
        diagram.texts.append(VennText(sets: Self.sortedIdentifiers(sets), identifier: Self.unquoted(identifier.text),
                                      label: label.flatMap(Self.nonEmptyUnquoted)))
    }

    /// The targets, then `property: value` declarations separated by commas; a value is quoted text, or identifiers,
    /// numbers and colors joined by spaces.
    private mutating func readStyle() throws(MermaidDiagramReadError) {
        let targets = try readIdentifiers()
        var declarations: [VennStyleDeclaration] = []
        while true {
            guard peek().kind == .identifier else { throw failure(.expectedStyleDeclaration) }
            let property = take().text
            guard peek().kind == .colon else { throw failure(.expectedStyleDeclaration) }
            _ = take()
            var value: String
            if peek().kind == .string {
                value = take().text
            } else {
                var pieces: [String] = []
                while peek().kind.isStyleValuePiece { pieces.append(take().text) }
                guard !pieces.isEmpty else { throw failure(.expectedStyleDeclaration) }
                value = pieces.joined(separator: " ")
            }
            if !value.isEmpty { value = Self.unquoted(value) }
            declarations.append(VennStyleDeclaration(property: property, value: value))
            guard peek().kind == .comma else { break }
            _ = take()
        }
        try countEdges(1)
        diagram.styles.append(VennStyle(targets: Self.sortedIdentifiers(targets), declarations: declarations))
    }

    private mutating func readIdentifier() throws(MermaidDiagramReadError) -> String {
        guard peek().kind == .identifier || peek().kind == .string else { throw failure(.expectedIdentifier) }
        return take().text
    }

    private mutating func readIdentifiers() throws(MermaidDiagramReadError) -> [String] {
        var identifiers = [try readIdentifier()]
        while peek().kind == .comma {
            _ = take()
            guard identifiers.count < limits.maximumEdgeCount else { throw .tooManyEdges(limit: limits.maximumEdgeCount) }
            identifiers.append(try readIdentifier())
        }
        return identifiers
    }

    private mutating func countNode() throws(MermaidDiagramReadError) {
        guard diagram.subsets.count + diagram.texts.count < limits.maximumNodeCount else { throw .tooManyNodes(limit: limits.maximumNodeCount) }
    }

    private mutating func countEdges(_ count: Int) throws(MermaidDiagramReadError) {
        edgeCount += count
        guard edgeCount <= limits.maximumEdgeCount else { throw .tooManyEdges(limit: limits.maximumEdgeCount) }
    }

    /// The error of the token peeked: text no rule reads, or a token where `expected` was wanted.
    private mutating func failure(_ expected: VennSyntaxProblem) -> MermaidDiagramReadError {
        let token = peek()
        if token.kind == .error {
            return .invalidSyntax(line: line(of: token), problem: .unexpectedText(PlaneMapByte.excerpt(at: token.start, in: bytes)))
        }
        return problem(expected, at: token)
    }

    private func problem(_ problem: VennSyntaxProblem, at token: VennToken) -> MermaidDiagramReadError {
        .invalidSyntax(line: line(of: token), problem: .venn(problem))
    }

    private func line(of token: VennToken) -> Int {
        PlaneMapByte.line(of: token.start, in: bytes)
    }

    /// The text without the white space at its ends and then one pair of quotation marks around it, as Mermaid's database
    /// takes them off identifiers, labels and values.
    static func unquoted(_ text: String) -> String {
        let trimmed = PlaneMapText.trimmed(text)
        guard trimmed.utf8.count >= 2, trimmed.hasPrefix("\""), trimmed.hasSuffix("\"") else { return trimmed }
        return String(trimmed.dropFirst().dropLast())
    }

    /// A label as the database keeps it: nil when it is empty, as JavaScript treats an empty string as no label.
    private static func nonEmptyUnquoted(_ label: String) -> String? {
        label.isEmpty ? nil : unquoted(label)
    }

    private static func sortedIdentifiers(_ identifiers: [String]) -> [String] {
        identifiers.map(unquoted).sorted(by: PlaneMapText.isOrderedBeforeByCodeUnits)
    }

    /// `title` and the character after it.
    private static let titleKeywordLength = 6
}
