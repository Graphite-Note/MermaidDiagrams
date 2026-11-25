/**
 * File: MermaidDiagramGanttPreparation.swift
 * ------------------------------------------
 * Layer: Core
 * Description: Prepares a Gantt chart scheduled on the preparation's day and time zone, with its layout for a narrow
 *              column, and says what a screen reader hears of it.
 *
 * Authors: Bahey Shalash
 * Version: 0.2
 * Date: 25/11/2026
 */

extension MermaidDiagramPreparationContext {
    /// A Gantt chart scheduled on `now` in `timeZone`, and for a narrow column the chart on a page as wide as the column.
    func prepared(_ chart: GanttChart) throws(MermaidDiagramPreparationFailure) -> PreparedMermaidDiagram {
        let layout: GanttLayout
        do {
            layout = try GanttLayoutEngine.layout(chart, typography: typography, now: now, timeZone: timeZone, limits: limits)
        } catch {
            throw .ganttLayout(error)
        }
        let narrow = narrowSceneIsWanted(forRegularSize: layout.size)
            ? narrowScene(of: chart, regularSize: layout.size, laidOut: { chart in
                try GanttLayoutEngine.layout(chart, typography: typography, now: now, timeZone: timeZone, limits: limits,
                                             availableWidth: narrowestColumnWidth)
            }, scene: { [limits] layout in DiagramScene(layout: layout, limits: limits) }) : nil
        return PreparedMermaidDiagram(kind: .ganttChart, scene: DiagramScene(layout: layout, limits: limits), preparedNarrowScene: narrow,
                                      accessibility: MermaidDiagramAccessibility(ganttChart: chart))
    }
}

extension MermaidDiagramAccessibility {
    /// The tasks' text, in the order they are written.
    init(ganttChart chart: GanttChart) {
        self.init(kind: .ganttChart, title: chart.accessibilityTitle ?? chart.title,
                  description: chart.accessibilityDescription) {
            chart.tasks.map(\.name)
        }
    }
}
