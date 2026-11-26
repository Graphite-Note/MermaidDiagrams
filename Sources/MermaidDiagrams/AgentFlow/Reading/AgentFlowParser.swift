/**
 * File: AgentFlowParser.swift
 * ---------------------------
 * Layer: Core
 * Description: Reads an agent flow (`agentflow-beta`) as Pele's parser.ts does: the text prepared as Pele prepares it,
 *              the header and its direction, then the document's statements, and Jison's errors with their lines,
 *              each text a range of the prepared text's bytes.
 *
 * Authors: Bahey Shalash
 * Version: 0.6
 * Date: 26/11/2026
 */

/// Reads an agent flow token by token as Pele's hand-written port of Mermaid's agentflow.jison does: blocks nest without
/// recursion, each statement goes to `AgentFlowDiagramBuilder` as Mermaid's grammar actions call its database, and an
/// unexpected token fails with Jison's name for it and what was expected, on its line. A token's text is a range of
/// the bytes; texts run together from tokens that do not follow one another are made after them.
struct AgentFlowParser {
    let tokens: AgentFlowTokens
    var index = 0
    var builder: AgentFlowDiagramBuilder
    /// The metadata body read last, and the tokens it spans.
    var pendingMetadata: MermaidTextRange?
    var metadataFrom = 0
    var metadataTo = 0
    /// What the open blocks' statements gave them, each block's from where it opened (`Frame.itemsStart`).
    var items: ScratchList<AgentFlowDocumentItem>
    /// The nodes of the vertex statement being read, group after group.
    var statementNodes: ScratchList<AgentFlowNamedText>
    /// Where each group of the vertex statement being read starts among its nodes.
    var groupStarts: ScratchList<Int>

    static func parse(_ cursor: MermaidTextCursor, keyword: String, limits: MermaidDiagramLimits) throws(MermaidDiagramReadError) -> AgentFlowDiagram {
        let keywordStart = cursor.position - keyword.utf8.count
        var lineStart = keywordStart
        while lineStart > 0, cursor.bytes[lineStart - 1] != MermaidByte.newline { lineStart -= 1 }
        let (bytes, isASCII) = AgentFlowPreparedText.bytes(of: cursor.bytes[lineStart...])
        let lineOffset = cursor.line - 1
        // The tokens and every list the reading needs only while it runs are in the thread's scratch arena.
        let read = DiagramScratchArena.withCurrentThread { arena in
            Result { () throws(MermaidDiagramReadError) in
                let lexed = AgentFlowLexer.tokens(of: bytes, isASCII: isASCII, arena: arena)
                let text = AgentFlowTextBytes(prepared: bytes, derived: lexed.derived, isASCII: isASCII)
                let builder = AgentFlowDiagramBuilder(text: text, limits: limits, lineOffset: lineOffset, arena: arena)
                var parser = AgentFlowParser(tokens: lexed.tokens, builder: builder, arena: arena)
                try parser.readDiagram()
                parser.builder.buildGraph()
                return parser.builder.model
            }
        }
        return AgentFlowDiagram(model: try read.get(), options: AgentFlowOptions(MermaidConfigurationOptions(section: "agentflow", in: cursor)))
    }

    private init(tokens: AgentFlowTokens, builder: AgentFlowDiagramBuilder, arena: DiagramScratchArena) {
        self.tokens = tokens
        self.builder = builder
        self.builder.reserveRoom(forTokenCount: tokens.count)
        items = arena.list(capacity: 32)
        statementNodes = arena.list(capacity: 16)
        groupStarts = arena.list(capacity: 8)
    }

    var preparedCount: Int { builder.model.text.preparedCount }

    var current: AgentFlowTokenKind { index < tokens.count ? tokens.kind(at: index) : .end }

    func kind(at position: Int) -> AgentFlowTokenKind { position < tokens.count ? tokens.kind(at: position) : .end }

    func text(at position: Int) -> MermaidTextRange { tokens.textRange(at: position) }

    /// `agentflow-beta`, its direction or a line break, then the document to its end.
    private mutating func readDiagram() throws(MermaidDiagramReadError) {
        while current == .space || current == .newline || current == .comment { index += 1 }
        _ = try expect(.graph, also: "'SPACE', 'NEWLINE', 'COMMENT'")
        if current == .noDirection {
            index += 1
            builder.setDirection(builder.constant(.topToBottom))
        } else {
            let direction = try expect(.direction, also: "'NODIR'")
            if current == .space {
                while current == .space { index += 1 }
                if current != .newline { throw failure(expecting: "'NEWLINE', 'SPACE'") }
            } else if current != .semicolon, current != .newline, current != .comment {
                throw failure(expecting: "'COMMENT', 'SEMI', 'NEWLINE', 'SPACE'")
            }
            index += 1
            builder.setDirection(direction)
        }
        try readDocument()
        if current != .end { throw failure(expecting: Self.statementStart) }
    }

