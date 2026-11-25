/**
 * File: MermaidDiagramTimelinePreparation.swift
 * ---------------------------------------------
 * Layer: Core
 * Description: Prepares a timeline, with its periods one below the other for a narrow column, and says what a screen
 *              reader hears of it.
 *
 * Authors: Bahey Shalash
 * Version: 0.2
 * Date: 25/11/2026
 */

extension MermaidDiagramPreparationContext {
    /// A timeline, and for a narrow column the timeline with its periods one below the other, its columns sharing the
    /// column's width.
    func prepared(_ timeline: TimelineDiagram) -> PreparedMermaidDiagram {
        let layout = TimelineLayoutEngine.layout(timeline, typography: typography)
        let narrow = narrowSceneIsWanted(forRegularSize: layout.size)
            ? narrowScene(of: narrowestColumnWidth.map { width in (timeline, width) }, regularSize: layout.size, laidOut: { timeline, width in
                TimelineLayoutEngine.layout(timeline, typography: typography, availableWidth: width)
            }, scene: { [limits] layout in DiagramScene(layout: layout, limits: limits) }) : nil
        return PreparedMermaidDiagram(kind: .timeline, scene: DiagramScene(layout: layout, limits: limits), preparedNarrowScene: narrow,
                                      accessibility: MermaidDiagramAccessibility(timeline: timeline))
    }
}

extension MermaidDiagramAccessibility {
    /// Each period with its events, in the order the diagram writes them: “2004: Facebook, Google”.
    init(timeline diagram: TimelineDiagram) {
        self.init(kind: .timeline, title: diagram.accessibilityTitle ?? diagram.title,
                  description: diagram.accessibilityDescription, summarySeparator: "; ") {
            let periodTexts = diagram.periods.map { period in
                period.events.isEmpty ? period.label.spokenText
                    : Self.joined(period.label.spokenText, ": ", period.events.map(\.spokenText).joined(separator: ", "))
            }
            return periodTexts
        }
    }
}
