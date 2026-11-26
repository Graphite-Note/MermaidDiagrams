/**
 * File: AgentFlowDiagramBuilder.swift
 * -----------------------------------
 * Layer: Core
 * Description: Builds an agent flow's flat model as Pele's db.ts builds its database: nodes named and renamed, their
 *              shapes and metadata, what metadata on a flow, a connector or an edge means, each count checked before
 *              anything is made, names as numbers and texts as ranges.
 *
 * Authors: Bahey Shalash
 * Version: 0.4
 * Date: 26/11/2026
 */

/// A text as the grammar read it, by its range, with how it was written.
struct AgentFlowText: Equatable {
    var range: MermaidTextRange
    var type: AgentFlowLabelType
}

/// A name as a statement wrote it, and its number.
struct AgentFlowNamedText {
    var range: MermaidTextRange
    var name: Int32
}

/// Builds an agent flow's model statement by statement, as Pele's `AgentflowDb` does, on numbers and ranges where 0.7.0
/// kept Strings in dictionaries: what each identifier stands for is its name's role (`AgentFlowNames`). Nodes, flows and
/// connectors count as nodes and edges as edges, each checked against the limits before it is made.
struct AgentFlowDiagramBuilder {
    var model = AgentFlowModel()
    var names: AgentFlowNames
    let limits: MermaidDiagramLimits
    /// Lines before the text the parser reads, added to every line reported.
    let lineOffset: Int
    var flowCount = 0
    var pairCounts: AgentFlowPairCounts
    /// The first edge whose made identifier has no name yet: such names are made only when an identifier that could be
    /// one is looked up (`nameEdgeIdentifiers`).
    var firstUnnamedEdge = 0
    var constants = [MermaidTextRange?](repeating: nil, count: AgentFlowConstantText.allCases.count)
    /// Room reused by every metadata body and every list split at commas.
    var metadataEntries: ScratchList<AgentFlowPlainMetadata.Entry>
    var pieces: ScratchList<MermaidTextRange>
    /// The thread's scratch arena, which holds every list the reading needs only while it runs.
    let arena: DiagramScratchArena
    /// For diagnostics, made when the first is recorded: each name's first mapping, and what was recorded of each name.
    var firstMappingByName: [Int32] = []
    var reportedDiagnostics: [Int32: [AgentFlowDiagnostic]] = [:]

    init(text: AgentFlowTextBytes, limits: MermaidDiagramLimits, lineOffset: Int, arena: DiagramScratchArena) {
        model.text = text
        self.arena = arena
        pairCounts = AgentFlowPairCounts(arena: arena)
        metadataEntries = arena.list(capacity: 8)
        pieces = arena.list(capacity: 8)
        names = AgentFlowNames(isASCII: text.isASCII)
        self.limits = limits
        self.lineOffset = lineOffset
    }

    /// Room for the nodes, edges and mappings a text of `tokenCount` tokens names, made once: the documentation's
    /// examples name a node for about every sixteen tokens and an edge for about every twenty-four.
    mutating func reserveRoom(forTokenCount tokenCount: Int) {
        let nodeCount = min(tokenCount / 16, limits.maximumNodeCount)
        let edgeCount = min(tokenCount / 24, limits.maximumEdgeCount)
        names.reserveCapacity(2 * nodeCount + 8)
        model.vertices.reserveCapacity(nodeCount + 4)
        model.vertexAttributes.reserveCapacity(nodeCount + 4)
        model.members.reserveCapacity(nodeCount + 4)
        model.flows.reserveCapacity(nodeCount / 4 + 2)
        model.mappings.reserveCapacity(2 * (nodeCount + edgeCount) + 4)
        model.edges.reserveCapacity(edgeCount + 4)
        pairCounts.reserveCapacity(edgeCount)
    }

    /// Nodes, flows and connectors made so far.
    var nodeCount: Int { model.vertices.count + model.flows.count }

    func checkNodeLimit() throws(MermaidDiagramReadError) {
        guard nodeCount < limits.maximumNodeCount else { throw .tooManyNodes(limit: limits.maximumNodeCount) }
    }

    mutating func name(of range: MermaidTextRange) -> Int32 {
        names.name(of: range, in: model.text)
    }

    mutating func constant(_ text: AgentFlowConstantText) -> MermaidTextRange {
        model.text.constant(text, cache: &constants)
    }

