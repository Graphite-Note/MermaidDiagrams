/**
 * File: MermaidDiagramInfoPreparation.swift
 * -----------------------------------------
 * Layer: Core
 * Description: Prepares the info diagram and says what a screen reader hears of it.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 24/11/2026
 */

extension MermaidDiagramPreparationContext {
    func prepared(_ info: InfoDiagram) -> PreparedMermaidDiagram {
        PreparedMermaidDiagram(kind: .info, scene: DiagramScene(layout: InfoDiagramLayoutEngine.layout(info, typography: typography)),
                               accessibility: MermaidDiagramAccessibility(info: info))
    }
}

extension MermaidDiagramAccessibility {
    /// The package's name and version, which is all an info diagram shows besides its title.
    init(info diagram: InfoDiagram) {
        self.init(kind: .info, title: diagram.accessibilityTitle ?? diagram.title,
                  description: diagram.accessibilityDescription) {
            [MermaidDiagramsVersion.text]
        }
    }
}
