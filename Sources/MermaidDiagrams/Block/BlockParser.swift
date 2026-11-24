/**
 * File: BlockParser.swift
 * -----------------------
 * Layer: Core
 * Description: Reads a block diagram as Pele's block parser does: its statements as plain values over the text's bytes,
 *              composites nested without recursion, every link of a statement kept, each error with its line.
 *
 * Authors: Bahey Shalash
 * Version: 0.5
 * Date: 24/11/2026
 */

/// Reads a block diagram's text, from its keyword, as Pele's `parseBlock` reads Mermaid's grammar: a composite that
/// opens keeps the statements of the one around it, so nesting needs no recursion; at the end the statements are set
/// into their hierarchy (`BlockHierarchy`). Statements are plain values whose texts are runs of the text's bytes, and a
/// composite's statements a run of one list of places, so nothing read is a String. The blocks and space cells count as
/// nodes and the links as edges, each checked against the limits as it is read.
struct BlockParser {
    private let tokens: ScratchList<BlockToken>
    private let source: BlockPreparedSource
    private let limits: MermaidDiagramLimits
    private var index = 0
    private(set) var statements: ScratchList<BlockStatement>
    /// The places in `statements` of every composite's statements, each composite's a run, the top level's last.
    private(set) var statementPlaces: ScratchList<Int32>
    /// The texts lists hold: arrows' directions.
    private(set) var texts: [BlockText] = []
    /// The places of the statements of the composites open, the innermost's last; each is moved to `statementPlaces`
    /// when its composite ends.
    private var openPlaces: ScratchList<Int32>
    /// The composites open, the innermost last.
    private var openComposites: ScratchList<BlockOpenComposite>
    /// Pele's `generateId` count: the composites and spaces named so far.
    private(set) var generatedIdentifierCount = 0
    private var nodeCount = 0
    private var edgeCount = 0

    static func parse(_ cursor: MermaidTextCursor, keyword: String, limits: MermaidDiagramLimits) throws(MermaidDiagramReadError) -> BlockDiagram {
        let source = BlockPreparedSource(cursor.bytes, from: cursor.position - keyword.utf8.count)
        // The tokens, the statements and the hierarchy's working lists live in the thread's arena; the model is copied
        // out of them.
        let read = DiagramScratchArena.withCurrentThread { arena in
            Result { () throws(MermaidDiagramReadError) -> BlockModel in
                var parser = BlockParser(tokens: BlockLexer.tokens(of: source.bytes, from: source.start, in: arena), source: source, limits: limits,
                                         arena: arena)
                let top = try parser.document()
                var hierarchy = BlockHierarchy(parser: parser, bytes: source.bytes, arena: arena)
                hierarchy.set(top)
                return hierarchy.model()
            }
        }
        var diagram = BlockDiagram(model: try read.get())
        if case .number(let padding) = MermaidConfigurationOptions(section: "block", in: cursor).values["padding"], padding >= 0 {
            diagram.padding = min(padding, BlockLayoutEngine.largestPadding)
        }
        return diagram
    }

    private init(tokens: ScratchList<BlockToken>, source: BlockPreparedSource, limits: MermaidDiagramLimits, arena: DiagramScratchArena) {
        self.tokens = tokens
        self.source = source
        self.limits = limits
        statements = arena.list(capacity: tokens.count / 2 + 1)
        statementPlaces = arena.list(capacity: tokens.count / 2 + 1)
        openPlaces = arena.list(capacity: tokens.count / 2 + 1)
        openComposites = arena.list(capacity: 8)
    }

    private var kind: BlockTokenKind { tokens[index].kind }

    /// The statements of the document after its keyword: the top level's run of `statementPlaces`.
    private mutating func document() throws(MermaidDiagramReadError) -> BlockSlice {
        _ = try expect(.keyword, else: .expectedKeyword)
        var placesStart = 0
        while true {
            switch kind {
            case .nodeIdentifier: _ = try nodeStatement(keepsItems: true)
            case .columns:
                let token = tokens[index]
                index += 1
                append(.columns(token.literal != .none ? nil : withText(of: token) { digits in BlockSyntaxValues.count(digits) ?? 0 }))
            case .space: append(try space())
            case .keyword:
                index += 1
                openComposites.append(BlockOpenComposite(placesStart: placesStart, header: nil, headerWasLinks: false))
                placesStart = openPlaces.count
            case .compositeKeyword:
                index += 1
                guard kind == .nodeIdentifier else { throw failure(.expectedBlockIdentifier) }
                let header = try nodeStatement(keepsItems: false)
                openComposites.append(BlockOpenComposite(placesStart: placesStart, header: header.statementCount == 1 ? header.first : nil,
                                                         headerWasLinks: header.statementCount > 1))
                placesStart = openPlaces.count
            case .end:
                guard let frame = openComposites.popLast(), openPlaces.count > placesStart else { throw failure(.expectedStatement) }
                index += 1
                generatedIdentifierCount += 1
                let identifierNumber = frame.header == nil && !frame.headerWasLinks ? generatedIdentifierCount : nil
                let children = closePlaces(from: placesStart)
                placesStart = frame.placesStart
                append(.composite(header: frame.header, identifierNumber: identifierNumber, children: children))
            case .classDefinition, .classAssignment, .style: append(try styling())
            case .endOfText:
                guard openComposites.isEmpty else { throw failure(.unclosedComposite) }
                guard openPlaces.count > placesStart else { throw failure(.expectedStatement) }
                return closePlaces(from: placesStart)
            default: throw failure(.expectedStatement)
            }
        }
    }

