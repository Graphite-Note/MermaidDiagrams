/**
 * File: MermaidDiagramUserJourneyPreparation.swift
 * ------------------------------------------------
 * Layer: Core
 * Description: Prepares a user journey, with the journey as a column of cards for a narrow column, and says what a
 *              screen reader hears of it.
 *
 * Authors: Bahey Shalash
 * Version: 0.4
 * Date: 26/11/2026
 */

extension MermaidDiagramPreparationContext {
    /// A user journey, and for a narrow column the journey as a column of cards (Pele's `turnToFit`).
    func prepared(_ journey: UserJourneyDiagram) -> PreparedMermaidDiagram {
        let layout = UserJourneyLayoutEngine.layout(journey, typography: typography)
        let narrow = narrowSceneIsWanted(forRegularSize: layout.size)
            ? narrowScene(of: journey, regularSize: layout.size, laidOut: { journey in
                guard let column = UserJourneyLayoutEngine.columnLayout(journey, typography: typography, availableWidth: narrowestColumnWidth) else {
                    throw NoColumnLayout()
                }
                return column
            }, scene: { [limits] layout in DiagramScene(layout: layout, limits: limits) }) : nil
        return PreparedMermaidDiagram(kind: .userJourney, scene: DiagramScene(layout: layout, limits: limits), preparedNarrowScene: narrow,
                                      accessibility: MermaidDiagramAccessibility(userJourney: journey, layout: layout))
    }
}

extension MermaidDiagramAccessibility {
    /// Each task with the level its face shows when it has a score, and the actors who take part: “Do work: 1 (Me, Cat)”.
    init(userJourney diagram: UserJourneyDiagram, layout: UserJourneyLayout) {
        // The legend and the tasks alone are taken into the work, not the whole layout.
        let legend = layout.legend
        let placedTasks = layout.placedTasks
        let dots = layout.dots
        self.init(kind: .userJourney, title: diagram.accessibilityTitle ?? diagram.title,
                  description: diagram.accessibilityDescription, summarySeparator: "; ") {
            let taskTexts = zip(diagram.taskRecords, placedTasks).map { task, placed in
                let text = task.score != nil ? Self.joined(task.label.spokenText, ": ", Self.written(task.level)) : task.label.spokenText
                let actors = dots[placed.dotIndices].compactMap { dot in
                    legend.indices.contains(dot.seriesIndex) ? legend[dot.seriesIndex].text.lines.joined(separator: " ") : nil
                }
                return actors.isEmpty ? text : Self.joined(text, " (", actors.joined(separator: ", "), ")")
            }
            return taskTexts
        }
    }
}

/// A journey's cards stay side by side in the narrowest column: no column layout is made.
private struct NoColumnLayout: Error {}