    // MARK: - Tokens

    mutating func expect(_ kind: AgentFlowTokenKind, also: String = "") throws(MermaidDiagramReadError) -> MermaidTextRange {
        guard current == kind else { throw failure(expecting: "'\(kind.grammarName)'" + (also.isEmpty ? "" : ", " + also)) }
        index += 1
        return text(at: index - 1)
    }

    mutating func separator() throws(MermaidDiagramReadError) {
        guard Self.separators.contains(current) else { throw failure(expecting: Self.separatorNames) }
        index += 1
    }

    /// Tokens of `kinds` run together: an identifier, or what follows `interpolate`.
    mutating func joined(_ kinds: AgentFlowTokenKindSet) throws(MermaidDiagramReadError) -> MermaidTextRange {
        guard kinds.contains(current) else { throw failure(expecting: "'NODE_STRING'") }
        let first = index
        index += 1
        while kinds.contains(current) { index += 1 }
        return joinedText(from: first, to: index)
    }

    /// The texts of the tokens from `first` up to `end` run together: one range when they follow one another in the
    /// bytes (an empty text, the `@{` that opens metadata, adds nothing), else their texts made after the bytes.
    mutating func joinedText(from first: Int, to end: Int) -> MermaidTextRange {
        var joined = text(at: first)
        var position = first + 1
        while position < end {
            let next = text(at: position)
            if next.isEmpty {
                position += 1
                continue
            }
            if joined.isEmpty { joined = next } else if next.start == joined.end { joined.end = next.end } else { break }
            position += 1
        }
        guard position < end else { return joined }
        let start = builder.model.text.bytes.count
        for piece in first..<end {
            let range = text(at: piece)
            builder.model.text.appendCopy(of: range)
        }
        return MermaidTextRange(start: start, end: builder.model.text.bytes.count)
    }

    mutating func identifier() throws(MermaidDiagramReadError) -> MermaidTextRange { try joined(Self.identifierTokens) }

    /// A node's text: a string, a Markdown string, or text and tags run together.
    mutating func nodeText() throws(MermaidDiagramReadError) -> AgentFlowText {
        let type: AgentFlowLabelType
        switch current {
        case .string: type = .string
        case .markdownString: type = .markdown
        case .text, .tagStart, .tagEnd, .unicodeText: type = .text
        default: throw failure(expecting: Self.textTokens + ", 'TAGEND', 'STR', 'MD_STR'")
        }
        let first = index
        index += 1
        while Self.nodeTextTokens.contains(current) { index += 1 }
        return AgentFlowText(range: joinedText(from: first, to: index), type: type)
    }

    mutating func close(_ kind: AgentFlowTokenKind) throws(MermaidDiagramReadError) {
        _ = try expect(kind, also: Self.textTokens)
    }

    /// An edge's text after `--`.
    mutating func edgeText() throws(MermaidDiagramReadError) -> AgentFlowText {
        let type: AgentFlowLabelType
        switch current {
        case .string: type = .string
        case .markdownString: type = .markdown
        case .edgeText, .unicodeText: type = .text
        default: throw failure(expecting: "'EDGE_TEXT', 'STR', 'MD_STR'")
        }
        let first = index
        index += 1
        while current == .edgeText || current == .unicodeText { index += 1 }
        return AgentFlowText(range: joinedText(from: first, to: index), type: type)
    }

    /// A flow's or a connector's identifier: words and punctuation without tags, or a string, which is text.
    mutating func textWithoutTags() throws(MermaidDiagramReadError) -> AgentFlowText {
        let type: AgentFlowLabelType
        if current == .string { type = .text } else if current == .markdownString { type = .markdown } else if Self.textWithoutTagsTokens.contains(current) {
            type = .text
        } else {
            throw failure(expecting: "'NODE_STRING', 'STR', 'MD_STR'")
        }
        let first = index
        index += 1
        while Self.textWithoutTagsTokens.contains(current) { index += 1 }
        return AgentFlowText(range: joinedText(from: first, to: index), type: type)
    }

    /// A metadata block's body: its tokens' texts run together.
    mutating func shapeData() -> MermaidTextRange {
        metadataFrom = index
        index += 1
        while current == .shapeData { index += 1 }
        metadataTo = index - 1
        return joinedText(from: metadataFrom, to: index)
    }

    func span(from first: Int, to last: Int) -> AgentFlowSourceSpan { tokens.span(from: first, to: last) }
}
