/**
 * File: MermaidDiagramTreeViewPreparation.swift
 * ---------------------------------------------
 * Layer: Core
 * Description: Prepares a tree view, with the tree laid out tight for a narrow column, and says what a screen reader
 *              hears of it.
 *
 * Authors: Bahey Shalash
 * Version: 0.2
 * Date: 25/11/2026
 */

extension MermaidDiagramPreparationContext {
    /// A tree view, and for a narrow column the tree laid out tight.
    func prepared(_ tree: TreeViewDiagram) -> PreparedMermaidDiagram {
        let layout = TreeViewLayoutEngine.layout(tree, typography: typography)
        let narrow = narrowSceneIsWanted(forRegularSize: layout.size)
            ? narrowScene(of: tree, regularSize: layout.size, laidOut: { tree in
                TreeViewLayoutEngine.layout(tree, typography: typography, maximumWidth: narrowestColumnWidth)
            }, scene: { layout in DiagramScene(layout: layout, limits: limits) }) : nil
        return PreparedMermaidDiagram(kind: .treeView, scene: DiagramScene(layout: layout, limits: limits), preparedNarrowScene: narrow,
                                      accessibility: MermaidDiagramAccessibility(treeView: tree))
    }
}

extension MermaidDiagramAccessibility {
    /// Each entry's name in the order written, a folder's with its `/`.
    init(treeView diagram: TreeViewDiagram) {
        self.init(kind: .treeView, title: diagram.accessibilityTitle ?? diagram.title,
                  description: diagram.accessibilityDescription) {
            diagram.entries.map { entry in entry.isFolder ? entry.name + "/" : entry.name }
        }
    }
}
