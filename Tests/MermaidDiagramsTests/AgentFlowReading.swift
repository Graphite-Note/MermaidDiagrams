/**
 * File: AgentFlowReading.swift
 * ----------------------------
 * Layer: Tests
 * Description: Reads agent flows for the tests: the diagram, the error reading it throws, and its elements by
 *              identifier, as Mermaid's specs ask for them.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 19/11/2026
 */

@testable import MermaidDiagrams

enum AgentFlowReading {
    static func diagram(_ source: String, limits: MermaidDiagramLimits = .standard) throws(MermaidDiagramReadError) -> AgentFlowDiagram {
        guard case .agentFlow(let diagram) = try MermaidDiagramReader.read(source, limits: limits) else { throw .noDiagram }
        return diagram
    }

    /// The error reading `source` throws, or nil when it reads.
    static func readError(_ source: String, limits: MermaidDiagramLimits = .standard) -> MermaidDiagramReadError? {
        do {
            _ = try diagram(source, limits: limits)
            return nil
        } catch {
            return error
        }
    }

    /// The agent flow's own problem, or nil.
    static func problem(_ source: String) -> AgentFlowSyntaxProblem? {
        guard case .invalidSyntax(_, .agentFlow(let problem)) = readError(source) else { return nil }
        return problem
    }

    static func vertex(_ identifier: String, in diagram: AgentFlowDiagram) -> AgentFlowVertex? {
        diagram.vertices.first { vertex in vertex.identifier == identifier }
    }

    static func flow(_ identifier: String, in diagram: AgentFlowDiagram) -> AgentFlowFlow? {
        diagram.flows.first { flow in flow.identifier == identifier }
    }

    static func node(_ identifier: String, in diagram: AgentFlowDiagram) -> AgentFlowGraphNode? {
        diagram.graph.nodes.first { node in node.identifier == identifier }
    }

    /// A metadata value as text, as the specs compare them.
    static func metadata(_ key: String, of vertex: AgentFlowVertex?) -> String? {
        vertex?.metadataText(key)
    }

    static func metadata(_ key: String, of flow: AgentFlowFlow?) -> String? {
        flow?.metadata?[key]?.javaScriptText
    }

    /// What a node means, as Mermaid's semantic model gives it.
    static func kind(_ identifier: String, in diagram: AgentFlowDiagram) -> AgentFlowVertexKind? {
        vertex(identifier, in: diagram).map(AgentFlowShapes.kind(of:))
    }
}
