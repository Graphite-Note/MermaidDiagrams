/**
 * File: MermaidDiagramLayeredPreparation.swift
 * --------------------------------------------
 * Layer: Core
 * Description: The preparation of the layered types added after the first graphs, requirement diagrams and swimlane
 *              diagrams: their scenes, their narrow scenes, and what a screen reader says of them.
 *
 * Authors: Bahey Shalash
 * Version: 0.5
 * Date: 24/11/2026
 */

extension MermaidDiagramPreparationContext {
    /// A requirement diagram, and for a narrow column the diagram turned to run down when it runs across, as Pele's
    /// `turnToFit` turns it.
    func prepared(_ diagram: RequirementDiagram) throws(MermaidDiagramPreparationFailure) -> PreparedMermaidDiagram {
        let layout: RequirementLayout
        do { layout = try RequirementLayoutEngine.layout(diagram, typography: typography, limits: limits) } catch { throw .requirementLayout(error) }
        let narrow = turnedNarrowSceneIsWanted(forRegularSize: layout.size)
            ? turnedNarrowScene(of: diagram.turnedToRunDown, regularSize: layout.size, laidOut: { turned in
                try RequirementLayoutEngine.layout(turned, typography: typography, limits: limits)
            }, scene: DiagramScene.init(layout:)) : nil
        return PreparedMermaidDiagram(kind: .requirement, scene: DiagramScene(layout: layout), preparedNarrowScene: narrow,
                                      accessibility: MermaidDiagramAccessibility(requirement: diagram),
                                      unappliedStatementCount: diagram.unappliedStatementCount)
    }
}

extension MermaidDiagramAccessibility {
    /// Each requirement and element by its kind and name, then each relation as its two ends around its kind: “Requirement
    /// test_req”, “test_entity satisfies test_req”.
    init(requirement diagram: RequirementDiagram) {
        self.init(kind: .requirement, title: diagram.accessibilityTitle ?? diagram.title, description: diagram.accessibilityDescription) {
            let requirements = diagram.requirements.map { requirement in "\(requirement.kind.rawValue) \(requirement.name)" }
            let elements = diagram.elements.map { element in "Element \(element.name)" }
            let relations = diagram.relations.map { relation in "\(relation.source) \(relation.kind.rawValue) \(relation.target)" }
            return requirements + elements + relations
        }
    }
}

extension MermaidDiagramPreparationContext {
    /// A swimlane diagram, and for a narrow column the diagram turned to run down when it runs across, in Pele's tight
    /// measurements, as Pele's `turnToFit` and `tighten` draw it.
    func prepared(swimlane diagram: FlowchartDiagram) -> PreparedMermaidDiagram {
        let layout = SwimlaneLayoutEngine.layout(diagram, typography: typography)
        let narrow = narrowSceneIsWanted(forRegularSize: layout.size)
            ? narrowScene(of: narrowestColumnWidth.map { width in (diagram, width) }, regularSize: layout.size, laidOut: { diagram, width in
                SwimlaneLayoutEngine.layout(diagram, typography: typography, availableWidth: width)
            }, scene: DiagramScene.init(layout:)) : nil
        return PreparedMermaidDiagram(kind: .swimlane, scene: DiagramScene(layout: layout), preparedNarrowScene: narrow,
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
