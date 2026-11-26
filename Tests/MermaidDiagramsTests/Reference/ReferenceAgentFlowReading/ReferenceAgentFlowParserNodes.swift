/**
 * File: ReferenceAgentFlowParserNodes.swift
 * -----------------------------------------
 * Layer: Tests
 * Description: 0.7.0's agent flow reader on UTF-16 code units (AgentFlowParserNodes.swift), kept unchanged but for its
 *              names as the reference the reader on bytes is compared with (AgentFlowReadingEquivalenceTests).
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 26/11/2026
 */

@testable import MermaidDiagrams

extension ReferenceAgentFlowParser {
    /// A node: its identifier, then its text in the brackets of its shape, if any.
    mutating func vertex() throws(MermaidDiagramReadError) -> String {
        let from = index
        let identifier = try identifier()
        var label: ReferenceAgentFlowText?
        var type: String?
        var properties: [String: String] = [:]
        if let bracket = Self.brackets[current.rawValue] {
            index += 1
            if bracket.opensTwice, current == bracket.opening {
                index += 1
                label = try nodeText()
                try close(bracket.closing)
                _ = try expect(bracket.closing)
                type = bracket.doubledType
            } else {
                label = try nodeText()
                try close(bracket.closing)
                type = bracket.type
            }
        } else if current == .vertexWithPropertiesStart {
            (label, properties) = try textWithProperty()
            type = "rect"
        } else if current == .trapezoidStart || current == .invertedTrapezoidStart {
            (label, type) = try trapezoidText()
        }
        try builder.addVertex(identifier, text: label, type: type, properties: properties)
        builder.addVertexMapping(identifier, hasShape: type != nil, span: span(from: from, to: index - 1))
        return identifier
    }

    /// `[|field:value|text]`: the text and the property.
    private mutating func textWithProperty() throws(MermaidDiagramReadError) -> (ReferenceAgentFlowText, [String: String]) {
        index += 1
        let field = try expect(.nodeString)
        _ = try expect(.colon)
        let value = try expect(.nodeString)
        _ = try expect(.pipe)
        let label = try nodeText()
        try close(.squareEnd)
        return (label, [field: value])
    }

    /// `[/text\]`, `[/text/]`, `[\text/]` or `[\text\]`: the text and the trapezoid or leaning shape its ends give.
    private mutating func trapezoidText() throws(MermaidDiagramReadError) -> (ReferenceAgentFlowText, String) {
        let isInverted = current == .invertedTrapezoidStart
        index += 1
        let label = try nodeText()
        let leaning: ReferenceAgentFlowTokenKind = isInverted ? .trapezoidEnd : .invertedTrapezoidEnd
        if current == leaning {
            index += 1
            return (label, isInverted ? "lean_left" : "lean_right")
        }
        try close(isInverted ? .invertedTrapezoidEnd : .trapezoidEnd)
        return (label, isInverted ? "inv_trapezoid" : "trapezoid")
    }

    /// A node with its class after `:::`.
    mutating func styledVertex() throws(MermaidDiagramReadError) -> String {
        let identifier = try vertex()
        if current == .styleSeparator {
            index += 1
            builder.setClass(identifier, className: try self.identifier())
        }
        return identifier
    }

    /// Nodes joined by `&`, the metadata after each but the last attached to it; the last one's is left pending.
    mutating func nodeGroup() throws(MermaidDiagramReadError) -> [String] {
        var identifiers = [try styledVertex()]
        pendingMetadata = nil
        while true {
            let metadata = current == .shapeData ? shapeData() : nil
            let (from, to) = (metadataFrom, metadataTo)
            if current != .space {
                pendingMetadata = metadata
                return identifiers
            }
            while current == .space { index += 1 }
            if current != .ampersand {
                if metadata != nil { throw failure(expecting: "'AMP'") }
                return identifiers
            }
            index += 1
            if current != .space { throw failure(expecting: "'SPACE'") }
            while current == .space { index += 1 }
            let next = try styledVertex()
            if let metadata, let last = identifiers.last { try attach(metadata, to: last, from: from, to: to) }
            identifiers.append(next)
        }
    }

