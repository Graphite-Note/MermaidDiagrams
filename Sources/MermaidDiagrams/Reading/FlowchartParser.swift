/**
 * File: FlowchartParser.swift
 * ---------------------------
 * Layer: Core
 * Description: Reads a flowchart's statements after its keyword.
 *
 * Authors: Félix Chevalier, Bahey Shalash
 * Version: 0.6
 * Date: 23/11/2026
 */

/// Reads a flowchart's statements after its `flowchart` or `graph` keyword: the direction, then chains of nodes and
/// links (`A & B --> C -->|yes| D`), groups (`subgraph … end`), accessibility text, and the statements that style the
/// diagram (`FlowchartStyleSyntax`); a `click` is counted and left. Statements end at a line break or a semicolon; `%%`
/// starts a comment.
struct FlowchartParser {
    private var cursor: MermaidTextCursor
    private var builder: FlowchartDiagramBuilder
    /// The cursor's text as Pele's lexer tests it, made once.
    private let lexerText: FlowchartLexerText
    /// The node groups of a chain that is being read, kept from chain to chain so that a group allocates no list.
    private var groupLists: (first: [Int], second: [Int]) = ([], [])

    /// Reads the flowchart whose keyword ends at the cursor.
    static func parse(_ cursor: MermaidTextCursor, limits: MermaidDiagramLimits) throws(MermaidDiagramReadError) -> FlowchartDiagram {
        var parser = FlowchartParser(cursor: cursor,
                                     builder: FlowchartDiagramBuilder(limits: limits, expectedNodeCount: lineCount(of: cursor.bytes, from: cursor.position) + 1),
                                     lexerText: FlowchartLexerText(bytes: cursor.bytes))
        try parser.readDirection()
        try parser.readStatements()
        return parser.builder.finishedDiagram()
    }

    /// How many line feeds the text holds from `start`: about as many statements as it has, which the node and edge
    /// lists are made for.
    private static func lineCount(of bytes: [UInt8], from start: Int) -> Int {
        var count = 0
        var index = start
        while let lineBreak = MermaidPreprocessing.firstIndex(of: MermaidByte.newline, in: bytes, from: index) {
            count += 1
            index = lineBreak + 1
        }
        return count
    }

    private mutating func readDirection() throws(MermaidDiagramReadError) {
        cursor.skipSpaces()
        guard let byte = cursor.peek(), !MermaidByte.endsStatement(byte), !cursor.hasPrefix(Self.commentStart) else { return }
        let start = cursor.position
        if MermaidByte.isLetter(byte) { _ = cursor.readWord() } else { cursor.advance() }
        let keyword = cursor.text(from: start, to: cursor.position)
        guard let direction = FlowchartDirection(keyword: keyword) else {
            throw .invalidSyntax(line: cursor.line, problem: .unknownDirection(keyword))
        }
        builder.setDirection(direction)
        try expectStatementEnd()
    }

    private mutating func readStatements() throws(MermaidDiagramReadError) {
        while true {
            cursor.skipWhitespace()
            while cursor.peek() == MermaidByte.semicolon {
                cursor.advance()
                cursor.skipWhitespace()
            }
            if cursor.isAtEnd { break }
            if cursor.hasPrefix(Self.commentStart) {
                cursor.skipToEndOfLine()
                continue
            }
            if try readKeywordStatement() { continue }
            try readChain()
            try expectStatementEnd()
        }
        if let identifier = builder.innermostOpenSubgraphIdentifier {
            throw .invalidSyntax(line: cursor.line, problem: .unclosedSubgraph(identifier: identifier))
        }
    }

    /// Reads a statement that starts with a keyword, and returns whether there was one. A word is a keyword only when
    /// a space, a colon, a brace or the statement's end follows it, so that `classes --> B` is a chain.
    private mutating func readKeywordStatement() throws(MermaidDiagramReadError) -> Bool {
        let wordEnd = cursor.endOfLetters()
        guard let keyword = keyword(from: cursor.position, to: wordEnd) else { return false }
        if wordEnd < cursor.bytes.count, case let next = cursor.bytes[wordEnd], !MermaidByte.isSpace(next), !MermaidByte.endsStatement(next),
           next != MermaidByte.colon, next != MermaidByte.openingBrace { return false }
        let statementLine = cursor.line
        cursor.advance(by: wordEnd - cursor.position)
        switch keyword {
        case .subgraph: readSubgraphOpening()
        case .end:
            guard builder.closeSubgraph() else { throw .invalidSyntax(line: statementLine, problem: .endWithoutSubgraph) }
            try expectStatementEnd()
        case .accessibilityTitle: builder.setAccessibilityTitle(readAccessibilityLine())
        case .accessibilityDescription: builder.setAccessibilityDescription(try readAccessibilityDescription())
        case .direction: readDirectionStatement()
        case .classDefinition, .classWord, .style, .linkStyle:
            let word = keyword.word
            let statementStart = cursor.position
            skipStatement()
            guard FlowchartStyleGrammar.isReadByPele(keyword: word, in: lexerText, from: statementStart, to: cursor.position) else {
                throw .invalidSyntax(line: statementLine, problem: .unexpectedText(cursor.trimmedText(from: statementStart, to: cursor.position)))
            }
            builder.apply(FlowchartStyleSyntax.statement(keyword: word, text: cursor.trimmedText(from: statementStart, to: cursor.position)))
        case .click:
            skipStatement()
            builder.countUnappliedStatement()
        }
        return true
    }

