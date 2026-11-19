/**
 * File: GanttRowAssignment.swift
 * ------------------------------
 * Layer: Core
 * Description: Which row each task of a Gantt chart takes: its own, or in compact mode the first of its section's free.
 *
 * Authors: Bahey Shalash
 * Version: 0.3
 * Date: 19/11/2026
 */

/// The rows of a Gantt chart's tasks. Each task takes a row of its own, in the order written; with
/// `displayMode: compact` in the front matter, as in Pele, a task takes the first row of its section whose tasks have all
/// ended when it starts, so tasks that follow each other share a row.
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

    /// Compact mode, as Pele packs the rows (`packRows`): the tasks but the vertical markers are grouped by section, the
    /// sections in the order they first appear, so that a section written twice is one group; within a group, the
    /// scheduled tasks by start (then as written) each take the first row whose last task has ended when it starts, and the
    /// tasks without a start or an end take a row each after those.
    private static func packRows(tasks: [GanttTask], schedule: [GanttSchedule.Entry], rowOfTask: inout [Int?], rowSections: inout [String]) {
        var groups: [(section: String, taskIndices: [Int])] = []
        var groupOfSection: [String: Int] = [:]
        for (index, task) in tasks.enumerated() where !task.isVertical {
            if let group = groupOfSection[task.section] {
                groups[group].taskIndices.append(index)
            } else {
                groupOfSection[task.section] = groups.count
                groups.append((task.section, [index]))
            }
        }
        var rows = [Int?](repeating: nil, count: tasks.count)
        for group in groups {
            let firstRow = rowSections.count
            let scheduled = group.taskIndices.compactMap { index -> (index: Int, start: GanttTime, end: GanttTime)? in
                guard schedule[index].isScheduled, let start = schedule[index].start, let end = schedule[index].end else { return nil }
                return (index, start, end)
            }.sorted { first, second in first.start != second.start ? first.start < second.start : first.index < second.index }
            // The end of the last task on each row of the group.
            var rowEnds: [GanttTime] = []
            for task in scheduled {
                let row = rowEnds.firstIndex { end in task.start >= end } ?? rowEnds.count
                if row == rowEnds.count { rowEnds.append(task.end) } else { rowEnds[row] = task.end }
                rows[task.index] = firstRow + row
            }
            var rowCount = rowEnds.count
            for index in group.taskIndices where rows[index] == nil {
                rows[index] = firstRow + rowCount
                rowCount += 1
            }
            rowSections.append(contentsOf: repeatElement(group.section, count: max(rowCount, 1)))
        }
        rowOfTask = rows
    }
}
