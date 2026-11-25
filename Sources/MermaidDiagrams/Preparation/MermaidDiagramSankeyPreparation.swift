/**
 * File: MermaidDiagramSankeyPreparation.swift
 * -------------------------------------------
 * Layer: Core
 * Description: Prepares a Sankey diagram, with the chart narrowed to fit a narrow column, and says what a screen
 *              reader hears of it.
 *
 * Authors: Bahey Shalash
 * Version: 0.2
 * Date: 25/11/2026
 */

extension MermaidDiagramPreparationContext {
    /// A Sankey diagram, and for a narrow column the chart narrowed to fit it with its labels smaller (Pele's `fitWidth`).
    func prepared(_ sankey: SankeyDiagram) throws(MermaidDiagramPreparationFailure) -> PreparedMermaidDiagram {
        let layout: SankeyLayout
        do { layout = try SankeyLayoutEngine.layout(sankey, typography: typography) } catch { throw .sankeyLayout(error) }
        let narrow = narrowSceneIsWanted(forRegularSize: layout.size)
            ? narrowScene(of: sankey, regularSize: layout.size, laidOut: { sankey in
                try SankeyLayoutEngine.layout(sankey, typography: typography, availableWidth: narrowestColumnWidth)
            }, scene: { layout in DiagramScene(layout: layout, limits: limits) }) : nil
        return PreparedMermaidDiagram(kind: .sankey, scene: DiagramScene(layout: layout, limits: limits), preparedNarrowScene: narrow,
                                      accessibility: MermaidDiagramAccessibility(sankey: sankey))
    }
}

extension MermaidDiagramAccessibility {
    /// Each flow in the order of its row, with its value rounded to two decimals: “Coal to Solid: 75.57”. Mermaid's
    /// Sankey grammar has no accessibility statements: the title is the front matter's.
    init(sankey diagram: SankeyDiagram) {
        self.init(kind: .sankey, title: diagram.title, description: nil, summarySeparator: "; ") {
            let flows = diagram.links.map { link in
                let source = diagram.nodes[link.sourceIndex].name
                let target = diagram.nodes[link.targetIndex].name
                guard let value = link.value, value.isFinite, value > 0 else { return Self.joined(source, " to ", target) }
                return Self.joined(source, " to ", target, ": ", Self.written((value * 100).rounded() / 100))
            }
            return flows
        }
    }
}
