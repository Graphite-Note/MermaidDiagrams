/**
 * File: CynefinParser.swift
 * -------------------------
 * Layer: Core
 * Description: Reads a Cynefin framework after its `cynefin-beta` keyword as Mermaid's Langium grammar does (Pele's
 *              parser.ts and model.ts): its tokens first, then titles, accessibility statements, domain blocks with
 *              their quoted items, and transitions.
 *
 * Authors: Bahey Shalash
 * Version: 0.2
 * Date: 23/11/2026
 */

/// A token of a Cynefin framework.
enum CynefinToken: Equatable {
    case arrow
    case colon
    case domain(CynefinDomain)
    case accessibilityDescription(String)
    case accessibilityTitle(String)
    case title(String)
    case string(String)
    case newline
}

/// Reads a Cynefin framework's statements. The whole text is read into tokens first, as Langium's lexer reads it, so that
/// text no terminal reads is an error wherever it is; then a domain followed by `-->` is a transition, and a domain on
/// its own starts a block of the quoted items after it, over any lines.
struct CynefinParser {
    private let tokens: [(token: CynefinToken, start: Int)]
    private let bytes: [UInt8]
    private let limits: MermaidDiagramLimits
    private var index = 0
    private var diagram = CynefinDiagram()

    static func parse(_ cursor: MermaidTextCursor, limits: MermaidDiagramLimits) throws(MermaidDiagramReadError) -> CynefinDiagram {
        var parser = CynefinParser(tokens: try CynefinLexer.tokens(after: cursor, limits: limits), bytes: cursor.bytes, limits: limits)
        parser.diagram.options = CynefinOptions(MermaidConfigurationOptions(section: "cynefin", in: cursor.sourceBytes))
        try parser.readStatements()
        return parser.diagram
    }

    private init(tokens: [(token: CynefinToken, start: Int)], bytes: [UInt8], limits: MermaidDiagramLimits) {
        self.tokens = tokens
        self.bytes = bytes
        self.limits = limits
    }

    private var current: CynefinToken? {
        index < tokens.count ? tokens[index].token : nil
    }

    private mutating func readStatements() throws(MermaidDiagramReadError) {
        while let token = current {
            index += 1
            switch token {
            case .newline: continue
            case .accessibilityDescription(let text): diagram.accessibilityDescription = text.isEmpty ? nil : text
            case .accessibilityTitle(let text): diagram.accessibilityTitle = text.isEmpty ? nil : text
            case .title(let text): diagram.title = text.isEmpty ? nil : text
            case .domain(let domain):
                if current == .arrow {
                    index += 1
                    try readTransition(from: domain)
                } else {
                    try readBlock(of: domain)
                    continue
                }
            default:
                index -= 1
                throw failure(.expectedStatement)
            }
            try expectLineEnd()
        }
    }

    /// The domain after `-->`, then `:` and a quoted label, optional; a transition from a domain to itself is left out.
    private mutating func readTransition(from origin: CynefinDomain) throws(MermaidDiagramReadError) {
        guard case .domain(let target) = current else { throw failure(.expectedDomain) }
        index += 1
        var label: String?
        if current == .colon {
            index += 1
            guard case .string(let text) = current else { throw failure(.expectedQuotedLabel) }
            index += 1
            label = text.isEmpty ? nil : text
        }
        guard origin != target else { return }
        guard diagram.transitions.count < limits.maximumEdgeCount else { throw .tooManyEdges(limit: limits.maximumEdgeCount) }
        diagram.transitions.append(CynefinTransition(from: origin, to: target, label: label))
    }

    /// The quoted items after a domain, over any lines.
    private mutating func readBlock(of domain: CynefinDomain) throws(MermaidDiagramReadError) {
        var items: [String] = []
        skipLineBreaks()
        while case .string(let text) = current {
            index += 1
            guard itemCount(replacing: domain) + items.count < limits.maximumNodeCount else { throw .tooManyNodes(limit: limits.maximumNodeCount) }
            items.append(text)
            skipLineBreaks()
        }
        diagram.items[domain] = items
    }

    /// The items of every domain but `domain`, whose block is being replaced.
    private func itemCount(replacing domain: CynefinDomain) -> Int {
        diagram.items.reduce(0) { count, entry in entry.key == domain ? count : count + entry.value.count }
    }

    private mutating func skipLineBreaks() {
        while current == .newline { index += 1 }
    }

    /// A line break, then any more, or the end of the text.
    private mutating func expectLineEnd() throws(MermaidDiagramReadError) {
        guard current != nil else { return }
        guard current == .newline else { throw failure(.expectedLineEnd) }
        skipLineBreaks()
    }

    /// The problem on the line of the current token, or of the last token at the end of the text.
    private func failure(_ problem: CynefinSyntaxProblem) -> MermaidDiagramReadError {
        let offset = index < tokens.count ? tokens[index].start : tokens.last { token in token.token != .newline }?.start ?? bytes.count
        return .invalidSyntax(line: PlaneMapByte.line(of: offset, in: bytes), problem: .cynefin(problem))
    }
}
