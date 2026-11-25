/**
 * File: MermaidDiagramStatePreparation.swift
 * ------------------------------------------
 * Layer: Core
 * Description: Prepares a state diagram, with its layout for a narrow column, and says what a screen reader hears of
 *              it.
 *
 * Authors: Bahey Shalash
 * Version: 0.2
 * Date: 25/11/2026
 */

extension MermaidDiagramPreparationContext {
    func prepared(_ stateDiagram: StateDiagram) throws(MermaidDiagramPreparationFailure) -> PreparedMermaidDiagram {
        let layout: StateDiagramLayout
        do { layout = try StateDiagramLayoutEngine.layout(stateDiagram, typography: typography, limits: limits) } catch { throw .stateDiagramLayout(error) }
        let narrow = narrowSceneIsWanted(forRegularSize: layout.size)
            ? narrowScene(of: narrowestColumnWidth.map { width in (stateDiagram, width) }, regularSize: layout.size, laidOut: { stateDiagram, width in
                try StateDiagramLayoutEngine.layout(stateDiagram, typography: typography, limits: limits, availableWidth: width)
            }, scene: { layout in DiagramScene(layout: layout, limits: limits) }) : nil
        return PreparedMermaidDiagram(kind: .stateDiagram, scene: DiagramScene(layout: layout, limits: limits), preparedNarrowScene: narrow,
                                      accessibility: MermaidDiagramAccessibility(stateDiagram: stateDiagram, layout: layout),
                                      unappliedStatementCount: stateDiagram.unappliedStatementCount)
    }
}

extension MermaidDiagramAccessibility {
    /// The names of the composite states, then of the states drawn as boxes, in the order the diagram names them: a
    /// composite state is named by its box's title, before the states it holds.
    init(stateDiagram diagram: StateDiagram, layout: StateDiagramLayout) {
        // The composites and the states alone are taken into the work, not the whole layout.
        let composites = layout.composites
        let states = layout.states
        self.init(kind: .stateDiagram, title: diagram.accessibilityTitle ?? diagram.title, description: diagram.accessibilityDescription) {
            let compositeNames = composites.compactMap { composite in composite.title?.lines.joined(separator: " ") }
            let stateNames = states.compactMap { state in state.name?.lines.joined(separator: " ") }
            return compositeNames + stateNames
        }
    }
}
