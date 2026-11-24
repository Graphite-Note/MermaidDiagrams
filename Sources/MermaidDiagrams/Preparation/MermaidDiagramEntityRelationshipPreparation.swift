/**
 * File: MermaidDiagramEntityRelationshipPreparation.swift
 * -------------------------------------------------------
 * Layer: Core
 * Description: Prepares an entity relationship diagram, with the diagram turned top to bottom for a narrow column,
 *              and says what a screen reader hears of it.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 24/11/2026
 */

extension MermaidDiagramPreparationContext {
    func prepared(_ diagram: EntityRelationshipDiagram) throws(MermaidDiagramPreparationFailure) -> PreparedMermaidDiagram {
        let layout: EntityRelationshipLayout
        do {
            layout = try EntityRelationshipLayoutEngine.layout(diagram, typography: typography, limits: limits)
        } catch {
            throw .entityRelationshipLayout(error)
        }
        let narrow = turnedNarrowSceneIsWanted(forRegularSize: layout.size)
            ? turnedNarrowScene(of: diagram.turnedTopToBottom, regularSize: layout.size, laidOut: { turned in
                try EntityRelationshipLayoutEngine.layout(turned, typography: typography, limits: limits)
            }, scene: DiagramScene.init(layout:)) : nil
        return PreparedMermaidDiagram(kind: .entityRelationship, scene: DiagramScene(layout: layout), preparedNarrowScene: narrow,
                                      accessibility: MermaidDiagramAccessibility(entityRelationship: diagram),
                                      unappliedStatementCount: diagram.unappliedStatementCount)
    }
}

extension MermaidDiagramAccessibility {
    /// Each entity's text, then each relationship as its two entities around its label: “CUSTOMER places ORDER”.
    init(entityRelationship diagram: EntityRelationshipDiagram) {
        self.init(kind: .entityRelationship, title: diagram.accessibilityTitle ?? diagram.title, description: diagram.accessibilityDescription) {
            let entityTexts = diagram.entities.map(\.label.spokenText)
            let relationships = diagram.relationships.map { relationship in
                [entityTexts[relationship.firstEntityIndex], relationship.label.spokenText, entityTexts[relationship.secondEntityIndex]]
                    .filter { part in !part.isEmpty }.joined(separator: " ")
            }
            return entityTexts + relationships
        }
    }
}
