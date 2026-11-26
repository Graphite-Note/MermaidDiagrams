/**
 * File: ReferenceAgentFlowDiagramBuilder.swift
 * --------------------------------------------
 * Layer: Tests
 * Description: 0.7.0's agent flow reader on UTF-16 code units (AgentFlowDiagramBuilder.swift), kept unchanged but for its
 *              names as the reference the reader on bytes is compared with (AgentFlowReadingEquivalenceTests).
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 26/11/2026
 */

@testable import MermaidDiagrams

/// A text as the grammar read it, with how it was written.
struct ReferenceAgentFlowText: Equatable {
    var text: String
    var type: AgentFlowLabelType
}

/// Builds an agent flow's model statement by statement, as Pele's `AgentflowDb` does. Nodes, flows and connectors
/// count as nodes and edges as edges, each checked against the limits before it is made.
struct ReferenceAgentFlowDiagramBuilder {
    var diagram = ReferenceAgentFlowDiagram()
    let limits: MermaidDiagramLimits
    /// Lines before the text the parser reads, added to every line reported.
    let lineOffset: Int
    var vertexIndices: [String: Int] = [:]
    var flowIndices: [String: Int] = [:]
    var classIndices: [String: Int] = [:]
    var connectorIdentifiers: Set<String> = []
    var globalNodes: Set<String> = []
    var members: Set<String> = []
    var edgeIndices: [String: Int] = [:]
    var pairCounts: [String: Int] = [:]
    var flowCount = 0
    var tooltips: [String: String] = [:]
    /// Whether each mapping, by its place, is of a bare reference, which becomes an attachment when metadata follows it.
    var isBareMapping: [Bool] = []
    var firstMappings: [String: Int] = [:]
    /// The diagnostics recorded, by the identifier they are about, so that each finding is recorded once.
    var reportedDiagnostics: [String: [AgentFlowDiagnostic]] = [:]

    init(limits: MermaidDiagramLimits, lineOffset: Int) {
        self.limits = limits
        self.lineOffset = lineOffset
    }

    /// Room for the nodes, edges and mappings a text of `tokenCount` tokens names, made once: the documentation's
    /// examples name a node for about every sixteen tokens and an edge for about every twenty-four.
    mutating func reserveRoom(forTokenCount tokenCount: Int) {
        let nodeCount = min(tokenCount / 16, limits.maximumNodeCount)
        let edgeCount = min(tokenCount / 24, limits.maximumEdgeCount)
        vertexIndices.reserveCapacity(nodeCount)
        firstMappings.reserveCapacity(nodeCount + edgeCount)
        diagram.vertices.reserveCapacity(nodeCount)
        diagram.mappings.reserveCapacity(nodeCount + edgeCount)
        isBareMapping.reserveCapacity(nodeCount + edgeCount)
        edgeIndices.reserveCapacity(edgeCount)
        pairCounts.reserveCapacity(edgeCount)
        diagram.edges.reserveCapacity(edgeCount)
    }

    /// Nodes, flows and connectors made so far.
    var nodeCount: Int { diagram.vertices.count + diagram.flows.count }

    func checkNodeLimit() throws(MermaidDiagramReadError) {
        guard nodeCount < limits.maximumNodeCount else { throw .tooManyNodes(limit: limits.maximumNodeCount) }
    }

    /// Names a node, or gives what follows to the flow, the connector or the edge of that identifier: Pele's
    /// `addVertex`. `metadata` is the body of a `@{ … }` block and `metadataSpan` where the block sits.
    mutating func addVertex(_ identifier: String, text: ReferenceAgentFlowText? = nil, type: String? = nil, styles: [String]? = nil,
                            properties: [String: String] = [:], metadata body: String? = nil,
                            metadataSpan: ReferenceAgentFlowSourceSpan? = nil) throws(MermaidDiagramReadError) {
        guard !C4Characters.trimmed(identifier).isEmpty else { return }
        var document: SequenceAttributeValue?
        var authoredShape: SequenceAttributeValue?
        if let body {
            guard var parsed = ReferenceAgentFlowMetadataReading.value(of: body) else {
                throw .invalidSyntax(line: line(of: metadataSpan), problem: .agentFlow(.metadataNotYAML(identifier: identifier)))
            }
            if case .mapping(var fields) = parsed, let shape = fields["shape"] {
                authoredShape = shape
                if case .text(let name) = shape { fields["shape"] = .text(ReferenceAgentFlowShapes.resolvingAlias(name)) }
                parsed = .mapping(fields)
            }
            document = parsed
        }
        if try applyToOtherElement(identifier, document: document) { return }
        let index = try vertexIndex(of: identifier)
        let lineOffset = lineOffset
        // Changed where it is in the list, not copied out and back: a statement that fails ends the whole reading.
        try Self.update(&diagram.vertices[index], named: identifier, text: text, type: type, styles: styles, properties: properties,
                        document: document, authoredShape: authoredShape, span: metadataSpan, lineOffset: lineOffset)
    }

