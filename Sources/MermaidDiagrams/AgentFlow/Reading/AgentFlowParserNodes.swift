/**
 * File: AgentFlowParserNodes.swift
 * --------------------------------
 * Layer: Core
 * Description: An agent flow's nodes, links and vertex statements as Pele's parser.ts reads them: a node's brackets and
 *              shape, `:::` classes, `&` groups, metadata after a node, and chains of links.
 *
 * Authors: Bahey Shalash
 * Version: 0.3
 * Date: 26/11/2026
 */

extension AgentFlowParser {
    /// A node: its identifier, then its text in the brackets of its shape, if any.
    mutating func vertex() throws(MermaidDiagramReadError) -> AgentFlowNamedText {
        let from = index
        let identifier = try identifier()
        var label: AgentFlowText?
        var type: Int16?
        var property: (field: MermaidTextRange, value: MermaidTextRange)?
        if let bracket = Self.brackets[Int(current.rawValue)] {
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
            (label, property) = try textWithProperty()
            type = AgentFlowShapeNames.number("rect")
        } else if current == .trapezoidStart || current == .invertedTrapezoidStart {
            (label, type) = try trapezoidText()
        }
        let name = try builder.addVertex(identifier, text: label, type: type, property: property)
        let named = AgentFlowNamedText(range: identifier, name: name >= 0 ? name : builder.name(of: identifier))
        builder.addVertexMapping(named, hasShape: type != nil, span: span(from: from, to: index - 1))
        return named
    }

    /// `[|field:value|text]`: the text and the property.
    private mutating func textWithProperty() throws(MermaidDiagramReadError) -> (AgentFlowText, (field: MermaidTextRange, value: MermaidTextRange)) {
        index += 1
        let field = try expect(.nodeString)
        _ = try expect(.colon)
        let value = try expect(.nodeString)
        _ = try expect(.pipe)
        let label = try nodeText()
        try close(.squareEnd)
        return (label, (field, value))
    }

    /// `[/text\]`, `[/text/]`, `[\text/]` or `[\text\]`: the text and the trapezoid or leaning shape its ends give.
    private mutating func trapezoidText() throws(MermaidDiagramReadError) -> (AgentFlowText, Int16) {
        let isInverted = current == .invertedTrapezoidStart
        index += 1
        let label = try nodeText()
        let leaning: AgentFlowTokenKind = isInverted ? .trapezoidEnd : .invertedTrapezoidEnd
        if current == leaning {
            index += 1
            return (label, AgentFlowShapeNames.number(isInverted ? "lean_left" : "lean_right"))
        }
        try close(isInverted ? .invertedTrapezoidEnd : .trapezoidEnd)
        return (label, AgentFlowShapeNames.number(isInverted ? "inv_trapezoid" : "trapezoid"))
    }

    /// A node with its class after `:::`.
    mutating func styledVertex() throws(MermaidDiagramReadError) -> AgentFlowNamedText {
        let identifier = try vertex()
        if current == .styleSeparator {
            index += 1
            builder.setClass(identifier.range, className: try self.identifier())
        }
        return identifier
    }

    /// Nodes joined by `&`, appended to the statement's nodes, the metadata after each but the last attached to it; the
    /// last one's is left pending.
    mutating func nodeGroup() throws(MermaidDiagramReadError) {
        statementNodes.append(try styledVertex())
        pendingMetadata = nil
        while true {
            let metadata = current == .shapeData ? shapeData() : nil
            let (from, to) = (metadataFrom, metadataTo)
            if current != .space {
                pendingMetadata = metadata
                return
            }
            while current == .space { index += 1 }
            if current != .ampersand {
                if metadata != nil { throw failure(expecting: "'AMP'") }
                return
            }
            index += 1
            if current != .space { throw failure(expecting: "'SPACE'") }
            while current == .space { index += 1 }
            let next = try styledVertex()
            if let metadata, let last = statementNodes.last { try attach(metadata, to: last, from: from, to: to) }
            statementNodes.append(next)
        }
    }

    /// Metadata after a node, widening the node's mapping over it.
    mutating func attach(_ metadata: MermaidTextRange, to identifier: AgentFlowNamedText, from first: Int, to last: Int) throws(MermaidDiagramReadError) {
        let metadataSpan = span(from: first, to: last)
        try builder.addVertex(identifier.range, metadata: metadata, metadataSpan: metadataSpan)
        builder.extendVertexMapping(identifier, span: metadataSpan)
    }

    /// A link: its identifier, then a whole arrow with an optional `|text|`, or an arrow split around its text.
    mutating func link() throws(MermaidDiagramReadError) -> AgentFlowLinkInfo {
        var identifier: MermaidTextRange?
        if current == .linkIdentifier {
            identifier = text(at: index)
            index += 1
        }
        if current == .link {
            var info = AgentFlowLinkInfo(end: text(at: index), in: builder.model.text)
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
            var info = AgentFlowLinkInfo(end: end, start: start, in: builder.model.text)
            info.text = label
            info.identifier = identifier
            return info
        }
        throw failure(expecting: "'LINK', 'START_LINK'")
    }

    /// Nodes and the links between them: each link joins every node before it to every node after it. Every node named
    /// goes to the block around it when it collects, the last group first, as Mermaid's grammar collects them for a flow.
    mutating func vertexStatement(collects: Bool) throws(MermaidDiagramReadError) {
        let from = index
        statementNodes.removeAll()
        groupStarts.removeAll()
        groupStarts.append(0)
        try nodeGroup()
        if let metadata = pendingMetadata, let last = statementNodes.last { try attach(metadata, to: last, from: metadataFrom, to: metadataTo) }
        while current == .link || current == .startLink || current == .linkIdentifier {
            let info = try link()
            let start = statementNodes.count
            try nodeGroup()
            if let metadata = pendingMetadata, let last = statementNodes.last { try attach(metadata, to: last, from: metadataFrom, to: metadataTo) }
            try builder.addLink(from: groupStarts[groupStarts.count - 1]..<start, to: start..<statementNodes.count, in: statementNodes.elements, link: info)
            builder.addEdgeMapping(to: statementNodes.elements.part(start..<statementNodes.count), span: span(from: from, to: index - 1))
            groupStarts.append(start)
        }
        guard collects else { return }
        groupStarts.append(statementNodes.count)
        for group in stride(from: groupStarts.count - 2, through: 0, by: -1) {
            for position in groupStarts[group]..<groupStarts[group + 1] { items.append(AgentFlowDocumentItem(isDirection: false, text: statementNodes[position])) }
        }
    }

    /// A node's brackets: the token that opens them, the one that closes them, and the shape they give; a bracket
    /// written twice (`((` … `))`, `{{` … `}}`) gives another.
    struct Bracket {
        let opening: AgentFlowTokenKind
        let closing: AgentFlowTokenKind
        let type: Int16
        var opensTwice = false
        var doubledType: Int16 = -1

        init(opening: AgentFlowTokenKind, closing: AgentFlowTokenKind, type: String, opensTwice: Bool = false, doubledType: String = "") {
            self.opening = opening
            self.closing = closing
            self.type = AgentFlowShapeNames.number(type)
            self.opensTwice = opensTwice
            self.doubledType = AgentFlowShapeNames.number(doubledType)
        }
    }

    /// The brackets by the raw value of the token that opens them, looked up without hashing; nil for any other token.
    static let brackets: [Bracket?] = {
        var byOpening = [Bracket?](repeating: nil, count: Int(AgentFlowTokenKind.endOfFile.rawValue) + 1)
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
            byOpening[Int(bracket.opening.rawValue)] = bracket
        }
        return byOpening
    }()
}