    /// The places from `start` on in `openPlaces`, moved to the end of `statementPlaces`.
    private mutating func closePlaces(from start: Int) -> BlockSlice {
        let slice = BlockSlice(first: statementPlaces.count, count: openPlaces.count - start)
        statementPlaces.append(contentsOf: openPlaces.elements.part(start..<openPlaces.count))
        while openPlaces.count > start { _ = openPlaces.removeLast() }
        return slice
    }

    /// `item` added to the statements, its place to the innermost open list.
    private mutating func append(_ item: BlockStatement) {
        openPlaces.append(Int32(truncatingIfNeeded: statements.count))
        statements.append(item)
    }

    /// `space` or `space:N`, its cells counted as nodes.
    private mutating func space() throws(MermaidDiagramReadError) -> BlockStatement {
        let token = tokens[index]
        let width = token.literal != .none ? 1 : withText(of: token) { digits in BlockSyntaxValues.count(digits) } ?? Int.max
        guard width <= limits.maximumNodeCount - nodeCount else { throw .tooManyNodes(limit: limits.maximumNodeCount) }
        nodeCount += width
        index += 1
        generatedIdentifierCount += 1
        return .space(identifierNumber: generatedIdentifierCount, width: width)
    }

    /// `classDef`, `class` or `style`, with what follows it to the end of its line, both trimmed.
    private mutating func styling() throws(MermaidDiagramReadError) -> BlockStatement {
        let statement = kind
        index += 1
        switch statement {
        case .classDefinition:
            let name = try expect(.classDefinitionIdentifier, else: .expectedClassDefinition)
            let declarations = try expect(.classDefinitionStyles, else: .expectedClassDefinition)
            return .texts(.classDefinition, trimmed(name), trimmed(declarations))
        case .classAssignment:
            let identifiers = try expect(.classAssignmentIdentifiers, else: .expectedStyleTarget)
            let className = try expect(.classAssignmentName, else: .expectedStyleTarget)
            return .texts(.classAssignment, trimmed(identifiers), trimmed(className))
        default:
            let identifiers = try expect(.styleIdentifiers, else: .expectedStyleTarget)
            let declarations = try expect(.styleDeclarations, else: .expectedStyleTarget)
            return .texts(.style, trimmed(identifiers), trimmed(declarations))
        }
    }

    /// A block, its size, and its links to the blocks after it: one item per block and per edge, added to the
    /// statements when `keepsItems`, or, for a composite's header, only read and counted. As in Pele, a block that a link
    /// follows keeps no size, and every link counts (Mermaid keeps only the last). The first block and how many items
    /// the statement made.
    private mutating func nodeStatement(keepsItems: Bool) throws(MermaidDiagramReadError) -> (first: BlockDraft, statementCount: Int) {
        var first = try node()
        if kind == .size {
            first.widthInColumns = withText(of: tokens[index]) { digits in BlockSyntaxValues.count(digits) } ?? Int.max
            index += 1
        }
        try countNode()
        guard kind == .link || kind == .startLink else {
            if keepsItems { append(.block(first)) }
            return (first, 1)
        }
        first.widthInColumns = 1
        if keepsItems { append(.block(first)) }
        var statementCount = 1
        var previous = first.identifier
        while kind == .link || kind == .startLink {
            var label = BlockText.empty
            let opensText = kind == .startLink
            index += 1
            if opensText {
                _ = try expect(.linkLabel, else: .expectedQuotedText)
                label = try expect(.string, else: .expectedQuotedText)
                _ = try expect(.link, else: .expectedLink)
            }
            let link = text(of: tokens[index - 1])
            var target = try node()
            target.widthInColumns = 1
            guard edgeCount < limits.maximumEdgeCount else { throw .tooManyEdges(limit: limits.maximumEdgeCount) }
            edgeCount += 1
            try countNode()
            if keepsItems {
                append(.edge(BlockEdgeDraft(source: previous, target: target.identifier, label: label, link: link)))
                append(.block(target))
            }
            statementCount += 2
            previous = target.identifier
        }
        return (first, statementCount)
    }

