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

/// The fields of Pele's `PROJECT` (tests/support/agentflow-reference.ts) the slim reference keeps, each as JSON values,
/// a field left out when Mermaid leaves it undefined.
enum AgentFlowReferenceProjection {
    /// The palette length and the configured curve of the page the reference was taken in.
    static let paletteLength = 12

    static func model(of diagram: AgentFlowDiagram) -> [String: Any] {
        [
            "direction": diagram.directionKeyword.map(C4Characters.trimmed) as Any? ?? NSNull(),
            "vertices": diagram.vertices.map(vertex),
            "edges": diagram.edges.map(edge),
            "subGraphs": diagram.flows.map(flow),
            "nodes": diagram.graph.nodes.map(node),
            "layoutEdges": diagram.graph.edges.map(layoutEdge),
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
        return fields
    }

    private static func edge(_ edge: AgentFlowEdge) -> [String: Any] {
        var fields: [String: Any] = ["start": edge.start, "end": edge.end, "text": edge.text, "labelType": edge.labelType.rawValue, "id": edge.identifier,
                                     "isUserDefinedId": edge.isUserDefinedIdentifier, "classes": edge.classes]
        if let type = edge.type { fields["type"] = type }
        if let stroke = edge.stroke { fields["stroke"] = stroke }
        if let length = edge.length { fields["length"] = length }
        if let semantic = edge.semantic { fields["edgeSemantic"] = semantic.rawValue }
        return fields
    }

    private static func flow(_ flow: AgentFlowFlow) -> [String: Any] {
        var fields: [String: Any] = ["id": flow.identifier, "nodes": flow.nodeIdentifiers, "title": flow.title, "labelType": flow.labelType.rawValue,
                                     "classes": flow.classes]
        if let direction = flow.directionKeyword { fields["dir"] = direction }
        return fields
    }

    private static func node(_ node: AgentFlowGraphNode) -> [String: Any] {
        let kind = node.kind.map { kind in " af-kind-\(kind.rawValue)" } ?? ""
        let classes = (node.classes + kind).split(whereSeparator: \.isWhitespace).joined(separator: " ")
        var fields: [String: Any] = ["id": node.identifier, "shape": node.shape, "isGroup": node.isGroup, "cssClasses": classes]
        if let label = node.label { fields["label"] = label }
        if let parent = node.parentIdentifier { fields["parentId"] = parent }
        if let number = node.containerNumber { fields["colorIndex"] = AgentFlowDiagramBuilder.containerSlot(number, paletteLength: paletteLength) }
        return fields
    }

    private static func layoutEdge(_ edge: AgentFlowGraphEdge) -> [String: Any] {
        var fields: [String: Any] = ["id": edge.identifier, "start": edge.start, "end": edge.end, "arrowTypeEnd": edge.arrowTypeEnd, "label": edge.label]
        if let thickness = edge.thickness { fields["thickness"] = thickness }
        if let length = edge.minimumLength { fields["minlen"] = length }
        return fields
    }

    private static func diagnostic(_ diagnostic: AgentFlowDiagnostic) -> [String: Any] {
        var fields: [String: Any] = ["id": diagnostic.identifier.rawValue, "severity": diagnostic.severity.rawValue, "message": diagnostic.message]
        if let node = diagnostic.nodeIdentifier { fields["nodeId"] = node }
        return fields
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