    /// Metadata after a node, widening the node's mapping over it.
    mutating func attach(_ metadata: String, to identifier: String, from first: Int, to last: Int) throws(MermaidDiagramReadError) {
        let metadataSpan = span(from: first, to: last)
        try builder.addVertex(identifier, metadata: metadata, metadataSpan: metadataSpan)
        builder.extendVertexMapping(identifier, span: metadataSpan)
    }

    /// A link: its identifier, then a whole arrow with an optional `|text|`, or an arrow split around its text.
    mutating func link() throws(MermaidDiagramReadError) -> ReferenceAgentFlowLinkInfo {
        var identifier: String?
        if current == .linkIdentifier {
            identifier = text(at: index)
            index += 1
        }
        if current == .link {
            var info = ReferenceAgentFlowLinkInfo(end: text(at: index))
            index += 1
            info.identifier = identifier
            if current == .pipe {
                index += 1
                info.text = try nodeText()
                try close(.pipe)
                if current == .space { index += 1 }
            }
            return info
        }
        if current == .startLink {
            let start = text(at: index)
            index += 1
            let label = try edgeText()
            let end = try expect(.link, also: "'EDGE_TEXT'")
            var info = ReferenceAgentFlowLinkInfo(end: end, start: start)
            info.text = label
            info.identifier = identifier
            return info
        }
        throw failure(expecting: "'LINK', 'START_LINK'")
    }

    /// Nodes and the links between them: each link joins every node before it to every node after it. Returns every
    /// node named, the last first, as Mermaid's grammar collects them for a flow.
    mutating func vertexStatement() throws(MermaidDiagramReadError) -> [String] {
        let from = index
        var statement = try nodeGroup()
        if let metadata = pendingMetadata, let last = statement.last { try attach(metadata, to: last, from: metadataFrom, to: metadataTo) }
        var nodes = statement
        while current == .link || current == .startLink || current == .linkIdentifier {
            let info = try link()
            let next = try nodeGroup()
            if let metadata = pendingMetadata, let last = next.last { try attach(metadata, to: last, from: metadataFrom, to: metadataTo) }
            try builder.addLink(from: statement, to: next, link: info)
            builder.addEdgeMapping(to: next, span: span(from: from, to: index - 1))
            nodes = next + nodes
            statement = next
        }
        return nodes
    }

    /// A node's brackets: the token that opens them, the one that closes them, and the shape they give; a bracket
    /// written twice (`((` … `))`, `{{` … `}}`) gives another.
    struct Bracket {
        let opening: ReferenceAgentFlowTokenKind
        let closing: ReferenceAgentFlowTokenKind
        let type: String
        var opensTwice = false
        var doubledType = ""
    }

    /// The brackets by the raw value of the token that opens them, looked up without hashing; nil for any other token.
    static let brackets: [Bracket?] = {
        var byOpening = [Bracket?](repeating: nil, count: ReferenceAgentFlowTokenKind.endOfFile.rawValue + 1)
        for bracket in [
            Bracket(opening: .squareStart, closing: .squareEnd, type: "square"),
            Bracket(opening: .doubleCircleStart, closing: .doubleCircleEnd, type: "doublecircle"),
            Bracket(opening: .parenthesisStart, closing: .parenthesisEnd, type: "round", opensTwice: true, doubledType: "circle"),
            Bracket(opening: .ellipseStart, closing: .ellipseEnd, type: "ellipse"),
            Bracket(opening: .stadiumStart, closing: .stadiumEnd, type: "stadium"),
            Bracket(opening: .subroutineStart, closing: .subroutineEnd, type: "subroutine"),
            Bracket(opening: .cylinderStart, closing: .cylinderEnd, type: "cylinder"),
            Bracket(opening: .diamondStart, closing: .diamondStop, type: "diamond", opensTwice: true, doubledType: "hexagon"),
            Bracket(opening: .tagEnd, closing: .squareEnd, type: "odd"),
        ] {
            byOpening[bracket.opening.rawValue] = bracket
        }
        return byOpening
    }()
}
