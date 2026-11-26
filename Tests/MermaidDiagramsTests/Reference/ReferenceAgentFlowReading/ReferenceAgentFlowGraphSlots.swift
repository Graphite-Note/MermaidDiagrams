/**
 * File: ReferenceAgentFlowGraphSlots.swift
 * ----------------------------------------
 * Layer: Tests
 * Description: 0.7.0's agent flow reader on UTF-16 code units (AgentFlowGraphSlots.swift), kept unchanged but for its
 *              names as the reference the reader on bytes is compared with (AgentFlowReadingEquivalenceTests).
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 26/11/2026
 */

@testable import MermaidDiagrams

extension ReferenceAgentFlowDiagramBuilder {
    /// Every node's shape reduced to one an agent flow draws, the removed and unsupported ones reported.
    mutating func normalizeShapes(of graph: inout ReferenceAgentFlowGraph) {
        for index in graph.nodes.indices where !graph.nodes[index].isGroup {
            let normalized = ReferenceAgentFlowShapes.normalized(graph.nodes[index].shape)
            graph.nodes[index].shape = normalized.shape
            guard let problem = normalized.problem else { continue }
            emitDiagnostic(problem.identifier, severity: problem.identifier == .shapeRemoved ? .error : .warning,
                           nodeIdentifier: graph.nodes[index].identifier, message: problem.message)
        }
    }

    /// Containers numbered in the order they were written: a walk of the nesting, parents first. The flows themselves
    /// are listed in the order their blocks closed, a nested flow before its parent.
    func containerOrder(parents: [String: String]) -> [String: Int] {
        var children: [String: [String]] = [:]
        for flow in diagram.flows {
            guard let parent = parents[flow.identifier] else { continue }
            children[parent, default: []].append(flow.identifier)
        }
        var order: [String: Int] = [:]
        for flow in diagram.flows where parents[flow.identifier] == nil {
            var pending = [flow.identifier]
            while let identifier = pending.popLast() {
                guard order[identifier] == nil else { continue }
                order[identifier] = order.count
                pending.append(contentsOf: (children[identifier] ?? []).reversed())
            }
        }
        return order
    }

    /// A node takes the color of its kind, from a fixed slot, so that editing the diagram around it never recolors it;
    /// containers count through the slots above the kinds in the order they were declared, a collapsed one keeping its
    /// slot, so that a frame does not take the color of a node inside it.
    func assignColorSlots(to graph: inout ReferenceAgentFlowGraph, order: [String: Int], paletteLength: Int) {
        var fallback = order.count
        for index in graph.nodes.indices {
            let node = graph.nodes[index]
            if node.isGroup || node.shape == "collapsedGroup" {
                let number = order[node.identifier] ?? fallback
                if order[node.identifier] == nil { fallback += 1 }
                graph.nodes[index].containerNumber = number
                graph.nodes[index].colorIndex = Self.containerSlot(number, paletteLength: paletteLength)
                continue
            }
            if connectorIdentifiers.contains(node.identifier) {
                graph.nodes[index].kind = .connector
            } else if let vertex = vertexIndices[node.identifier] {
                graph.nodes[index].kind = ReferenceAgentFlowShapes.kind(of: diagram.vertices[vertex])
            }
        }
    }

    /// The slots containers count through, above the kinds: at least one, so that a palette shorter than the kinds
    /// still gives containers a slot.
    static func containerSlot(_ number: Int, paletteLength: Int) -> Int {
        let kindCount = AgentFlowVertexKind.allCases.count
        let slot = kindCount + number % max(1, paletteLength - kindCount)
        return paletteLength > 0 ? slot % paletteLength : slot
    }

    /// Records a diagnostic once, where the node it is about was first named.
    mutating func emitDiagnostic(_ identifier: AgentFlowDiagnostic.Identifier, severity: AgentFlowDiagnostic.Severity, nodeIdentifier: String,
                                 message: String) {
        let position = firstMappings[nodeIdentifier].map { index in diagram.mappings[index].position }
        let diagnostic = AgentFlowDiagnostic(identifier: identifier, severity: severity, message: message,
                                             nodeIdentifier: nodeIdentifier.isEmpty ? nil : nodeIdentifier, position: position)
        if reportedDiagnostics[nodeIdentifier]?.contains(diagnostic) == true { return }
        reportedDiagnostics[nodeIdentifier, default: []].append(diagnostic)
        diagram.diagnostics.append(diagnostic)
    }
}
