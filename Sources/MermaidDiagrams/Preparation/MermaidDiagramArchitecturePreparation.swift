/**
 * File: MermaidDiagramArchitecturePreparation.swift
 * -------------------------------------------------
 * Layer: Core
 * Description: Prepares an architecture diagram, with the diagram drawn tight for a narrow column, and says what a
 *              screen reader hears of it.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 24/11/2026
 */

extension MermaidDiagramPreparationContext {
    /// An architecture diagram, and for a narrow column the diagram drawn tight, as Pele's `tighten` draws it.
    func prepared(_ diagram: ArchitectureDiagram) -> PreparedMermaidDiagram {
        let layout = ArchitectureLayoutEngine.layout(diagram, typography: typography)
        let narrow = narrowSceneIsWanted(forRegularSize: layout.size)
            ? narrowScene(of: narrowestColumnWidth.map { width in (diagram, width) }, regularSize: layout.size, laidOut: { diagram, width in
                ArchitectureLayoutEngine.layout(diagram, typography: typography, availableWidth: width, isTight: true)
            }, scene: DiagramScene.init(layout:)) : nil
        return PreparedMermaidDiagram(kind: .architecture, scene: DiagramScene(layout: layout), preparedNarrowScene: narrow,
                                      accessibility: MermaidDiagramAccessibility(architecture: diagram))
    }
}

extension MermaidDiagramAccessibility {
    /// Each service by its title (its identifier without one), each group by its title, in the order written.
    init(architecture diagram: ArchitectureDiagram) {
        self.init(kind: .architecture, title: diagram.accessibilityTitle ?? diagram.title, description: diagram.accessibilityDescription) {
            let services = diagram.nodes.filter { node in node.kind == .service }.map { node in node.title ?? node.identifier }
            let groups = diagram.groups.map { group in group.title ?? group.identifier }
            return groups + services
        }
    }
}
