/**
 * File: AgentFlowDiagramBuilder.swift
 * -----------------------------------
 * Layer: Core
 * Description: Builds an agent flow's model as Pele's db.ts does: nodes named and renamed, their shapes and metadata,
 *              what metadata on a flow, a connector or an edge means, each count checked before anything is made.
 *
 * Authors: Bahey Shalash
 * Version: 0.2
 * Date: 23/11/2026
 */

/// A text as the grammar read it, with how it was written.
struct AgentFlowText: Equatable {
    var text: String
    var type: AgentFlowLabelType
}

/// Builds an agent flow's model statement by statement, as Pele's `AgentflowDb` does. Nodes, flows and connectors
/// count as nodes and edges as edges, each checked against the limits before it is made.
struct AgentFlowDiagramBuilder {
    var diagram = AgentFlowDiagram()
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
    /// Mappings of bare references, which become attachments when metadata follows them.
    var bareMappings: Set<Int> = []
    var firstMappings: [String: Int] = [:]
    /// The diagnostics recorded, by the identifier they are about, so that each finding is recorded once.
    var reportedDiagnostics: [String: [AgentFlowDiagnostic]] = [:]

    init(limits: MermaidDiagramLimits, lineOffset: Int) {
        self.limits = limits
        self.lineOffset = lineOffset
    }

    /// Nodes, flows and connectors made so far.
    var nodeCount: Int { diagram.vertices.count + diagram.flows.count }

    func checkNodeLimit() throws(MermaidDiagramReadError) {
        guard nodeCount < limits.maximumNodeCount else { throw .tooManyNodes(limit: limits.maximumNodeCount) }
    }

    /// Names a node, or gives what follows to the flow, the connector or the edge of that identifier: Pele's
    /// `addVertex`. `metadata` is the body of a `@{ … }` block and `metadataSpan` where the block sits.
    mutating func addVertex(_ identifier: String, text: AgentFlowText? = nil, type: String? = nil, styles: [String]? = nil,
                            properties: [String: String] = [:], metadata body: String? = nil,
                            metadataSpan: AgentFlowSourceSpan? = nil) throws(MermaidDiagramReadError) {
        guard !C4Characters.trimmed(identifier).isEmpty else { return }
        var document: SequenceAttributeValue?
        var authoredShape: SequenceAttributeValue?
        if let body {
            guard var parsed = AgentFlowMetadataReading.value(of: body) else {
                throw .invalidSyntax(line: line(of: metadataSpan), problem: .agentFlow(.metadataNotYAML(identifier: identifier)))
            }
            if case .mapping(var fields) = parsed, let shape = fields["shape"] {
                authoredShape = shape
                if case .text(let name) = shape { fields["shape"] = .text(AgentFlowShapes.resolvingAlias(name)) }
                parsed = .mapping(fields)
            }
            document = parsed
        }
        if try applyToOtherElement(identifier, document: document) { return }
        let index = try vertexIndex(of: identifier)
        var vertex = diagram.vertices[index]
        if let text {
            vertex.labelType = text.type
            vertex.text = Self.unquoted(C4Characters.trimmed(text.text))
        } else if vertex.text == nil {
            vertex.text = identifier
        }
        if let type { vertex.type = type }
        vertex.styles += styles ?? []
        vertex.properties = (vertex.properties ?? [:]).merging(properties) { _, new in new }
        if let document {
            vertex.metadata = AgentFlowMetadataReading.merged(vertex.metadata, with: document)
            if case .mapping(let fields) = document {
                try apply(fields, authoredShape: authoredShape, to: &vertex, span: metadataSpan)
            }
        }
        diagram.vertices[index] = vertex
    }

    /// Metadata for a flow or a connector, or anything for an edge, goes to it: true when it did.
    private mutating func applyToOtherElement(_ identifier: String, document: SequenceAttributeValue?) throws(MermaidDiagramReadError) -> Bool {
        if let document, let flow = flowIndices[identifier] {
            diagram.flows[flow].metadata = AgentFlowMetadataReading.merged(diagram.flows[flow].metadata, with: document)
            return true
        }
        if let document, connectorIdentifiers.contains(identifier), let vertex = vertexIndices[identifier] {
            diagram.vertices[vertex].metadata = AgentFlowMetadataReading.merged(diagram.vertices[vertex].metadata, with: document)
            return true
        }
        // Mermaid reserves this identifier and makes no node for it.
        if identifier == "connectors" { return true }
        guard let edgeIndex = edgeIndices[identifier] else { return false }
        if let document {
            if case .mapping(let fields) = document, let curve = fields["curve"] {
                diagram.edges[edgeIndex].interpolation = curve.javaScriptText
            }
            diagram.edges[edgeIndex].metadata = AgentFlowMetadataReading.merged(diagram.edges[edgeIndex].metadata, with: document)
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
    private func apply(_ fields: [String: SequenceAttributeValue], authoredShape: SequenceAttributeValue?, to vertex: inout AgentFlowVertex,
                       span: AgentFlowSourceSpan?) throws(MermaidDiagramReadError) {
        if let shape = fields["shape"], shape.isTruthy {
            let line = line(of: span)
            guard case .text(let authored) = authoredShape ?? shape, case .text(let resolved) = shape else {
                throw .invalidSyntax(line: line, problem: .agentFlow(.unknownShape((authoredShape ?? shape).javaScriptText)))
            }
            guard authored == authored.lowercased(), !FoundationTextOnBytes.contains(authored, character: MermaidByte.underscore) else {
                throw .invalidSyntax(line: line, problem: .agentFlow(.shapeNameNotLowercase(authored)))
            }
            guard AgentFlowShapes.isValidShape(resolved) else { throw .invalidSyntax(line: line, problem: .agentFlow(.unknownShape(resolved))) }
            vertex.type = resolved
        }
        if let label = fields["label"], label.isTruthy {
            vertex.text = label.javaScriptText
            if case .text(let type) = fields["labelType"] { vertex.labelType = AgentFlowLabelType(named: type) } else { vertex.labelType = .markdown }
        }
    }

    /// The line a span starts on, in the whole text.
    func line(of span: AgentFlowSourceSpan?) -> Int {
        (span?.firstLine ?? 1) + lineOffset
    }

    /// A text without the quotation marks around it.
    static func unquoted(_ text: String) -> String {
        guard text.count >= 2, text.hasPrefix("\""), text.hasSuffix("\"") else { return text }
        return String(text.dropFirst().dropLast())
    }
}
