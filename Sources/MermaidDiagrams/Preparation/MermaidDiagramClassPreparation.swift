/**
 * File: MermaidDiagramClassPreparation.swift
 * ------------------------------------------
 * Layer: Core
 * Description: Prepares a class diagram, with its layout for a narrow column, and says what a screen reader hears of
 *              it.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 24/11/2026
 */

extension MermaidDiagramPreparationContext {
    func prepared(_ classDiagram: ClassDiagram) throws(MermaidDiagramPreparationFailure) -> PreparedMermaidDiagram {
        let layout: ClassDiagramLayout
        do { layout = try ClassDiagramLayoutEngine.layout(classDiagram, typography: typography, limits: limits) } catch { throw .classDiagramLayout(error) }
        let narrow = narrowSceneIsWanted(forRegularSize: layout.size)
            ? narrowScene(of: narrowestColumnWidth.map { width in (classDiagram, width) }, regularSize: layout.size, laidOut: { classDiagram, width in
                try ClassDiagramLayoutEngine.layout(classDiagram, typography: typography, limits: limits, availableWidth: width)
            }, scene: DiagramScene.init(layout:)) : nil
        return PreparedMermaidDiagram(kind: .classDiagram, scene: DiagramScene(layout: layout), preparedNarrowScene: narrow,
                                      accessibility: MermaidDiagramAccessibility(classDiagram: classDiagram),
                                      unappliedStatementCount: classDiagram.unappliedStatementCount)
    }
}

extension MermaidDiagramAccessibility {
    /// The name of each class as its box shows it, in the order the diagram names them.
    init(classDiagram diagram: ClassDiagram) {
        self.init(kind: .classDiagram, title: diagram.accessibilityTitle ?? diagram.title,
                  description: diagram.accessibilityDescription) {
            diagram.classes.map(\.displayedName.spokenText)
        }
    }
}
