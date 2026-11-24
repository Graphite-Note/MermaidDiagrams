/**
 * File: MermaidDiagramFlowchartPreparation.swift
 * ----------------------------------------------
 * Layer: Core
 * Description: Prepares a flowchart, with the flowchart Pele fits to a narrow column, and says what a screen reader
 *              hears of it.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 24/11/2026
 */

extension MermaidDiagramPreparationContext {
    /// A flowchart, and for a narrow column the flowchart as Pele fits it: turned to run down, with Pele's tighter gaps.
    func prepared(_ flowchart: FlowchartDiagram) throws(MermaidDiagramPreparationFailure) -> PreparedMermaidDiagram {
        let layout: FlowchartLayout
        do { layout = try FlowchartLayoutEngine.layout(flowchart, typography: typography, limits: limits) } catch { throw .flowchartLayout(error) }
        let narrow = narrowSceneIsWanted(forRegularSize: layout.size)
            ? narrowScene(of: narrowestColumnWidth.map { width in (flowchart, width) }, regularSize: layout.size, laidOut: { flowchart, width in
                try FlowchartLayoutEngine.layout(flowchart, typography: typography, limits: limits, availableWidth: width)
            }, scene: DiagramScene.init(layout:)) : nil
        return PreparedMermaidDiagram(kind: .flowchart, scene: DiagramScene(layout: layout), preparedNarrowScene: narrow,
                                      accessibility: MermaidDiagramAccessibility(flowchart: flowchart),
                                      unappliedStatementCount: flowchart.unappliedStatementCount)
    }
}

extension MermaidDiagramAccessibility {
    /// The text of each node drawn, in the order the diagram names them, then each group's title.
    init(flowchart diagram: FlowchartDiagram) {
        self.init(kind: .flowchart, title: diagram.accessibilityTitle ?? diagram.title, description: diagram.accessibilityDescription) {
            let subgraphs = diagram.subgraphs
            let groupNodes = Set(subgraphs.compactMap(\.representingNodeIndex))
            let nodeTexts = (0..<diagram.nodeCount).filter { node in !groupNodes.contains(node) }.map { node in diagram.nodeLabel(at: node).spokenText }
            return nodeTexts + subgraphs.map(\.title.spokenText).filter { title in !title.isEmpty }
        }
    }
}
