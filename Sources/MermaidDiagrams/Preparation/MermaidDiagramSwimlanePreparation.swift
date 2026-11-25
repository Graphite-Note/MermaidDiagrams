/**
 * File: MermaidDiagramSwimlanePreparation.swift
 * ---------------------------------------------
 * Layer: Core
 * Description: Prepares a swimlane diagram, with the diagram turned to run down in Pele's tight measurements for a
 *              narrow column, the regular layout not laid out again, and says what a screen reader hears of it.
 *
 * Authors: Bahey Shalash
 * Version: 0.3
 * Date: 25/11/2026
 */

extension MermaidDiagramPreparationContext {
    /// A swimlane diagram, and for a narrow column the diagram turned to run down when it runs across, in Pele's tight
    /// measurements, as Pele's `turnToFit` and `tighten` draw it.
    func prepared(swimlane diagram: FlowchartDiagram) -> PreparedMermaidDiagram {
        let layout = SwimlaneLayoutEngine.layout(diagram, typography: typography)
        // The regular layout is the one across in Pele's measurements that fitting tries first: it is not laid out again.
        let regularWidth = layout.size.width
        let narrow = narrowSceneIsWanted(forRegularSize: layout.size)
            ? narrowScene(of: narrowestColumnWidth.map { width in (diagram, width) }, regularSize: layout.size, laidOut: { diagram, width in
                try SwimlaneLayoutEngine.narrowLayout(diagram, typography: typography, availableWidth: width, regularWidth: regularWidth)
            }, scene: { layout in DiagramScene(layout: layout, limits: limits) }) : nil
        return PreparedMermaidDiagram(kind: .swimlane, scene: DiagramScene(layout: layout, limits: limits), preparedNarrowScene: narrow,
                                      accessibility: MermaidDiagramAccessibility(swimlane: diagram),
                                      unappliedStatementCount: diagram.unappliedStatementCount)
    }
}

extension MermaidDiagramAccessibility {
    /// Each lane's title, then the text of each node drawn, as a flowchart's: “Customer, Warehouse, Browse catalogue, Pay”;
    /// its title and description a flowchart's.
    init(swimlane diagram: FlowchartDiagram) {
        let flowchart = MermaidDiagramAccessibility(flowchart: diagram)
        self.init(kind: .swimlane, title: flowchart.title, description: flowchart.description) {
            let nesting = FlowchartClusterNesting(diagram: diagram)
            let subgraphs = diagram.subgraphs
            let laneTitles = subgraphs.indices.filter { subgraph in nesting.subgraphParents[subgraph] == nil }
                .map { subgraph in subgraphs[subgraph].title.spokenText }.filter { title in !title.isEmpty }
            let groupNodes = Set(subgraphs.compactMap(\.representingNodeIndex))
            let nodeTexts = (0..<diagram.nodeCount).filter { node in !groupNodes.contains(node) }.map { node in diagram.nodeLabel(at: node).spokenText }
            return laneTitles + nodeTexts
        }
    }
}
