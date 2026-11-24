/**
 * File: MermaidDiagramRailroadPreparation.swift
 * ---------------------------------------------
 * Layer: Core
 * Description: Prepares a railroad diagram, with its long sequences folded into rows for a narrow column, and says
 *              what a screen reader hears of it.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 24/11/2026
 */

extension MermaidDiagramPreparationContext {
    /// A railroad diagram, and for a narrow column the diagram with Pele's tighter gaps and its long sequences folded
    /// into rows that fit the column.
    func prepared(_ diagram: RailroadDiagram) -> PreparedMermaidDiagram {
        let layout = RailroadLayoutEngine.layout(diagram, typography: typography)
        let narrow = narrowSceneIsWanted(forRegularSize: layout.size)
            ? narrowScene(of: narrowestColumnWidth.map { width in (diagram, width) }, regularSize: layout.size, laidOut: { diagram, width in
                RailroadLayoutEngine.layout(diagram, typography: typography, columnWidth: width)
            }, scene: DiagramScene.init(layout:)) : nil
        return PreparedMermaidDiagram(kind: .railroad, scene: DiagramScene(layout: layout), preparedNarrowScene: narrow,
                                      accessibility: MermaidDiagramAccessibility(railroad: diagram))
    }
}

extension MermaidDiagramAccessibility {
    /// Each rule by its name, in the order they are written.
    init(railroad diagram: RailroadDiagram) {
        self.init(kind: .railroad, title: diagram.accessibilityTitle ?? diagram.title,
                  description: diagram.accessibilityDescription) {
            diagram.rules.map(\.name)
        }
    }
}
