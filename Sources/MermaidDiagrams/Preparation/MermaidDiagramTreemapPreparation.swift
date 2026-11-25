/**
 * File: MermaidDiagramTreemapPreparation.swift
 * --------------------------------------------
 * Layer: Core
 * Description: Prepares a treemap, with its layout for a narrow column, and says what a screen reader hears of it.
 *
 * Authors: Bahey Shalash
 * Version: 0.2
 * Date: 25/11/2026
 */

import Foundation

extension MermaidDiagramPreparationContext {
    func prepared(_ treemap: TreemapDiagram) -> PreparedMermaidDiagram {
        let layout = TreemapLayoutEngine.layout(treemap, typography: typography)
        let narrow = narrowSceneIsWanted(forRegularSize: layout.size)
            ? narrowScene(of: narrowestColumnWidth.map { width in (treemap, width) }, regularSize: layout.size, laidOut: { treemap, width in
                TreemapLayoutEngine.layout(treemap, typography: typography, availableWidth: width)
            }, scene: { layout in DiagramScene(layout: layout, limits: limits) }) : nil
        return PreparedMermaidDiagram(kind: .treemap, scene: DiagramScene(layout: layout, limits: limits), preparedNarrowScene: narrow,
                                      accessibility: MermaidDiagramAccessibility(treemap: treemap), unappliedStatementCount: treemap.unappliedStatementCount)
    }
}

extension MermaidDiagramAccessibility {
    /// Each node in the order it is written: a section by its name, a leaf with its value as the treemap writes it
    /// (“Item A1: 10”).
    init(treemap diagram: TreemapDiagram) {
        self.init(kind: .treemap, title: diagram.accessibilityTitle ?? diagram.title,
                  description: diagram.accessibilityDescription, summarySeparator: "; ") {
            let format = TreemapValueFormat(specifier: diagram.options.valueFormat)
            let nodes = diagram.nodes.map { node in
                let name = DiagramLabelDecoder.decodingEntities(node.name).trimmingCharacters(in: .whitespacesAndNewlines)
                guard !node.isSection, node.size > 0, diagram.options.showsValues else { return name }
                return "\(name): \(format.text(node.size))"
            }
            return nodes
        }
    }
}
