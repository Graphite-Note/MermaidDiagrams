/**
 * File: MermaidDiagramAgentFlowPreparation.swift
 * ----------------------------------------------
 * Layer: Core
 * Description: The preparation of an agent flow: its scene, the scene of the diagram turned to run down for a narrow
 *              column when it runs across, and what a screen reader says of it.
 *
 * Authors: Bahey Shalash
 * Version: 0.3
 * Date: 23/11/2026
 */

extension MermaidDiagramPreparationContext {
    /// An agent flow, and for a narrow column, when it runs across, the diagram laid out to run down, as Pele's
    /// `turnToFit` draws it (an agent flow has no tighter drawing). Its layout refuses as a flowchart's does.
    func prepared(_ diagram: AgentFlowDiagram) throws(MermaidDiagramPreparationFailure) -> PreparedMermaidDiagram {
        let layout: AgentFlowLayout
        do {
            layout = try AgentFlowLayoutEngine.layout(diagram, typography: typography, limits: limits)
        } catch {
            throw .flowchartLayout(error)
        }
        let turned: AgentFlowDiagram? = diagram.direction.runsAcross ? diagram : nil
        let narrow = turnedNarrowSceneIsWanted(forRegularSize: layout.size)
            ? turnedNarrowScene(of: turned, regularSize: layout.size, laidOut: { turned in
                try AgentFlowLayoutEngine.layout(turned, typography: typography, limits: limits, isTurnedToRunDown: true)
            }, scene: DiagramScene.init(layout:)) : nil
        return PreparedMermaidDiagram(kind: .agentFlow, scene: DiagramScene(layout: layout), preparedNarrowScene: narrow,
                                      accessibility: MermaidDiagramAccessibility(agentFlow: diagram))
    }
}

extension MermaidDiagramAccessibility {
    /// Each node drawn by its text, in the graph's order (flows first, by their titles), each flow without a title
    /// left out.
    init(agentFlow diagram: AgentFlowDiagram) {
        let texts = diagram.graph.nodes.compactMap { node -> String? in
            let spoken = AgentFlowMeasurement.label(node.label, type: node.labelType).spokenText
            return spoken.isEmpty ? nil : spoken
        }
        self.init(kind: .agentFlow, title: diagram.accessibilityTitle ?? diagram.title, description: diagram.accessibilityDescription,
                  summary: texts)
    }
}
