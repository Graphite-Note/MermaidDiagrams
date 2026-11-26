/**
 * File: AgentFlowParserStatements.swift
 * -------------------------------------
 * Layer: Core
 * Description: An agent flow's statements as Pele's parser.ts reads them: styles, link styles, classes, clicks,
 *              connectors, directions, accessibility text, and the document's blocks nested without recursion.
 *
 * Authors: Bahey Shalash
 * Version: 0.2
 * Date: 26/11/2026
 */

extension AgentFlowParser {
    /// An open `flow` or `global` block: where its keyword is, its identifier, title and metadata, where its items start
    /// among the parser's, and whether the block around it collects.
    struct Frame {
        var isGlobal: Bool
        var keywordIndex: Int
        var identifier: AgentFlowText?
        var title: AgentFlowText?
        var metadata: MermaidTextRange?
        var metadataFrom = 0
        var metadataTo = 0
        var itemsStart = 0
        var collects = false
    }

    /// The statements to the end, `flow` and `global` blocks kept on a stack of their own, their items on one list.
    mutating func readDocument() throws(MermaidDiagramReadError) {
        var open: [Frame] = []
        var collects = false
        while true {
            let kind = current
            if kind == .end { break }
            switch kind {
            case .endKeyword:
                guard let frame = open.popLast() else { return }
                let closed = try close(frame)
                while items.count > frame.itemsStart { _ = items.removeLast() }
                collects = frame.collects
                if collects, let closed { items.append(AgentFlowDocumentItem(isDirection: false, text: closed)) }
            case .semicolon, .newline, .space, .endOfFile: index += 1
            case .comment: index += 1
            case .flow, .global:
                var frame = try openFrame(isGlobal: kind == .global)
                frame.itemsStart = items.count
                frame.collects = collects
                open.append(frame)
                collects = true
            default:
                try statement(collects: collects)
            }
        }
        if !open.isEmpty { throw failure(expecting: "'end'") }
    }

    /// The `end` of a block: a `global` block's nodes kept out of flows, or the flow made, its identifier returned.
    private mutating func close(_ frame: Frame) throws(MermaidDiagramReadError) -> AgentFlowNamedText? {
        let endIndex = index
        index += 1
        guard !frame.isGlobal else {
            builder.addGlobal(items.elements.part(frame.itemsStart..<items.count))
            return nil
        }
        let identifier = try builder.addFlow(identifier: frame.identifier, items: items.elements.part(frame.itemsStart..<items.count), title: frame.title)
        try attachBlockMetadata(frame, to: identifier.range)
        builder.addBlockMapping(frame.identifier?.range ?? .empty, kind: .subgraph, start: span(from: frame.keywordIndex, to: frame.keywordIndex),
                                end: span(from: endIndex, to: endIndex))
        return identifier
    }

    /// `flow` or `global` up to its separator.
    private mutating func openFrame(isGlobal: Bool) throws(MermaidDiagramReadError) -> Frame {
        let keywordIndex = index
        index += 1
        if isGlobal || Self.separators.contains(current) {
            try separator()
            return Frame(isGlobal: isGlobal, keywordIndex: keywordIndex)
        }
        let frame = try header(keywordIndex: keywordIndex)
        index += 1
        return frame
    }

    /// The header of a `flow` or a `connector`: white space, its identifier, an optional bracketed title and metadata,
    /// then a separator, which is left for the caller.
    private mutating func header(keywordIndex: Int) throws(MermaidDiagramReadError) -> Frame {
        _ = try expect(.space, also: Self.separatorNames)
        let identifier = try textWithoutTags()
        var title = AgentFlowText(range: .empty, type: .text)
        if current == .squareStart {
            index += 1
            title = try nodeText()
            try close(.squareEnd)
        }
        let metadata = current == .shapeData ? shapeData() : nil
        guard Self.separators.contains(current) else { throw failure(expecting: Self.separatorNames + ", 'SHAPE_DATA'") }
        return Frame(isGlobal: false, keywordIndex: keywordIndex, identifier: identifier, title: title, metadata: metadata,
                     metadataFrom: metadataFrom, metadataTo: metadataTo)
    }

