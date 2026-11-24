/**
 * File: MermaidDiagramRequirementPreparation.swift
 * ------------------------------------------------
 * Layer: Core
 * Description: Prepares a requirement diagram, with the diagram turned to run down for a narrow column, and says what
 *              a screen reader hears of it.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 24/11/2026
 */

extension MermaidDiagramPreparationContext {
    /// A requirement diagram, and for a narrow column the diagram turned to run down when it runs across, as Pele's
    /// `turnToFit` turns it.
    func prepared(_ diagram: RequirementDiagram) throws(MermaidDiagramPreparationFailure) -> PreparedMermaidDiagram {
        let layout: RequirementLayout
        do { layout = try RequirementLayoutEngine.layout(diagram, typography: typography, limits: limits) } catch { throw .requirementLayout(error) }
        let narrow = turnedNarrowSceneIsWanted(forRegularSize: layout.size)
            ? turnedNarrowScene(of: diagram.turnedToRunDown, regularSize: layout.size, laidOut: { turned in
                try RequirementLayoutEngine.layout(turned, typography: typography, limits: limits)
            }, scene: DiagramScene.init(layout:)) : nil
        return PreparedMermaidDiagram(kind: .requirement, scene: DiagramScene(layout: layout), preparedNarrowScene: narrow,
                                      accessibility: MermaidDiagramAccessibility(requirement: diagram),
                                      unappliedStatementCount: diagram.unappliedStatementCount)
    }
}

extension MermaidDiagramAccessibility {
    /// Each requirement and element by its kind and name, then each relation as its two ends around its kind: “Requirement
    /// test_req”, “test_entity satisfies test_req”.
    init(requirement diagram: RequirementDiagram) {
        self.init(kind: .requirement, title: diagram.accessibilityTitle ?? diagram.title, description: diagram.accessibilityDescription) {
            let requirements = diagram.requirements.map { requirement in "\(requirement.kind.rawValue) \(requirement.name)" }
            let elements = diagram.elements.map { element in "Element \(element.name)" }
            let relations = diagram.relations.map { relation in "\(relation.source) \(relation.kind.rawValue) \(relation.target)" }
            return requirements + elements + relations
        }
    }
}
