/**
 * File: MermaidDiagramSequencePreparation.swift
 * ---------------------------------------------
 * Layer: Core
 * Description: Prepares a sequence diagram, with its layout for a narrow column, and says what a screen reader hears
 *              of it.
 *
 * Authors: Bahey Shalash
 * Version: 0.2
 * Date: 25/11/2026
 */

extension MermaidDiagramPreparationContext {
    func prepared(_ sequence: SequenceDiagram) throws(MermaidDiagramPreparationFailure) -> PreparedMermaidDiagram {
        let layout: SequenceLayout
        do { layout = try SequenceLayoutEngine.layout(sequence, typography: typography) } catch { throw .sequenceLayout(error) }
        let narrow = narrowSceneIsWanted(forRegularSize: layout.size)
            ? narrowScene(of: narrowestColumnWidth.map { width in (sequence, width) }, regularSize: layout.size, laidOut: { sequence, width in
                try SequenceLayoutEngine.layout(sequence, typography: typography, availableWidth: width)
            }, scene: { [limits] layout in DiagramScene(layout: layout, limits: limits) }) : nil
        return PreparedMermaidDiagram(kind: .sequence, scene: DiagramScene(layout: layout, limits: limits), preparedNarrowScene: narrow,
                                      accessibility: MermaidDiagramAccessibility(sequence: sequence))
    }
}

extension MermaidDiagramAccessibility {
    /// The participants' names, then each message as who sends it to whom and its text: “Alice to Bob: Hello”.
    init(sequence diagram: SequenceDiagram) {
        self.init(kind: .sequence, title: diagram.accessibilityTitle ?? diagram.title,
                  description: diagram.accessibilityDescription, summarySeparator: ". ") {
            let names = diagram.participants.map(\.label.spokenText)
            let messages = diagram.events.compactMap { event -> String? in
                guard case .message(let message) = event else { return nil }
                let text = message.text.spokenText
                let route = "\(names[message.sourceIndex]) to \(names[message.targetIndex])"
                return text.isEmpty ? route : "\(route): \(text)"
            }
            return [names.joined(separator: ", ")] + messages
        }
    }
}
