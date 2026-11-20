/**
 * File: AgentFlowParserStatements.swift
 * -------------------------------------
 * Layer: Core
 * Description: An agent flow's statements as Pele's parser.ts reads them: styles, link styles, classes, clicks,
 *              connectors, directions, accessibility text, and the document's blocks nested without recursion.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 19/11/2026
 */

extension AgentFlowParser {
    /// An open `flow` or `global` block: where its keyword is, its identifier, title and metadata, and the items and
    /// collecting of the block around it.
    struct Frame {
        var isGlobal: Bool
        var keywordIndex: Int
        var identifier: AgentFlowText?
        var title: AgentFlowText?
        var metadata: String?
        var metadataFrom = 0
        var metadataTo = 0
        var items: [AgentFlowDocumentItem] = []
        var collects = false
    }

    /// The statements to the end, `flow` and `global` blocks kept on a stack of their own.
    mutating func readDocument() throws(MermaidDiagramReadError) {
        var open: [Frame] = []
        var items: [AgentFlowDocumentItem] = []
        var collects = false
        while true {
            let kind = current
            if kind == .end { break }
            switch kind {
            case .endKeyword:
                guard let frame = open.popLast() else { return }
                let closed = try close(frame, items: items)
                items = frame.items
                collects = frame.collects
                if collects, let closed { items.append(.text(closed)) }
            case .semicolon, .newline, .space, .endOfFile: index += 1
            case .comment: index += 1
            case .flow, .global:
                var frame = try openFrame(isGlobal: kind == .global)
                frame.items = items
                frame.collects = collects
                open.append(frame)
                items = []
                collects = true
            default:
                let item = try statement()
                if collects, let item { items.append(item) }
            }
        }
        if !open.isEmpty { throw failure(expecting: "'end'") }
    }

    /// The `end` of a block: a `global` block's nodes kept out of flows, or the flow made, its identifier returned.
    private mutating func close(_ frame: Frame, items: [AgentFlowDocumentItem]) throws(MermaidDiagramReadError) -> String? {
        let endIndex = index
        index += 1
        guard !frame.isGlobal else {
            builder.addGlobal(items)
            return nil
        }
        let identifier = try builder.addFlow(identifier: frame.identifier, items: items, title: frame.title)
        try attachBlockMetadata(frame, to: identifier)
        builder.addBlockMapping(frame.identifier.map { written in written.text } ?? "", kind: .subgraph,
                                start: span(from: frame.keywordIndex, to: frame.keywordIndex), end: span(from: endIndex, to: endIndex))
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
        var title = AgentFlowText(text: "", type: .text)
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

    private mutating func attachBlockMetadata(_ frame: Frame, to identifier: String) throws(MermaidDiagramReadError) {
        guard let metadata = frame.metadata else { return }
        try builder.addVertex(identifier, metadata: metadata, metadataSpan: span(from: frame.metadataFrom, to: frame.metadataTo))
    }

    /// One statement, and what it gives the block around it: the nodes it names, a connector's identifier, an
    /// accessibility text or a direction; nil for a statement that names nothing.
    private mutating func statement() throws(MermaidDiagramReadError) -> AgentFlowDocumentItem? {
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
        case .connector: return try connectorStatement()
        case .directionTopToBottom, .directionBottomToTop, .directionRightToLeft, .directionLeftToRight, .directionTopDown:
            index += 1
            return .direction(["TB", "BT", "RL", "LR", "TD"][kind.rawValue - AgentFlowTokenKind.directionTopToBottom.rawValue])
        case .accessibilityTitle, .accessibilityDescription:
            index += 1
            let value = C4Characters.trimmed(try expect(kind == .accessibilityTitle ? .accessibilityTitleValue : .accessibilityDescriptionValue))
            setAccessibility(value, isTitle: kind == .accessibilityTitle)
            return .text(value)
        case .accessibilityDescriptionMultilineValue:
            let value = C4Characters.trimmed(text(at: index))
            index += 1
            setAccessibility(value, isTitle: false)
            return .text(value)
        default:
            guard Self.identifierTokens.contains(kind) else { throw failure(expecting: Self.statementStart) }
            let nodes = try vertexStatement()
            try separator()
            return nodes.isEmpty ? nil : .identifiers(nodes)
        }
        return nil
    }

    /// `classDef names styles` or `class identifiers name`, and its separator.
    private mutating func classStatement(isDefinition: Bool) throws(MermaidDiagramReadError) {
        index += 1
        _ = try expect(.space)
        let identifiers = try identifier()
        _ = try expect(.space)
        if isDefinition { builder.addClass(identifiers, styles: try styles()) } else { builder.setClass(identifiers, className: try identifier()) }
        try separator()
    }

    private mutating func setAccessibility(_ value: String, isTitle: Bool) {
        if isTitle {
            builder.diagram.accessibilityTitle = value
        } else {
            builder.diagram.accessibilityDescription = value.replacingRuns(afterLineFeed: true)
        }
    }

    /// `connector id["Title"]@{ … }` and its separator.
    private mutating func connectorStatement() throws(MermaidDiagramReadError) -> AgentFlowDocumentItem {
        let keywordIndex = index
        index += 1
        let frame = try header(keywordIndex: keywordIndex)
        let separatorIndex = index
        index += 1
        let identifier = try builder.addConnector(frame.identifier, title: frame.title)
        try attachBlockMetadata(frame, to: identifier)
        builder.addBlockMapping(C4Characters.trimmed(frame.identifier?.text ?? ""), kind: .connector,
                                start: span(from: keywordIndex, to: keywordIndex), end: span(from: separatorIndex, to: separatorIndex))
        return .text(identifier)
    }
}

extension String {
    /// The text with each line feed and the white space after it made one line feed (`/\n\s+/g` to `\n`).
    fileprivate func replacingRuns(afterLineFeed: Bool) -> String {
        var result = ""
        var skipping = false
        for scalar in unicodeScalars {
            if skipping, C4Characters.isSpace(UInt16(truncatingIfNeeded: scalar.value)), scalar.value <= 0xFFFF { continue }
            skipping = false
            result.unicodeScalars.append(scalar)
            if scalar == "\n" { skipping = true }
        }
        return result
    }
}
