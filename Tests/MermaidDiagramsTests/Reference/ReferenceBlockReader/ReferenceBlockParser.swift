/**
 * File: ReferenceBlockParser.swift
 * --------------------------------
 * Layer: Tests
 * Description: MermaidDiagrams 0.7.0's BlockParser, frozen as main 2a0cc65 had it: the reference the block reader is
 *              proven against (BlockReadingEquivalenceTests).
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 24/11/2026
 */

@testable import MermaidDiagrams
/// Reads a block diagram's text, from its keyword, as Pele's `parseBlock` reads Mermaid's grammar: a composite that
/// opens keeps the statements of the one around it, so nesting needs no recursion; at the end the statements are set
/// into their hierarchy (`ReferenceBlockHierarchy`). The blocks and space cells count as nodes and the links as edges, each
/// checked against the limits as it is read.
struct ReferenceBlockParser {
    private let tokens: [ReferenceBlockToken]
    private let source: ReferenceBlockPreparedSource
    private let limits: MermaidDiagramLimits
    private var index = 0
    private(set) var statements: [ReferenceBlockStatement] = []
    /// Pele's `generateId` count: the composites and spaces named so far.
    private(set) var generatedIdentifierCount = 0
    private var nodeCount = 0
    private var edgeCount = 0

    static func parse(_ cursor: MermaidTextCursor, keyword: String, limits: MermaidDiagramLimits) throws(MermaidDiagramReadError) -> BlockDiagram {
        let source = ReferenceBlockPreparedSource(cursor.bytes, from: cursor.position - keyword.utf8.count)
        let tokens = ReferenceBlockLexer.tokens(of: source.bytes, from: source.start)
        var parser = ReferenceBlockParser(tokens: tokens, source: source, limits: limits)
        let top = try parser.document()
        var hierarchy = ReferenceBlockHierarchy(statements: parser.statements, generatedIdentifierCount: parser.generatedIdentifierCount)
        hierarchy.set(top)
        var diagram = hierarchy.diagram
        if case .number(let padding) = MermaidConfigurationOptions(section: "block", in: cursor).values["padding"], padding >= 0 {
            diagram.padding = min(padding, BlockLayoutEngine.largestPadding)
        }
        return diagram
    }

    private var kind: ReferenceBlockTokenKind { tokens[index].kind }

    /// The statements of the document after its keyword, the top level's by their place in `statements`.
    private mutating func document() throws(MermaidDiagramReadError) -> [Int] {
        _ = try expect(.keyword, else: .expectedKeyword)
        var open: [(list: [Int], header: ReferenceBlockDraft?, headerWasLinks: Bool)] = []
        var list: [Int] = []
        while true {
            switch kind {
            case .nodeIdentifier: try append(nodeStatement(), to: &list)
            case .columns:
                let written = tokens[index].text
                index += 1
                append([.columns(written == "-1" ? nil : ReferenceBlockSyntaxValues.count(written) ?? 0)], to: &list)
            case .space: try append([space()], to: &list)
            case .keyword:
                index += 1
                open.append((list, nil, false))
                list = []
            case .compositeKeyword:
                index += 1
                guard kind == .nodeIdentifier else { throw failure(.expectedBlockIdentifier) }
                let header = try nodeStatement()
                open.append((list, header.count == 1 ? header.first.flatMap(Self.draft) : nil, header.count > 1))
                list = []
            case .end:
                guard let frame = open.popLast(), !list.isEmpty else { throw failure(.expectedStatement) }
                index += 1
                generatedIdentifierCount += 1
                let identifier = frame.header == nil && !frame.headerWasLinks ? "id-\(generatedIdentifierCount)" : nil
                let composite = ReferenceBlockStatement.composite(header: frame.header, identifier: identifier, childIndices: list)
                list = frame.list
                append([composite], to: &list)
            case .classDefinition, .classAssignment, .style: try append([styling()], to: &list)
            case .endOfText:
                guard open.isEmpty else { throw failure(.unclosedComposite) }
                guard !list.isEmpty else { throw failure(.expectedStatement) }
                return list
            default: throw failure(.expectedStatement)
            }
        }
    }

    private mutating func append(_ items: [ReferenceBlockStatement], to list: inout [Int]) {
        for item in items {
            list.append(statements.count)
            statements.append(item)
        }
    }

    private static func draft(_ statement: ReferenceBlockStatement) -> ReferenceBlockDraft? {
        guard case .block(let draft) = statement else { return nil }
        return draft
    }

    /// `space` or `space:N`, its cells counted as nodes.
    private mutating func space() throws(MermaidDiagramReadError) -> ReferenceBlockStatement {
        let width = ReferenceBlockSyntaxValues.count(tokens[index].text) ?? Int.max
        guard width <= limits.maximumNodeCount - nodeCount else { throw .tooManyNodes(limit: limits.maximumNodeCount) }
        nodeCount += width
        index += 1
        generatedIdentifierCount += 1
        return .space(identifier: "id-\(generatedIdentifierCount)", width: width)
    }