    /// The keyword written from `start` to `end`, compared byte by byte, or nil.
    private func keyword(from start: Int, to end: Int) -> FlowchartKeyword? {
        guard end > start else { return nil }
        func written(_ keyword: FlowchartKeyword) -> FlowchartKeyword? {
            cursor.bytes(from: start, to: end, equal: keyword.bytes) ? keyword : nil
        }
        switch cursor.bytes[start] {
        case UInt8(ascii: "s"): return written(.subgraph) ?? written(.style)
        case UInt8(ascii: "e"): return written(.end)
        case UInt8(ascii: "d"): return written(.direction)
        case UInt8(ascii: "c"): return written(.classDefinition) ?? written(.classWord) ?? written(.click)
        case UInt8(ascii: "l"): return written(.linkStyle)
        case UInt8(ascii: "a"): return written(.accessibilityTitle) ?? written(.accessibilityDescription)
        default: return nil
        }
    }

    /// `A & B --> C -->|text| D`: node groups joined by links, each link making an edge from every node before it to
    /// every node after it.
    private mutating func readChain() throws(MermaidDiagramReadError) {
        // The two lists move out of the parser while the chain is read, and back when it ends.
        var previousGroup = groupLists.first
        var nextGroup = groupLists.second
        groupLists = ([], [])
        defer { groupLists = (previousGroup, nextGroup) }
        guard try readNodeGroup(into: &previousGroup) else { return }
        while true {
            cursor.skipSpaces()
            guard let link = try FlowchartLinkSyntax.readLink(&cursor, in: lexerText) else { return }
            if let identifier = link.identifier { builder.recordEdgeIdentifier(identifier) }
            cursor.skipSpaces()
            guard try readNodeGroup(into: &nextGroup) else { throw .invalidSyntax(line: cursor.line, problem: .expectedNode) }
            try builder.addEdges(from: previousGroup, to: nextGroup, link: link)
            swap(&previousGroup, &nextGroup)
        }
    }

    /// `A & B & C`: the indexes of the nodes put in `indices`, and false for an edge's attributes (`e1@{ … }`), which
    /// name no node. As in Pele's `node`, the `&` has spaces on both sides: written against a node it is part of the
    /// identifier, and after a shape (`A[x]&B`) or before a node (`A &B`) the statement is refused.
    private mutating func readNodeGroup(into indices: inout [Int]) throws(MermaidDiagramReadError) -> Bool {
        indices.removeAll(keepingCapacity: true)
        while true {
            guard let index = try readNode() else { return !indices.isEmpty }
            indices.append(index)
            let nodeEnd = cursor.mark
            let nodeEndPosition = cursor.position
            cursor.skipSpaces()
            guard cursor.position > nodeEndPosition, cursor.peek() == MermaidByte.ampersand else {
                cursor.move(to: nodeEnd)
                return true
            }
            cursor.advance()
            guard let next = cursor.peek(), MermaidByte.isSpace(next) else {
                throw .invalidSyntax(line: cursor.line, problem: .unexpectedText(cursor.excerpt()))
            }
            cursor.skipSpaces()
        }
    }

