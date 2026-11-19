/**
 * File: GanttLayoutError.swift
 * ----------------------------
 * Layer: Core
 * Description: Why a Gantt chart was not laid out.
 *
 * Authors: felixchvl, Bahey Shalash
 * Version: 0.1
 * Date: 19/11/2026
 */

/// Why a Gantt chart was not laid out.
public enum GanttLayoutError: Error, Equatable, Sendable {
    /// The chart has a statement that is not drawn yet: drawn without it, it would look complete and be wrong.
    case statementNotDrawn(GanttStatementNotDrawn)
    /// A start date is written in a form neither `dateFormat` nor the forms of JavaScript's `Date` read (ISO 8601 and what V8's
    /// legacy parser reads: `JavaScriptDateReading`), by its text; Mermaid refuses it too.
    case unreadableDate(String)
    /// Every day for 10,000 days after a task's end is excluded, by the task's text: Mermaid's error.
    case noDayLeftAfterExclusions(task: String)
    /// Moving tasks' ends past excluded days would step through more days than the limit.
    case tooManyScheduledDays(limit: Int)
}