    /// `classDef`, `class` or `style`, with what follows it to the end of its line.
    private mutating func styling() throws(MermaidDiagramReadError) -> ReferenceBlockStatement {
        let statement = kind
        index += 1
        switch statement {
        case .classDefinition:
            let name = try expect(.classDefinitionIdentifier, else: .expectedClassDefinition)
            let declarations = try expect(.classDefinitionStyles, else: .expectedClassDefinition)
            return .classDefinition(name: Self.trimmed(name), declarations: Self.trimmed(declarations))
        case .classAssignment:
            let identifiers = try expect(.classAssignmentIdentifiers, else: .expectedStyleTarget)
            let className = try expect(.classAssignmentName, else: .expectedStyleTarget)
            return .classAssignment(identifiers: Self.trimmed(identifiers), className: Self.trimmed(className))
        default:
            let identifiers = try expect(.styleIdentifiers, else: .expectedStyleTarget)
            let declarations = try expect(.styleDeclarations, else: .expectedStyleTarget)
            return .style(identifiers: Self.trimmed(identifiers), declarations: Self.trimmed(declarations))
        }
    }

    /// A block, its size, and its links to the blocks after it: one item per block and per edge. As in Pele, a block
    /// that a link follows keeps no size, and every link counts (Mermaid keeps only the last).
    private mutating func nodeStatement() throws(MermaidDiagramReadError) -> [ReferenceBlockStatement] {
        var first = try node()
        if kind == .size {
            first.widthInColumns = ReferenceBlockSyntaxValues.count(tokens[index].text) ?? Int.max
            index += 1
        }
        try countNode()
        guard kind == .link || kind == .startLink else { return [.block(first)] }
        first.widthInColumns = 1
        var items: [ReferenceBlockStatement] = [.block(first)]
        var previous = first.identifier
        while kind == .link || kind == .startLink {
            var label = ""
            let opensText = kind == .startLink
            index += 1
            if opensText {
                _ = try expect(.linkLabel, else: .expectedQuotedText)
                label = try expect(.string, else: .expectedQuotedText)
                _ = try expect(.link, else: .expectedLink)
            }
            let link = tokens[index - 1].text
            var target = try node()
            target.widthInColumns = 1
            guard edgeCount < limits.maximumEdgeCount else { throw .tooManyEdges(limit: limits.maximumEdgeCount) }
            edgeCount += 1
            try countNode()
            items.append(.edge(ReferenceBlockEdgeDraft(identifier: previous + "-" + target.identifier, sourceIdentifier: previous,
                                              targetIdentifier: target.identifier, label: label, link: link)))
            items.append(.block(target))
            previous = target.identifier
        }
        return items
    }

    /// An identifier, then its shape's brackets around a string, or an arrow's with its directions.
    private mutating func node() throws(MermaidDiagramReadError) -> ReferenceBlockDraft {
        let identifier = try expect(.nodeIdentifier, else: .expectedBlockIdentifier)
        if kind == .nodeStart {
            let opening = tokens[index].text
            index += 1
            let label = try expect(.string, else: .expectedQuotedText)
            let closing = try expect(.nodeEnd, else: .expectedClosingBracket)
            return ReferenceBlockDraft(identifier: identifier, label: label, kind: ReferenceBlockSyntaxValues.kind(brackets: opening + closing), directions: [],
                              widthInColumns: 1)
        }
        guard kind == .arrowStart else { return ReferenceBlockDraft(identifier: identifier, label: nil, kind: .unshaped, directions: [], widthInColumns: 1) }
        let opening = tokens[index].text
        index += 1
        let label = try expect(.string, else: .expectedQuotedText)
        var directions = [try expect(.direction, else: .expectedArrowDirection)]
        while kind == .direction {
            directions.append(tokens[index].text)
            index += 1
        }
        let closing = try expect(.arrowEnd, else: .expectedArrowEnd)
        return ReferenceBlockDraft(identifier: identifier, label: label, kind: ReferenceBlockSyntaxValues.kind(brackets: opening + closing), directions: directions,
                          widthInColumns: 1)
    }

    private mutating func countNode() throws(MermaidDiagramReadError) {
        guard nodeCount < limits.maximumNodeCount else { throw .tooManyNodes(limit: limits.maximumNodeCount) }
        nodeCount += 1
    }

    /// The text of the token of `expected` kind, which is taken; else the error, or the lexer's where it stopped.
    private mutating func expect(_ expected: ReferenceBlockTokenKind, else problem: BlockSyntaxProblem) throws(MermaidDiagramReadError) -> String {
        guard kind == expected else { throw failure(problem) }
        index += 1
        return tokens[index - 1].text
    }

    /// The error at the current token: the lexer's where it stopped, else `problem`, on the token's line.
    private func failure(_ problem: BlockSyntaxProblem) -> MermaidDiagramReadError {
        let start = tokens[index].start
        let line = source.line(of: start)
        if kind == .unrecognized { return .invalidSyntax(line: line, problem: .unexpectedText(PlaneMapByte.excerpt(at: start, in: source.bytes))) }
        return .invalidSyntax(line: line, problem: .block(problem))
    }

    private static func trimmed(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
