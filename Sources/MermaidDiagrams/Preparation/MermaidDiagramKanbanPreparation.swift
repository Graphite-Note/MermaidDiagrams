/**
 * File: MermaidDiagramKanbanPreparation.swift
 * -------------------------------------------
 * Layer: Core
 * Description: Prepares a kanban board, with the board folded into rows of columns for a narrow column, and says what
 *              a screen reader hears of it.
 *
 * Authors: Bahey Shalash
 * Version: 0.2
 * Date: 25/11/2026
 */

extension MermaidDiagramPreparationContext {
    /// A kanban board, and for a narrow column the board folded into rows of columns that fit it.
    func prepared(_ board: KanbanBoard) -> PreparedMermaidDiagram {
        let layout = KanbanLayoutEngine.layout(board, typography: typography)
        let narrow = narrowSceneIsWanted(forRegularSize: layout.size)
            ? narrowScene(of: board, regularSize: layout.size, laidOut: { board in
                KanbanLayoutEngine.layout(board, typography: typography, maximumWidth: narrowestColumnWidth)
            }, scene: { [limits] layout in DiagramScene(layout: layout, limits: limits) }) : nil
        return PreparedMermaidDiagram(kind: .kanban, scene: DiagramScene(layout: layout, limits: limits), preparedNarrowScene: narrow,
                                      accessibility: MermaidDiagramAccessibility(kanban: board))
    }
}

extension MermaidDiagramAccessibility {
    /// Each column with its cards, in the board's order: “Todo: Write the docs, Fix the bug”.
    init(kanban board: KanbanBoard) {
        self.init(kind: .kanban, title: board.title, description: nil, summarySeparator: "; ") {
            let columns = board.columns.map { column in
                column.cards.isEmpty ? column.label.spokenText
                    : column.label.spokenText + ": " + column.cards.map(\.label.spokenText).joined(separator: ", ")
            }
            return columns
        }
    }
}
