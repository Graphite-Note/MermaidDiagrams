/**
 * File: MermaidDiagramMindmapPreparation.swift
 * --------------------------------------------
 * Layer: Core
 * Description: Prepares a mindmap, with the mindmap as an outline running down for a narrow column, and says what a
 *              screen reader hears of it.
 *
 * Authors: Bahey Shalash
 * Version: 0.2
 * Date: 25/11/2026
 */

extension MermaidDiagramPreparationContext {
    /// A mindmap, and for a narrow column the mindmap as an outline running down (Pele's `turnToFit`).
    func prepared(_ mindmap: MindmapDiagram) -> PreparedMermaidDiagram {
        let layout = MindmapLayoutEngine.layout(mindmap, typography: typography)
        let narrow = narrowSceneIsWanted(forRegularSize: layout.size)
            ? narrowScene(of: mindmap, regularSize: layout.size, laidOut: { mindmap in
                MindmapLayoutEngine.layout(mindmap, typography: typography, availableWidth: narrowestColumnWidth)
            }, scene: { layout in DiagramScene(layout: layout, limits: limits) }) : nil
        return PreparedMermaidDiagram(kind: .mindmap, scene: DiagramScene(layout: layout, limits: limits), preparedNarrowScene: narrow,
                                      accessibility: MermaidDiagramAccessibility(mindmap: mindmap))
    }
}

extension MermaidDiagramAccessibility {
    /// The text of each node, the root first, in the order the diagram writes them.
    init(mindmap diagram: MindmapDiagram) {
        self.init(kind: .mindmap, title: diagram.accessibilityTitle ?? diagram.title,
                  description: diagram.accessibilityDescription) {
            diagram.nodes.map(\.label.spokenText)
        }
    }
}