    private mutating func attachBlockMetadata(_ frame: Frame, to identifier: MermaidTextRange) throws(MermaidDiagramReadError) {
        guard let metadata = frame.metadata else { return }
        try builder.addVertex(identifier, metadata: metadata, metadataSpan: span(from: frame.metadataFrom, to: frame.metadataTo))
    }

    /// One statement, and what it gives the block around it when the block collects: the nodes it names, a connector's
    /// identifier, an accessibility text or a direction.
    private mutating func statement(collects: Bool) throws(MermaidDiagramReadError) {
        let kind = current
        switch kind {
        case .style:
            index += 1
            _ = try expect(.space)
            let identifier = try identifier()
            _ = try expect(.space)
            try builder.addVertex(identifier, styles: try styles())
            try separator()
        case .linkStyle:
            try linkStyleStatement()
            try separator()
        case .classDefinition, .classKeyword:
            try classStatement(isDefinition: kind == .classDefinition)
        case .click:
            try clickStatement()
            try separator()
        case .connector:
            let identifier = try connectorStatement()
            if collects { collect(identifier) }
        case .directionTopToBottom, .directionBottomToTop, .directionRightToLeft, .directionLeftToRight, .directionTopDown:
            index += 1
            let direction = Self.directionTexts[Int(kind.rawValue - AgentFlowTokenKind.directionTopToBottom.rawValue)]
            if collects { items.append(AgentFlowDocumentItem(isDirection: true, text: AgentFlowNamedText(range: builder.constant(direction), name: -1))) }
        case .accessibilityTitle, .accessibilityDescription, .accessibilityDescriptionMultilineValue:
            try accessibilityStatement(kind, collects: collects)
        default:
            guard Self.identifierTokens.contains(kind) else { throw failure(expecting: Self.statementStart) }
            try vertexStatement(collects: collects)
            try separator()
        }
    }

    /// `accTitle: …`, `accDescr: …` or `accDescr { … }`: its text, trimmed, which a collecting block also gets.
    private mutating func accessibilityStatement(_ kind: AgentFlowTokenKind, collects: Bool) throws(MermaidDiagramReadError) {
        let value: MermaidTextRange
        if kind == .accessibilityDescriptionMultilineValue {
            value = builder.model.text.trimmed(text(at: index))
            index += 1
        } else {
            index += 1
            value = builder.model.text.trimmed(try expect(kind == .accessibilityTitle ? .accessibilityTitleValue : .accessibilityDescriptionValue))
        }
        builder.setAccessibility(value, isTitle: kind == .accessibilityTitle)
        if collects { collect(AgentFlowNamedText(range: value, name: builder.name(of: value))) }
    }

    private mutating func collect(_ text: AgentFlowNamedText) {
        items.append(AgentFlowDocumentItem(isDirection: false, text: text))
    }

    static let directionTexts: [AgentFlowConstantText] = [.topToBottom, .bottomToTop, .rightToLeft, .leftToRight, .topDown]

    /// `classDef names styles` or `class identifiers name`, and its separator.
    private mutating func classStatement(isDefinition: Bool) throws(MermaidDiagramReadError) {
        index += 1
        _ = try expect(.space)
        let identifiers = try identifier()
        _ = try expect(.space)
        if isDefinition { builder.addClass(identifiers, styles: try styles()) } else { builder.setClass(identifiers, className: try identifier()) }
        try separator()
    }

    /// `connector id["Title"]@{ … }` and its separator; its identifier, empty for none.
    private mutating func connectorStatement() throws(MermaidDiagramReadError) -> AgentFlowNamedText {
        let keywordIndex = index
        index += 1
        let frame = try header(keywordIndex: keywordIndex)
        let separatorIndex = index
        index += 1
        let identifier = try builder.addConnector(frame.identifier, title: frame.title)
        try attachBlockMetadata(frame, to: identifier.range)
        builder.addBlockMapping(builder.model.text.trimmed(frame.identifier?.range ?? .empty), kind: .connector,
                                start: span(from: keywordIndex, to: keywordIndex), end: span(from: separatorIndex, to: separatorIndex))
        return identifier
    }
}
