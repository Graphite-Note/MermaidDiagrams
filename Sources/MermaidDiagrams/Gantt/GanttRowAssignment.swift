/**
 * File: GanttRowAssignment.swift
 * ------------------------------
 * Layer: Core
 * Description: Which row each task of a Gantt chart takes: its own, or in compact mode the first of its section's free.
 *
 * Authors: Bahey Shalash
 * Version: 0.2
 * Date: 19/11/2026
 */

/// The rows of a Gantt chart's tasks. Each task takes a row of its own, in the order written; with
/// `displayMode: compact` in the front matter, as in Mermaid, a task takes the first row of its section's run whose
/// tasks have all ended when it starts, so tasks that follow each other share a row.
struct GanttRowAssignment {
    /// The row of each task, or nil for a vertical marker (a task tagged `vert`), which has none.
    let rowOfTask: [Int?]
    /// The section of each row.
    let rowSections: [String]

    init(tasks: [GanttTask], schedule: [GanttSchedule.Entry], isCompact: Bool) {
        var rowOfTask: [Int?] = []
        var rowSections: [String] = []
        if isCompact {
            Self.packRows(tasks: tasks, schedule: schedule, rowOfTask: &rowOfTask, rowSections: &rowSections)
        } else {
            for task in tasks {
                rowOfTask.append(task.isVertical ? nil : rowSections.count)
                if !task.isVertical { rowSections.append(task.section) }
            }
        }
        self.rowOfTask = rowOfTask
        self.rowSections = rowSections
    }

    /// Compact mode: each task but the vertical markers takes the first row of its section's run that is free when it starts.
    private static func packRows(tasks: [GanttTask], schedule: [GanttSchedule.Entry], rowOfTask: inout [Int?], rowSections: inout [String]) {
        // The rows of the run of tasks of one section being filled, by the end of the last task in each.
        var runEnds: [GanttTime?] = []
        var runFirstRow = 0
        var runSection: String?
        for (index, task) in tasks.enumerated() {
            guard !task.isVertical else {
                rowOfTask.append(nil)
                continue
            }
            if task.section != runSection {
                runSection = task.section
                runFirstRow = rowSections.count
                runEnds = []
            }
            let start = schedule[index].start, end = schedule[index].end
            let freeRow = runEnds.firstIndex { lastEnd in
                guard let lastEnd, let start else { return false }
                return lastEnd <= start
            }
            if let freeRow {
                runEnds[freeRow] = end
                rowOfTask.append(runFirstRow + freeRow)
            } else {
                runEnds.append(end)
                rowSections.append(task.section)
                rowOfTask.append(rowSections.count - 1)
            }
        }
    }
}
