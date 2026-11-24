/**
 * File: AgentFlowParser.swift
 * ---------------------------
 * Layer: Core
 * Description: Reads an agent flow (`agentflow-beta`) as Pele's parser.ts does: the text prepared as Pele prepares it,
 *              the header and its direction, then the document's statements, and Jison's errors with their lines.
 *
 * Authors: Bahey Shalash
 * Version: 0.5
 * Date: 23/11/2026
 */

/// Reads an agent flow token by token as Pele's hand-written port of Mermaid's agentflow.jison does: blocks nest without
/// recursion, each statement goes to `AgentFlowDiagramBuilder` as Mermaid's grammar actions call its database, and an
/// unexpected token fails with Jison's name for it and what was expected, on its line.
struct AgentFlowParser {
    let units: [UInt16]
    let tokens: AgentFlowTokens
    var index = 0
    var builder: AgentFlowDiagramBuilder
    /// The metadata body read last, and the tokens it spans.
    var pendingMetadata: String?
    var metadataFrom = 0
    var metadataTo = 0

    static func parse(_ cursor: MermaidTextCursor, keyword: String, limits: MermaidDiagramLimits) throws(MermaidDiagramReadError) -> AgentFlowDiagram {
        let keywordStart = cursor.position - keyword.utf8.count
        var lineStart = keywordStart
        while lineStart > 0, cursor.bytes[lineStart - 1] != MermaidByte.newline { lineStart -= 1 }
        let units = AgentFlowPreparedText.units(of: cursor.bytes[lineStart...])
        var parser = AgentFlowParser(units: units, builder: AgentFlowDiagramBuilder(limits: limits, lineOffset: cursor.line - 1))
        try parser.readDiagram()
        parser.builder.diagram.options = AgentFlowOptions(MermaidConfigurationOptions(section: "agentflow", in: cursor))
        parser.builder.buildGraph()
        return parser.builder.diagram
    }

    private init(units: [UInt16], builder: AgentFlowDiagramBuilder) {
        self.units = units
        tokens = AgentFlowLexer.tokens(of: units)
        self.builder = builder
        self.builder.reserveRoom(forTokenCount: tokens.count)
    }

    var current: AgentFlowTokenKind { index < tokens.count ? tokens.kinds[index] : .end }

    func kind(at position: Int) -> AgentFlowTokenKind { position < tokens.count ? tokens.kinds[position] : .end }

    func text(at position: Int) -> String { tokens.text(at: position, in: units) }

    /// `agentflow-beta`, its direction or a line break, then the document to its end.
    private mutating func readDiagram() throws(MermaidDiagramReadError) {
        while current == .space || current == .newline || current == .comment { index += 1 }
        _ = try expect(.graph, also: "'SPACE', 'NEWLINE', 'COMMENT'")
        if current == .noDirection {
            index += 1
            builder.setDirection("TB")
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

    mutating func expect(_ kind: AgentFlowTokenKind, also: String = "") throws(MermaidDiagramReadError) -> String {
        guard current == kind else { throw failure(expecting: "'\(kind.grammarName)'" + (also.isEmpty ? "" : ", " + also)) }
        index += 1
        return text(at: index - 1)
    }

    mutating func separator() throws(MermaidDiagramReadError) {
        guard Self.separators.contains(current) else { throw failure(expecting: Self.separatorNames) }
        index += 1
    }

    /// Tokens of `kinds` run together: an identifier, or what follows `interpolate`.
    mutating func joined(_ kinds: AgentFlowTokenKindSet) throws(MermaidDiagramReadError) -> String {
        guard kinds.contains(current) else { throw failure(expecting: "'NODE_STRING'") }
        let first = index
        index += 1
        while kinds.contains(current) { index += 1 }
        return joinedText(from: first, to: index)
    }

    /// The texts of the tokens from `first` up to `end` run together: one slice of the code units when the tokens follow
    /// one another with their own texts and no token ends between the two halves of a surrogate pair (each token's
    /// text is decoded alone, a half alone made U+FFFD); else each token's text joined.
    func joinedText(from first: Int, to end: Int) -> String {
        guard end - first > 1 else { return text(at: first) }
        var isOneSlice = tokens.replacedTexts.isEmpty
        var position = first + 1
        while isOneSlice, position < end {
            let boundary = tokens.starts[position]
            isOneSlice = boundary == tokens.ends[position - 1] && !(boundary > 0 && UTF16.isLeadSurrogate(units[boundary - 1]))
            position += 1
        }
        guard isOneSlice else {
            var joined = text(at: first)
            for position in (first + 1)..<end { joined += text(at: position) }
            return joined
        }
        return UnicodeScalarText.string(utf16: units[tokens.starts[first]..<tokens.ends[end - 1]])
    }

    mutating func identifier() throws(MermaidDiagramReadError) -> String { try joined(Self.identifierTokens) }

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
        return AgentFlowText(text: joinedText(from: first, to: index), type: type)
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
        return AgentFlowText(text: joinedText(from: first, to: index), type: type)
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
        return AgentFlowText(text: joinedText(from: first, to: index), type: type)
    }

    /// A metadata block's body: its tokens' texts run together.
    mutating func shapeData() -> String {
        metadataFrom = index
        var body = text(at: index)
        index += 1
        while current == .shapeData {
            body += text(at: index)
            index += 1
        }
        metadataTo = index - 1
        return body
    }

    func span(from first: Int, to last: Int) -> AgentFlowSourceSpan { tokens.span(from: first, to: last) }
}