    /// An identifier, then its shape's brackets around a string, or an arrow's with its directions.
    private mutating func node() throws(MermaidDiagramReadError) -> BlockDraft {
        let identifier = try expect(.nodeIdentifier, else: .expectedBlockIdentifier)
        var draft = BlockDraft(identifier: identifier, label: .empty, hasLabel: false, kind: .unshaped, shapeIndex: 0, directions: .empty,
                               widthInColumns: 1)
        if kind == .nodeStart {
            let opening = tokens[index]
            index += 1
            draft.label = try expect(.string, else: .expectedQuotedText)
            draft.hasLabel = true
            guard kind == .nodeEnd else { throw failure(.expectedClosingBracket) }
            (draft.kind, draft.shapeIndex) = shapeKind(opening: opening, closing: tokens[index])
            index += 1
            return draft
        }
        guard kind == .arrowStart else { return draft }
        let opening = tokens[index]
        index += 1
        draft.label = try expect(.string, else: .expectedQuotedText)
        draft.hasLabel = true
        let firstDirection = texts.count
        texts.append(try expect(.direction, else: .expectedArrowDirection))
        while kind == .direction {
            texts.append(text(of: tokens[index]))
            index += 1
        }
        guard kind == .arrowEnd else { throw failure(.expectedArrowEnd) }
        (draft.kind, draft.shapeIndex) = shapeKind(opening: opening, closing: tokens[index])
        index += 1
        draft.directions = BlockSlice(first: firstDirection, count: texts.count - firstDirection)
        return draft
    }

    /// The kind and shape the brackets of `opening` and `closing` name, Pele's `typeStr2Type`.
    private func shapeKind(opening: BlockToken, closing: BlockToken) -> (BlockKindCode, UInt8) {
        withBytes(of: opening) { opening in withBytes(of: closing) { closing in BlockSyntaxValues.kind(opening: opening, closing: closing) } }
    }

    private mutating func countNode() throws(MermaidDiagramReadError) {
        guard nodeCount < limits.maximumNodeCount else { throw .tooManyNodes(limit: limits.maximumNodeCount) }
        nodeCount += 1
    }

    /// The text of the token of `expected` kind, which is taken; else the error, or the lexer's where it stopped.
    private mutating func expect(_ expected: BlockTokenKind, else problem: BlockSyntaxProblem) throws(MermaidDiagramReadError) -> BlockText {
        guard kind == expected else { throw failure(problem) }
        index += 1
        return text(of: tokens[index - 1])
    }

    /// The run of bytes a token's text is: a token whose text is a literal has none, and is read through `withBytes`.
    private func text(of token: BlockToken) -> BlockText {
        BlockText(start: token.textStart, count: token.textEnd - token.textStart)
    }

    /// `body` over the bytes of a token's text, its literal's for a token whose text is not written.
    private func withBytes<Result>(of token: BlockToken, _ body: (UnsafeBufferPointer<UInt8>) -> Result) -> Result {
        if let literal = token.literal.text { return literal.withUTF8Buffer(body) }
        return source.bytes.withUnsafeBufferPointer { buffer in body(UnsafeBufferPointer(rebasing: buffer[token.textStart..<token.textEnd])) }
    }

    /// `body` over a token's text as a String: a count's digits.
    private func withText<Result>(of token: BlockToken, _ body: (String) -> Result) -> Result {
        withBytes(of: token) { bytes in body(String(decoding: bytes, as: UTF8.self)) }
    }

    private func trimmed(_ text: BlockText) -> BlockText {
        BlockBytes.trimmed(text, in: source.bytes)
    }

    /// The error at the current token: the lexer's where it stopped, else `problem`, on the token's line.
    private func failure(_ problem: BlockSyntaxProblem) -> MermaidDiagramReadError {
        let start = tokens[index].start
        let line = source.line(of: start)
        if kind == .unrecognized { return .invalidSyntax(line: line, problem: .unexpectedText(PlaneMapByte.excerpt(at: start, in: source.bytes))) }
        return .invalidSyntax(line: line, problem: .block(problem))
    }
}

/// A composite open while its statements are read: where they start in the parser's open places, its header, and
/// whether that header was a link statement.
struct BlockOpenComposite: BitwiseCopyable {
    let placesStart: Int
    let header: BlockDraft?
    let headerWasLinks: Bool
}
