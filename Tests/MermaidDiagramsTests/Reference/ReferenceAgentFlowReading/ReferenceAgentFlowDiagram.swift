/**
 * File: ReferenceAgentFlowDiagram.swift
 * -------------------------------------
 * Layer: Tests
 * Description: 0.7.0's agent flow model (AgentFlowDiagram.swift), its lists stored whole, kept unchanged but for its
 *              name as what the reference reader makes, and the reference reading of a whole text.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 26/11/2026
 */

@testable import MermaidDiagrams

/// 0.7.0's agent flow as its reader made it, every list stored: what the model on bytes must give, list for list.
struct ReferenceAgentFlowDiagram: Equatable {
    var directionKeyword: String?
    var vertices: [AgentFlowVertex] = []
    var edges: [AgentFlowEdge] = []
    var flows: [AgentFlowFlow] = []
    var connectorIdentifiers: [String] = []
    var classDefinitions: [AgentFlowClassDefinition] = []
    var defaultEdgeStyle: [String]?
    var defaultInterpolation: String?
    var mappings: [AgentFlowElementMapping] = []
    var diagnostics: [AgentFlowDiagnostic] = []
    var graph = ReferenceAgentFlowGraph()
    var title: String?
    var accessibilityTitle: String?
    var accessibilityDescription: String?
    var options = AgentFlowOptions()

    var direction: FlowchartDirection {
        directionKeyword.flatMap(FlowchartDirection.init(keyword:)) ?? .topToBottom
    }
}

/// 0.7.0's graph of an agent flow, its lists stored whole.
struct ReferenceAgentFlowGraph: Equatable {
    var nodes: [AgentFlowGraphNode] = []
    var edges: [AgentFlowGraphEdge] = []
}

enum ReferenceAgentFlowReading {
    /// The agent flow `source` holds as 0.7.0 read it, nil when it is of another type.
    static func read(_ source: String, limits: MermaidDiagramLimits) throws(MermaidDiagramReadError) -> ReferenceAgentFlowDiagram? {
        guard source.utf8.count <= limits.maximumSourceBytes else { throw .sourceTooLarge(limitBytes: limits.maximumSourceBytes) }
        let frontEnd = try MermaidFrontEnd.read(source)
        guard frontEnd.typeKeyword == .agentFlow || frontEnd.keywordText == "agentflow-beta" else { return nil }
        var diagram = try ReferenceAgentFlowParser.parse(MermaidTextCursor(frontEnd), keyword: frontEnd.keywordText, limits: limits)
        if diagram.title == nil { diagram.title = frontEnd.frontMatterTitle }
        return diagram
    }
}
