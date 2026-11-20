/**
 * File: AgentFlowReferenceProjection.swift
 * ----------------------------------------
 * Layer: Tests
 * Description: An agent flow's model in the fields and the form of Pele's reference projection, to compare with what
 *              Mermaid built.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 19/11/2026
 */

import Foundation
@testable import MermaidDiagrams

/// The fields of Pele's `PROJECT` (tests/support/agentflow-reference.ts) but the semantic model, each as JSON values, a
/// field left out when Mermaid leaves it undefined: metadata as the YAML read it, styles, curves and positions included.
enum AgentFlowReferenceProjection {
    /// The palette length and the configured curve of the page the reference was taken in.
    static let paletteLength = 12
    /// The curve Mermaid's configuration names for edges that set none.
    static let curve = "basis"

    static func model(of diagram: AgentFlowDiagram) -> [String: Any] {
        [
            "direction": diagram.directionKeyword.map(C4Characters.trimmed) as Any? ?? NSNull(),
            "vertices": diagram.vertices.map(vertex),
            "edges": diagram.edges.map(edge),
            "subGraphs": diagram.flows.map(flow),
            "classes": diagram.classDefinitions.map { definition in
                ["id": definition.identifier, "styles": definition.styles, "textStyles": definition.textStyles] as [String: Any]
            },
            "nodes": diagram.graph.nodes.map { node in self.node(node, in: diagram) },
            "layoutEdges": diagram.graph.edges.map { edge in layoutEdge(edge, in: diagram) },
            "mappings": diagram.mappings.map { mapping -> [Any] in
                [mapping.identifier, mapping.kind.rawValue, mapping.position.startLine, mapping.position.startColumn, mapping.position.endLine,
                 mapping.position.endColumn]
            },
            "diagnostics": diagram.diagnostics.map(diagnostic),
            "accTitle": diagram.accessibilityTitle ?? "",
            "accDescr": diagram.accessibilityDescription ?? "",
        ]
    }

    private static func vertex(_ vertex: AgentFlowVertex) -> [String: Any] {
        var fields: [String: Any] = ["id": vertex.identifier, "labelType": vertex.labelType.rawValue, "styles": vertex.styles, "classes": vertex.classes]
        if let text = vertex.text { fields["text"] = text }
        if let type = vertex.type { fields["type"] = type }
        if vertex.isConnector { fields["isConnector"] = true }
        if let link = vertex.link { fields["link"] = link }
        if let target = vertex.linkTarget { fields["linkTarget"] = target }
        if let metadata = vertex.metadata { fields["metadata"] = json(metadata) }
        if let properties = vertex.properties { fields["props"] = properties }
        return fields
    }

    private static func edge(_ edge: AgentFlowEdge) -> [String: Any] {
        var fields: [String: Any] = ["start": edge.start, "end": edge.end, "text": edge.text, "labelType": edge.labelType.rawValue, "id": edge.identifier,
                                     "isUserDefinedId": edge.isUserDefinedIdentifier, "classes": edge.classes]
        if let type = edge.type { fields["type"] = type }
        if let stroke = edge.stroke { fields["stroke"] = stroke }
        if let length = edge.length { fields["length"] = length }
        if let semantic = edge.semantic { fields["edgeSemantic"] = semantic.rawValue }
        if let style = edge.style { fields["style"] = style }
        if let interpolation = edge.interpolation { fields["interpolate"] = interpolation }
        if let metadata = edge.metadata { fields["metadata"] = json(metadata) }
        return fields
    }

    private static func flow(_ flow: AgentFlowFlow) -> [String: Any] {
        var fields: [String: Any] = ["id": flow.identifier, "nodes": flow.nodeIdentifiers, "title": flow.title, "labelType": flow.labelType.rawValue,
                                     "classes": flow.classes, "type": "flow"]
        if let direction = flow.directionKeyword { fields["dir"] = direction }
        if let metadata = flow.metadata { fields["metadata"] = json(metadata) }
        return fields
    }

