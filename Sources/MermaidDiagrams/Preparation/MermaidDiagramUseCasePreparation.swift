/**
 * File: MermaidDiagramUseCasePreparation.swift
 * --------------------------------------------
 * Layer: Core
 * Description: Prepares a use case diagram, with the diagram turned to run down for a narrow column as Pele's
 *              turnToFit draws it, and says what a screen reader hears of it.
 *
 * Authors: Bahey Shalash
 * Version: 0.4
 * Date: 24/11/2026
 */

extension MermaidDiagramPreparationContext {
    /// A use case diagram, and for a narrow column the diagram that runs across turned to run down.
    func prepared(_ diagram: UseCaseDiagram) throws(MermaidDiagramPreparationFailure) -> PreparedMermaidDiagram {
        let layout: UseCaseLayout
        do { layout = try UseCaseLayoutEngine.layout(diagram, typography: typography, limits: limits) } catch { throw .useCaseLayout(error) }
        let narrow = turnedNarrowSceneIsWanted(forRegularSize: layout.size)
            ? turnedNarrowScene(of: diagram.turnedToRunDown, regularSize: layout.size, laidOut: { turned in
                try UseCaseLayoutEngine.layout(turned, typography: typography, limits: limits)
            }, scene: DiagramScene.init(layout:)) : nil
        return PreparedMermaidDiagram(kind: .useCase, scene: DiagramScene(layout: layout), preparedNarrowScene: narrow,
                                      accessibility: MermaidDiagramAccessibility(useCase: diagram))
    }
}

extension MermaidDiagramAccessibility {
    /// Each actor and use case by its label, then each relationship as its two ends and its label or kind: “Customer;
    /// Place order; Customer to Place order; Checkout includes Browse”.
    init(useCase diagram: UseCaseDiagram) {
        let title = diagram.accessibilityTitle.isEmpty ? diagram.title : diagram.accessibilityTitle
        self.init(kind: .useCase, title: title.flatMap { title in title.isEmpty ? nil : title },
                  description: diagram.accessibilityDescription.isEmpty ? nil : diagram.accessibilityDescription, summarySeparator: "; ") {
            var names: [String: String] = [:]
            for actor in diagram.actors {
                names[actor.identifier] = Self.useCaseName(actor.label, labelType: actor.labelType, identifier: actor.identifier)
            }
            for useCase in diagram.useCases {
                names[useCase.identifier] = Self.useCaseName(useCase.label, labelType: useCase.labelType, identifier: useCase.identifier)
            }
            let elements = diagram.actors.map { actor in names[actor.identifier] ?? actor.identifier }
                + diagram.useCases.map { useCase in names[useCase.identifier] ?? useCase.identifier }
            let relationships = diagram.relationships.map { relationship in
                let source = names[relationship.source] ?? relationship.source
                let target = names[relationship.target] ?? relationship.target
                switch relationship.type {
                case .include: return source + " includes " + target
                case .extend: return source + " extends " + target
                case .generalization: return source + " is a kind of " + target
                case .association:
                    let label = relationship.label.map { label in
                        Self.useCaseName(label, labelType: relationship.labelType ?? .text, identifier: "")
                    } ?? ""
                    return label.isEmpty ? source + " to " + target : source + " to " + target + ": " + label
                }
            }
            return elements + relationships
        }
    }

    /// A label as it is drawn, read aloud, else `identifier`.
    private static func useCaseName(_ label: String, labelType: UseCaseLabelType, identifier: String) -> String {
        let spoken = labelType == .markdown ? DiagramLabelDecoder.label(from: label, form: .markdown).spokenText
            : UseCaseCharacters.trimmed(UseCaseTextLabel.mermaidCodesRead(label))
        return spoken.isEmpty ? identifier : spoken
    }
}