    /// A node: its identifier, then its shape and text or its attributes, then any `:::class`, then any attributes.
    private mutating func readNode() throws(MermaidDiagramReadError) -> Int? {
        let line = cursor.line
        let identifierStart = cursor.position
        let identifierEnd = FlowchartIdentifierSyntax.endOfIdentifier(in: lexerText, from: identifierStart)
        guard identifierEnd > identifierStart else {
            throw .invalidSyntax(line: line, problem: cursor.isAtEnd ? .expectedNode : .unexpectedText(cursor.excerpt()))
        }
        cursor.advance(by: identifierEnd - identifierStart)
        if FlowchartNodeSyntax.isAtAttributes(cursor), builder.hasEdgeIdentifiers,
           builder.isEdgeIdentifier(cursor.text(from: identifierStart, to: identifierEnd)) {
            _ = try FlowchartNodeSyntax.readAttributes(&cursor)
            builder.countUnappliedStatement()
            return nil
        }
        let (index, isNew) = try builder.nodeIndex(forIdentifierIn: cursor.bytes, from: identifierStart, to: identifierEnd)
        if FlowchartNodeSyntax.isAtAttributes(cursor) {
            let definition = try FlowchartNodeSyntax.readAttributes(&cursor)
            if isNew, definition.label == nil { builder.giveIdentifierAsLabel(toNodeAt: index) }
            builder.define(nodeAt: index, as: definition)
        } else if !isNew, let length = builder.lengthOfShapeWrittenAgain(forNodeAt: index, in: cursor.bytes, at: cursor.position) {
            // The same brackets and text as the node's shape was last written with read the same, which the node has.
            cursor.advance(by: length)
        } else {
            let shapeStart = cursor.position
            let definition = try FlowchartNodeSyntax.readShape(&cursor)
            // A new node shows the text it is written with, or else its identifier.
            if isNew, definition?.label == nil { builder.giveIdentifierAsLabel(toNodeAt: index) }
            if let definition { builder.define(nodeAt: index, asShapeWrittenFrom: shapeStart, to: cursor.position, definition) }
        }
        while cursor.hasPrefix(Self.classMarker) {
            cursor.advance(by: Self.classMarker.count)
            if let className = FlowchartIdentifierSyntax.readIdentifier(&cursor, in: lexerText) { builder.assignClass(className, toNodeAt: index) } else { builder.countUnappliedStatement() }
        }
        // Attributes may also follow a shape in brackets and its classes (`C[Hello]@{ shape: circle }`), as Pele reads them.
        if FlowchartNodeSyntax.isAtAttributes(cursor) { builder.define(nodeAt: index, as: try FlowchartNodeSyntax.readAttributes(&cursor)) }
        return index
    }

    /// `subgraph id[title]`, `subgraph id ["title"]`, `subgraph "title"` or `subgraph title words`; words end at the
    /// line's end or a semicolon outside quotation marks, as statements do.
    private mutating func readSubgraphOpening() {
        cursor.skipSpaces()
        var lookahead = cursor
        if let identifier = lookahead.readIdentifier() {
            lookahead.skipSpaces()
            if lookahead.peek() == MermaidByte.openingBracket, let title = Self.bracketedTitle(&lookahead) {
                cursor = lookahead
                builder.openSubgraph(identifier: identifier, title: title)
                return
            }
        }
        let wordsStart = cursor.position
        skipStatement()
        let written = FlowchartTextSyntax.unquoted(cursor.trimmedText(from: wordsStart, to: cursor.position))
        let title = DiagramLabelDecoder.label(from: written.text, form: written.form)
        // Pele's header text runs to the statement's end, spaces included, and names no group when it holds a space
        // (flowchart/db.ts `addSubGraph`): `subgraph myTitle   ` is titled `myTitle` and named `subGraph0`.
        var wordsEnd = cursor.position
        if wordsEnd > wordsStart, cursor.bytes[wordsEnd - 1] == MermaidByte.carriageReturn { wordsEnd -= 1 }
        let endsWithSpace = wordsEnd > wordsStart && MermaidByte.isWhitespace(cursor.bytes[wordsEnd - 1])
        let isOneWord = !written.text.isEmpty && !written.text.contains(where: \.isWhitespace) && !endsWithSpace
        builder.openSubgraph(identifier: isOneWord ? written.text : nil, title: title)
    }

    /// `direction TB` (or `TD`, `BT`, `LR`, `RL`) inside a group sets the group's direction, and the rest of the line
    /// is not read, as in Mermaid. Outside a group, or naming no direction, the statement is counted and left.
    private mutating func readDirectionStatement() {
        var lookahead = cursor
        lookahead.skipSpaces()
        if builder.hasOpenSubgraph, let word = lookahead.readWord(), let direction = Self.subgraphDirections[word] {
            builder.setInnermostSubgraphDirection(direction)
            cursor = lookahead
            cursor.skipToEndOfLine()
            return
        }
        skipStatement()
        builder.countUnappliedStatement()
    }

