/**
 * File: MermaidDiagramCynefinPreparation.swift
 * --------------------------------------------
 * Layer: Core
 * Description: Prepares a Cynefin framework and says what a screen reader hears of it.
 *
 * Authors: Bahey Shalash
 * Version: 0.2
 * Date: 25/11/2026
 */

extension MermaidDiagramPreparationContext {
    func prepared(_ cynefin: CynefinDiagram) -> PreparedMermaidDiagram {
        PreparedMermaidDiagram(kind: .cynefin, scene: DiagramScene(layout: CynefinLayoutEngine.layout(cynefin, typography: typography), limits: limits),
                               accessibility: MermaidDiagramAccessibility(cynefin: cynefin))
    }
}

extension MermaidDiagramAccessibility {
    /// Each domain that has items, in the order drawn, with its items, then each transition with its label: “Complex:
    /// Investigate root cause, Run chaos experiment; Complex to Complicated: Pattern identified”.
    init(cynefin diagram: CynefinDiagram) {
        self.init(kind: .cynefin, title: diagram.accessibilityTitle ?? diagram.title,
                  description: diagram.accessibilityDescription, summarySeparator: "; ") {
            let domains = CynefinLayoutEngine.quadrants.map(\.domain) + [.confusion]
            let itemTexts = domains.compactMap { domain -> String? in
                guard let items = diagram.items[domain], !items.isEmpty else { return nil }
                return domain.name + ": " + items.map(Self.spoken).joined(separator: ", ")
            }
            let transitionTexts = diagram.transitions.map { transition in
                let names = transition.from.name + " to " + transition.to.name
                return transition.label.map { label in names + ": " + Self.spoken(label) } ?? names
            }
            return itemTexts + transitionTexts
        }
    }
}