    private static func node(_ node: AgentFlowGraphNode, in diagram: AgentFlowDiagram) -> [String: Any] {
        let kind = node.kind.map { kind in " af-kind-\(kind.rawValue)" } ?? ""
        let classes = (node.classes + kind).split(whereSeparator: \.isWhitespace).joined(separator: " ")
        var fields: [String: Any] = ["id": node.identifier, "shape": node.shape, "isGroup": node.isGroup, "cssClasses": classes]
        if let label = node.label { fields["label"] = label }
        if let parent = node.parentIdentifier { fields["parentId"] = parent }
        if let number = node.containerNumber { fields["colorIndex"] = AgentFlowDiagramBuilder.containerSlot(number, paletteLength: paletteLength) }
        fields["labelType"] = node.labelType.rawValue
        fields["cssCompiledStyles"] = node.compiledStyles
        if let direction = node.directionKeyword { fields["dir"] = direction }
        if let link = node.link { fields["link"] = link }
        if let target = node.linkTarget { fields["linkTarget"] = target }
        if let tooltip = node.tooltip { fields["tooltip"] = tooltip }
        if let metadata = metadata(of: node, in: diagram) { fields["metadata"] = metadata }
        return fields
    }

    /// A graph node's metadata as Mermaid's `getData` gives it: its vertex's or its flow's, a collapsed flow's with its
    /// container's type.
    private static func metadata(of node: AgentFlowGraphNode, in diagram: AgentFlowDiagram) -> Any? {
        if let flow = diagram.flows.last(where: { flow in flow.identifier == node.identifier }) {
            guard node.shape == "collapsedGroup" else { return flow.metadata.map(json) }
            var fields = flow.metadata.map(json) as? [String: Any] ?? [:]
            fields["containerType"] = "flow"
            return fields
        }
        return diagram.vertices.first { vertex in vertex.identifier == node.identifier }?.metadata.map(json)
    }

    private static func layoutEdge(_ edge: AgentFlowGraphEdge, in diagram: AgentFlowDiagram) -> [String: Any] {
        var fields: [String: Any] = ["id": edge.identifier, "start": edge.start, "end": edge.end, "arrowTypeEnd": edge.arrowTypeEnd, "label": edge.label,
                                     "type": edge.type, "labelType": edge.labelType.rawValue, "arrowTypeStart": "none",
                                     "cssCompiledStyles": edge.compiledStyles, "style": edge.style, "curve": edge.curve ?? curve,
                                     "isUserDefinedId": edge.isUserDefinedIdentifier]
        if let metadata = diagram.edges.first(where: { raw in raw.identifier == edge.identifier })?.metadata { fields["metadata"] = json(metadata) }
        if let thickness = edge.thickness { fields["thickness"] = thickness }
        if let length = edge.minimumLength { fields["minlen"] = length }
        return fields
    }

    private static func diagnostic(_ diagnostic: AgentFlowDiagnostic) -> [String: Any] {
        var fields: [String: Any] = ["id": diagnostic.identifier.rawValue, "severity": diagnostic.severity.rawValue, "message": diagnostic.message]
        if let node = diagnostic.nodeIdentifier { fields["nodeId"] = node }
        if let position = diagnostic.position {
            fields["position"] = ["startLine": position.startLine, "startColumn": position.startColumn, "endLine": position.endLine,
                                  "endColumn": position.endColumn, "startIndex": 0, "endIndex": 0]
        }
        return fields
    }

    /// A YAML value as JSON.
    private static func json(_ metadata: AgentFlowMetadata) -> Any {
        metadata.mapValues(json)
    }

    private static func json(_ value: SequenceAttributeValue) -> Any {
        switch value {
        case .null: NSNull()
        case .boolean(let value): value
        case .number(let value): value
        case .text(let value): value
        case .list(let items): items.map(json)
        case .mapping(let fields): fields.mapValues(json)
        }
    }

    /// Mermaid passes text through DOMPurify, which rewrites markup, so text holding any is not compared.
    static func comparable(_ value: Any) -> Any {
        if let text = value as? String { return text.contains(where: { character in "<>&".contains(character) }) ? "(markup)" : text }
        if let list = value as? [Any] { return list.map(comparable) }
        if let fields = value as? [String: Any] { return fields.mapValues(comparable) }
        return value
    }

    /// Whether two JSON values are the same, written with sorted keys.
    static func same(_ first: Any, _ second: Any) -> Bool {
        json(first) == json(second)
    }

    private static func json(_ value: Any) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: [value], options: [.sortedKeys, .fragmentsAllowed]) else { return "\(value)" }
        return String(decoding: data, as: UTF8.self)
    }
}