    /// Names a node, or gives what follows to the flow, the connector or the edge of that identifier: Pele's
    /// `addVertex`. `metadata` is the range of a `@{ … }` block's body and `metadataSpan` where the block sits. Returns
    /// the identifier's name, or -1 for an identifier of white space alone, which names nothing.
    @discardableResult
    mutating func addVertex(_ identifier: MermaidTextRange, text: AgentFlowText? = nil, type: Int16? = nil, styles: [MermaidTextRange] = [],
                            property: (field: MermaidTextRange, value: MermaidTextRange)? = nil, metadata body: MermaidTextRange? = nil,
                            metadataSpan: AgentFlowSourceSpan? = nil) throws(MermaidDiagramReadError) -> Int32 {
        guard !model.text.trimmed(identifier).isEmpty else { return -1 }
        var facts: AgentFlowMetadataFacts?
        if let body {
            facts = AgentFlowMetadataFacts.reading(body, in: &model.text, entries: &metadataEntries)
            guard facts != nil else {
                throw .invalidSyntax(line: line(of: metadataSpan), problem: .agentFlow(.metadataNotYAML(identifier: model.text.string(identifier))))
            }
        }
        let name = name(of: identifier)
        if try applyToOtherElement(name, identifier: identifier, facts: facts, body: body) { return name }
        let index = try vertexIndex(of: name, identifier: identifier)
        if let text {
            model.vertices[index].labelType = text.type
            model.vertices[index].text = model.text.unquoted(model.text.trimmed(text.range))
            model.vertices[index].hasText = true
        } else if !model.vertices[index].hasText {
            model.vertices[index].text = identifier
            model.vertices[index].hasText = true
        }
        if let type { model.vertices[index].type = type }
        for style in styles { addVertexAttribute(index, .style, style) }
        // A node always has properties once named, empty when none were written.
        model.vertices[index].hasProperties = true
        if let property { model.vertexAttributes.append(AgentFlowAttribute(owner: Int32(index), kind: .property, value: property.field, detail: property.value)) }
        guard let facts, let body else { return name }
        model.vertices[index].hasMetadata = true
        addVertexAttribute(index, .metadata, body)
        if facts.isMapping { try apply(facts, toVertex: index, line: (metadataSpan?.firstLine ?? 1) + lineOffset) }
        return name
    }

    mutating func addVertexAttribute(_ vertex: Int, _ kind: AgentFlowAttribute.Kind, _ value: MermaidTextRange) {
        model.vertexAttributes.append(AgentFlowAttribute(owner: Int32(vertex), kind: kind, value: value))
    }

    /// Metadata for a flow or a connector, or anything for an edge, goes to it: true when it did.
    private mutating func applyToOtherElement(_ name: Int32, identifier: MermaidTextRange, facts: AgentFlowMetadataFacts?,
                                              body: MermaidTextRange?) throws(MermaidDiagramReadError) -> Bool {
        let role = names[name]
        if let facts, let body, role.flow >= 0 {
            let flow = Int(role.flow)
            model.flows[flow].hasMetadata = true
            model.flowAttributes.append(AgentFlowAttribute(owner: role.flow, kind: .metadata, value: body))
            if facts.isMapping, let view = facts.view { model.flows[flow].isCollapsed = isText(view, Self.collapsedWord) }
            return true
        }
        if let body, role.isConnector, role.vertex >= 0 {
            model.vertices[Int(role.vertex)].hasMetadata = true
            addVertexAttribute(Int(role.vertex), .metadata, body)
            return true
        }
        // Mermaid reserves this identifier and makes no node for it.
        if isReservedConnectorsIdentifier(identifier) { return true }
        let edge = edgeIndex(of: name, identifier: identifier)
        guard edge >= 0 else { return false }
        if let facts, let body {
            if facts.isMapping, let curve = facts.curve { model.edges[edge].interpolation = curve.javaScriptText(in: &model.text) }
            model.edges[edge].hasMetadata = true
            model.edgeAttributes.append(AgentFlowAttribute(owner: Int32(edge), kind: .metadata, value: body))
        }
        return true
    }

    /// Whether `identifier` is `connectors`, as 0.7.0's String comparison found it.
    private func isReservedConnectorsIdentifier(_ identifier: MermaidTextRange) -> Bool {
        if model.text.isASCII(identifier) { return model.text.equals(identifier, Self.connectorsWord) }
        return model.text.string(identifier) == "connectors"
    }

    private static let connectorsWord = Array("connectors".utf8)

    /// Whether a metadata value is the text `word`.
    func isText(_ value: AgentFlowMetadataValue, _ word: [UInt8]) -> Bool {
        guard case .text(let range) = value else { return false }
        return model.text.isASCII(range) ? model.text.equals(range, word) : model.text.string(range) == String(decoding: word, as: UTF8.self)
    }

    static let collapsedWord = Array("collapsed".utf8)

    /// The index of the node of `name`, made when it is new.
    private mutating func vertexIndex(of name: Int32, identifier: MermaidTextRange) throws(MermaidDiagramReadError) -> Int {
        let known = names[name].vertex
        if known >= 0 { return Int(known) }
        try checkNodeLimit()
        names[name].vertex = Int32(model.vertices.count)
        model.vertices.append(AgentFlowVertexRecord(identifier: identifier, name: name, firstAttribute: Int32(model.vertexAttributes.count)))
        return model.vertices.count - 1
    }

    /// The line a span starts on, in the whole text.
    func line(of span: AgentFlowSourceSpan?) -> Int {
        (span?.firstLine ?? 1) + lineOffset
    }
}