    /// What one statement says of a node: its text, shape, styles, properties and metadata.
    private static func update(_ vertex: inout AgentFlowVertex, named identifier: String, text: ReferenceAgentFlowText?, type: String?, styles: [String]?,
                               properties: [String: String], document: SequenceAttributeValue?, authoredShape: SequenceAttributeValue?,
                               span: ReferenceAgentFlowSourceSpan?, lineOffset: Int) throws(MermaidDiagramReadError) {
        if let text {
            vertex.labelType = text.type
            vertex.text = Self.unquoted(C4Characters.trimmed(text.text))
        } else if vertex.text == nil {
            vertex.text = identifier
        }
        if let type { vertex.type = type }
        vertex.styles += styles ?? []
        // A node always has properties once named, empty when none were written.
        vertex.properties = properties.isEmpty ? vertex.properties ?? [:] : (vertex.properties ?? [:]).merging(properties) { _, new in new }
        if let document {
            vertex.metadata = ReferenceAgentFlowMetadataReading.merged(vertex.metadata, with: document)
            if case .mapping(let fields) = document {
                try apply(fields, authoredShape: authoredShape, to: &vertex, line: (span?.firstLine ?? 1) + lineOffset)
            }
        }
    }

    /// Metadata for a flow or a connector, or anything for an edge, goes to it: true when it did.
    private mutating func applyToOtherElement(_ identifier: String, document: SequenceAttributeValue?) throws(MermaidDiagramReadError) -> Bool {
        if let document, let flow = flowIndices[identifier] {
            diagram.flows[flow].metadata = ReferenceAgentFlowMetadataReading.merged(diagram.flows[flow].metadata, with: document)
            return true
        }
        if let document, connectorIdentifiers.contains(identifier), let vertex = vertexIndices[identifier] {
            diagram.vertices[vertex].metadata = ReferenceAgentFlowMetadataReading.merged(diagram.vertices[vertex].metadata, with: document)
            return true
        }
        // Mermaid reserves this identifier and makes no node for it.
        if identifier == "connectors" { return true }
        guard let edgeIndex = edgeIndices[identifier] else { return false }
        if let document {
            if case .mapping(let fields) = document, let curve = fields["curve"] {
                diagram.edges[edgeIndex].interpolation = curve.javaScriptText
            }
            diagram.edges[edgeIndex].metadata = ReferenceAgentFlowMetadataReading.merged(diagram.edges[edgeIndex].metadata, with: document)
        }
        return true
    }

    /// The index of the node `identifier`, made when it is new.
    private mutating func vertexIndex(of identifier: String) throws(MermaidDiagramReadError) -> Int {
        if let index = vertexIndices[identifier] { return index }
        try checkNodeLimit()
        vertexIndices[identifier] = diagram.vertices.count
        diagram.vertices.append(AgentFlowVertex(identifier: identifier))
        return diagram.vertices.count - 1
    }

    /// A metadata mapping's `shape` and `label`, as Mermaid applies them: a shape must be text, in lowercase without an
    /// underscore as written, and one Mermaid knows once its alias is resolved.
    private static func apply(_ fields: [String: SequenceAttributeValue], authoredShape: SequenceAttributeValue?, to vertex: inout AgentFlowVertex,
                              line: Int) throws(MermaidDiagramReadError) {
        if let shape = fields["shape"], shape.isTruthy {
            guard case .text(let authored) = authoredShape ?? shape, case .text(let resolved) = shape else {
                throw .invalidSyntax(line: line, problem: .agentFlow(.unknownShape((authoredShape ?? shape).javaScriptText)))
            }
            guard authored == authored.lowercased(), !FoundationTextOnBytes.contains(authored, character: MermaidByte.underscore) else {
                throw .invalidSyntax(line: line, problem: .agentFlow(.shapeNameNotLowercase(authored)))
            }
            guard ReferenceAgentFlowShapes.isValidShape(resolved) else { throw .invalidSyntax(line: line, problem: .agentFlow(.unknownShape(resolved))) }
            vertex.type = resolved
        }
        if let label = fields["label"], label.isTruthy {
            vertex.text = label.javaScriptText
            if case .text(let type) = fields["labelType"] { vertex.labelType = AgentFlowLabelType(named: type) } else { vertex.labelType = .markdown }
        }
    }

    /// The line a span starts on, in the whole text.
    func line(of span: ReferenceAgentFlowSourceSpan?) -> Int {
        (span?.firstLine ?? 1) + lineOffset
    }

    /// A text without the quotation marks around it.
    static func unquoted(_ text: String) -> String {
        guard text.count >= 2, text.hasPrefix("\""), text.hasSuffix("\"") else { return text }
        return String(text.dropFirst().dropLast())
    }
}