    /// `[title]` after a group's identifier, or nil when the brackets do not close: the line is then read as words.
    private static func bracketedTitle(_ cursor: inout MermaidTextCursor) -> DiagramLabel? {
        cursor.advance()
        let closings = [[MermaidByte.closingBracket]]
        let title = try? FlowchartTextSyntax.readText(&cursor, closedByAnyOf: closings, openingLine: cursor.line) // Unclosed: read as words.
        return title?.0
    }

    /// `accTitle: text`, to the end of the line.
    private mutating func readAccessibilityLine() -> String {
        cursor.skipSpaces()
        if cursor.peek() == MermaidByte.colon { cursor.advance() }
        cursor.skipSpaces()
        return DiagramLabelDecoder.decodingEntities(cursor.readRestOfLine())
    }

    /// `accDescr: text` or `accDescr { lines }`.
    private mutating func readAccessibilityDescription() throws(MermaidDiagramReadError) -> String {
        cursor.skipSpaces()
        guard cursor.peek() == MermaidByte.openingBrace else { return readAccessibilityLine() }
        let openingLine = cursor.line
        cursor.advance()
        let start = cursor.position
        while let byte = cursor.peek(), byte != MermaidByte.closingBrace { cursor.advance() }
        guard !cursor.isAtEnd else { throw .invalidSyntax(line: openingLine, problem: .unclosedAccessibilityDescription) }
        let description = cursor.text(from: start, to: cursor.position)
        cursor.advance()
        return DiagramLabelDecoder.label(from: description, form: .plain).lines.filter { line in !line.isEmpty }.joined(separator: " ")
    }

    /// Moves to the end of a statement that is not read: the next line break, or semicolon outside quotation marks.
    private mutating func skipStatement() {
        var isInsideQuotation = false
        while let byte = cursor.peek(), byte != MermaidByte.newline {
            if byte == MermaidByte.quotationMark { isInsideQuotation.toggle() }
            if byte == MermaidByte.semicolon, !isInsideQuotation { return }
            cursor.advance()
        }
    }

    /// A statement ends at a line break, a semicolon, a comment or the end of the text; anything else is an error.
    private mutating func expectStatementEnd() throws(MermaidDiagramReadError) {
        cursor.skipSpaces()
        guard let byte = cursor.peek(), !MermaidByte.endsStatement(byte) else { return }
        if cursor.hasPrefix(Self.commentStart) {
            cursor.skipToEndOfLine()
            return
        }
        throw .invalidSyntax(line: cursor.line, problem: .unexpectedText(cursor.excerpt()))
    }

    private static let commentStart = Array("%%".utf8)
    private static let classMarker = Array(":::".utf8)
    /// The words `direction` takes inside a group: Mermaid's, upper case only.
    private static let subgraphDirections: [String: FlowchartDirection] = ["TB": .topToBottom, "TD": .topToBottom, "BT": .bottomToTop,
                                                                           "LR": .leftToRight, "RL": .rightToLeft]
}

/// The words that start a flowchart statement of their own.
private enum FlowchartKeyword {
    case subgraph
    case end
    case direction
    case classDefinition
    case classWord
    case style
    case linkStyle
    case click
    case accessibilityTitle
    case accessibilityDescription

    /// The word as written.
    var word: String {
        switch self {
        case .subgraph: "subgraph"
        case .end: "end"
        case .direction: "direction"
        case .classDefinition: "classDef"
        case .classWord: "class"
        case .style: "style"
        case .linkStyle: "linkStyle"
        case .click: "click"
        case .accessibilityTitle: "accTitle"
        case .accessibilityDescription: "accDescr"
        }
    }

    /// The word's UTF-8 bytes.
    var bytes: [UInt8] {
        switch self {
        case .subgraph: Self.subgraphBytes
        case .end: Self.endBytes
        case .direction: Self.directionBytes
        case .classDefinition: Self.classDefinitionBytes
        case .classWord: Self.classBytes
        case .style: Self.styleBytes
        case .linkStyle: Self.linkStyleBytes
        case .click: Self.clickBytes
        case .accessibilityTitle: Self.accessibilityTitleBytes
        case .accessibilityDescription: Self.accessibilityDescriptionBytes
        }
    }

    private static let subgraphBytes = Array("subgraph".utf8)
    private static let endBytes = Array("end".utf8)
    private static let directionBytes = Array("direction".utf8)
    private static let classDefinitionBytes = Array("classDef".utf8)
    private static let classBytes = Array("class".utf8)
    private static let styleBytes = Array("style".utf8)
    private static let linkStyleBytes = Array("linkStyle".utf8)
    private static let clickBytes = Array("click".utf8)
    private static let accessibilityTitleBytes = Array("accTitle".utf8)
    private static let accessibilityDescriptionBytes = Array("accDescr".utf8)
}
