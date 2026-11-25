/**
 * File: GanttTaskTimes.swift
 * --------------------------
 * Layer: Core
 * Description: What a Gantt task's start and end texts are read as, which no pass of the schedule changes: a time, the
 *              tasks it comes after or lasts until, a date or a duration, and whether its end is written as a date.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 25/11/2026
 */

/// A task's start and end texts as the schedule reads them, read the first time the task is scheduled and kept for
/// every later pass: reading them depends on the chart's date format, `now` and the time zone alone, never on the
/// other tasks' times, which `GanttSchedule` works out from these on each pass.
struct GanttTaskTimes {
    /// A written start: a time, the tasks it comes after (none: today), or a text that is no date.
    enum Start {
        case time(GanttTime)
        case after([Int])
        case unreadable
    }

    /// A written end: the tasks it lasts until (none: today), a date (the next day's start with inclusive end dates),
    /// or a duration after the start, nil when the text is none (the task then has no length).
    enum End {
        case until([Int])
        case date(GanttTime)
        case duration(GanttDuration?)
    }

    /// The start, nil for a task with none written, which follows the task before it or starts today.
    let start: Start?
    let end: End
    /// Whether the end is written as a date (`YYYY-MM-DD`), which excluded days do not move.
    let hasWrittenEnd: Bool
}
