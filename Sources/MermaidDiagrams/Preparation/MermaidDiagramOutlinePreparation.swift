/**
 * File: MermaidDiagramOutlinePreparation.swift
 * --------------------------------------------
 * Layer: Core
 * Description: Prepares kanban boards, tree views and Ishikawa diagrams, each with its layout for a narrow column, and
 *              says what a screen reader hears of them.
 *
 * Authors: Bahey Shalash
 * Version: 0.2
 * Date: 23/11/2026
 */

import CoreGraphics

extension MermaidDiagramPreparationContext {
    /// A kanban board, and for a narrow column the board folded into rows of columns that fit it.
    func prepared(_ board: KanbanBoard) -> PreparedMermaidDiagram {
        let layout = KanbanLayoutEngine.layout(board, typography: typography)
        let narrow = narrowSceneIsWanted(forRegularSize: layout.size)
            ? narrowScene(of: board, regularSize: layout.size, laidOut: { board in
                KanbanLayoutEngine.layout(board, typography: typography, maximumWidth: narrowestColumnWidth)
            }, scene: DiagramScene.init(layout:)) : nil
        return PreparedMermaidDiagram(kind: .kanban, scene: DiagramScene(layout: layout), preparedNarrowScene: narrow,
                                      accessibility: MermaidDiagramAccessibility(kanban: board))
    }

    /// A tree view, and for a narrow column the tree laid out tight.
    func prepared(_ tree: TreeViewDiagram) -> PreparedMermaidDiagram {
        let layout = TreeViewLayoutEngine.layout(tree, typography: typography)
        let narrow = narrowSceneIsWanted(forRegularSize: layout.size)
            ? narrowScene(of: tree, regularSize: layout.size, laidOut: { tree in
                TreeViewLayoutEngine.layout(tree, typography: typography, maximumWidth: narrowestColumnWidth)
            }, scene: DiagramScene.init(layout:)) : nil
        return PreparedMermaidDiagram(kind: .treeView, scene: DiagramScene(layout: layout), preparedNarrowScene: narrow,
                                      accessibility: MermaidDiagramAccessibility(treeView: tree))
    }

    /// An Ishikawa diagram, and for a narrow column the diagram running down as an indented list.
    func prepared(_ diagram: IshikawaDiagram) -> PreparedMermaidDiagram {
        let layout = IshikawaLayoutEngine.layout(diagram, typography: typography)
        let narrow = narrowSceneIsWanted(forRegularSize: layout.size)
            ? narrowScene(of: diagram, regularSize: layout.size, laidOut: { diagram in
                IshikawaLayoutEngine.layout(diagram, typography: typography, maximumWidth: narrowestColumnWidth)
            }, scene: DiagramScene.init(layout:)) : nil
        return PreparedMermaidDiagram(kind: .ishikawa, scene: DiagramScene(layout: layout), preparedNarrowScene: narrow,
                                      accessibility: MermaidDiagramAccessibility(ishikawa: diagram))
    }
}

extension MermaidDiagramAccessibility {
    /// Each column with its cards, in the board's order: “Todo: Write the docs, Fix the bug”.
    init(kanban board: KanbanBoard) {
        let columns = board.columns.map { column in
            column.cards.isEmpty ? column.label.spokenText
                : column.label.spokenText + ": " + column.cards.map(\.label.spokenText).joined(separator: ", ")
        }
        self.init(kind: .kanban, title: board.title, description: nil, summary: columns, summarySeparator: "; ")
    }

    /// Each entry's name in the order written, a folder's with its `/`.
    init(treeView diagram: TreeViewDiagram) {
        self.init(kind: .treeView, title: diagram.accessibilityTitle ?? diagram.title, description: diagram.accessibilityDescription,
                  summary: diagram.entries.map { entry in entry.isFolder ? entry.name + "/" : entry.name })
    }

    /// The effect, then each category with its causes in the order written: “Blurry photo; Process: Out of focus, Too slow”.
    init(ishikawa diagram: IshikawaDiagram) {
        var summary: [String] = []
        if let effect = diagram.nodes.first {
            summary.append(effect.text)
            for categoryIndex in effect.childIndices {
                var causes: [String] = []
                var pending = Array(diagram.nodes[categoryIndex].childIndices.reversed())
                while let index = pending.popLast() {
                    causes.append(diagram.nodes[index].text)
                    pending += diagram.nodes[index].childIndices.reversed()
                }
                let category = diagram.nodes[categoryIndex].text
                summary.append(causes.isEmpty ? category : category + ": " + causes.joined(separator: ", "))
            }
        }
        self.init(kind: .ishikawa, title: diagram.title, description: nil, summary: summary, summarySeparator: "; ")
    }
}
