/**
 * File: GanttSchedule.swift
 * -------------------------
 * Layer: Core
 * Description: When each task of a Gantt chart starts and ends, as Mermaid's Gantt database works it out over up to
 *              eleven passes, each task's texts read once.
 *
 * Authors: felixchvl, Bahey Shalash
 * Version: 0.2
 * Date: 25/11/2026
 */

import Foundation

/// When each task of a Gantt chart starts and ends, worked out as Mermaid's Gantt database does (`getTasks`): every
/// task is scheduled again on each pass, as a task may follow one written after it, up to eleven passes or until
/// every task has a start and an end. A task that waits on one that never gets them keeps neither.
struct GanttSchedule {
    struct Entry: Equatable {
        var start: GanttTime?
        var end: GanttTime?
        /// Where the bar ends when excluded days moved the task's end on, before the last excluded run; else nil.
        var drawnEnd: GanttTime?
        var isScheduled = false
        /// Whether the end is written as a date (`YYYY-MM-DD`), which excluded days do not move.
        var hasWrittenEnd = false
    }

    private(set) var entries: [Entry]
    private let chart: GanttChart
    private let today: GanttTime
    private let now: GanttTime
    private let zone: GanttTimeZone
    private let dateFormat: GanttDateFormat
    /// The chart's excluded days, which the plot shades too.
    let excludedDays: GanttExcludedDays
    /// The last task written with each identifier.
    private let taskIndexByIdentifier: [String: Int]
    /// Each task's texts as read the first time it was scheduled, nil before.
    private var readTimes: [GanttTaskTimes?]
    private let maximumDayCount: Int
    private var steppedDayCount = 0

    /// The most passes over the tasks: Mermaid's eleven.
    static let maximumPassCount = 11
    /// How far excluded days may move a task's end before Mermaid gives up.
    static let maximumExcludedDayRun: Int64 = 10_000

    /// Schedules `chart` on the wall clock `now` reads in `zone`.
    init(chart: GanttChart, now: GanttTime, zone: GanttTimeZone, limits: MermaidDiagramLimits) throws(GanttLayoutError) {
        entries = Array(repeating: Entry(), count: chart.tasks.count)
        readTimes = Array(repeating: nil, count: chart.tasks.count)
        self.chart = chart
        self.now = now
        today = now.startOfDay
        self.zone = zone
        dateFormat = GanttDateFormat(chart.dateFormat)
        excludedDays = GanttExcludedDays(chart: chart, zone: zone, dateFormat: dateFormat)
        taskIndexByIdentifier = Dictionary(chart.tasks.enumerated().map { index, task in (task.identifier, index) }) { _, later in later }
        maximumDayCount = limits.maximumScheduledDayCount
        for _ in 0..<Self.maximumPassCount {
            var isEveryTaskScheduled = true
            for index in entries.indices {
                try schedule(taskAt: index)
                isEveryTaskScheduled = isEveryTaskScheduled && entries[index].isScheduled
            }
            if isEveryTaskScheduled { break }
        }
    }

    private mutating func schedule(taskAt index: Int) throws(GanttLayoutError) {
        let task = chart.tasks[index]
        let times: GanttTaskTimes
        if let read = readTimes[index] { times = read } else { times = try readTimes(ofTaskAt: index) }
        if let start = times.start {
            if let time = startTime(start, text: task.startText ?? "") { entries[index].start = time }
            if case .unreadable = start { throw .unreadableDate(task.startText ?? "") }
        } else {
            let previous = task.previousTaskIdentifier.flatMap { identifier in taskIndexByIdentifier[identifier] }
            entries[index].start = previous.map { previousIndex in entries[previousIndex].end } ?? today
        }
        guard let start = entries[index].start else { return }
        entries[index].end = endTime(after: start, times.end)
        guard entries[index].end != nil else { return }
        entries[index].isScheduled = true
        entries[index].hasWrittenEnd = times.hasWrittenEnd
        try moveEndPastExcludedDays(ofTaskAt: index)
    }

    /// The task's texts read, and kept for the passes after: its start as Unix time for the `x` and `X` formats, `after`
    /// the tasks named, a date in `dateFormat` or one of JavaScript's date forms read here; its end as `until` the tasks
    /// named, a date in `dateFormat` or a duration. A start that cannot be read refuses the chart, as a date that cannot
    /// be read is refused each time it is read.
    private mutating func readTimes(ofTaskAt index: Int) throws(GanttLayoutError) -> GanttTaskTimes {
        let task = chart.tasks[index]
        var start: GanttTaskTimes.Start?
        if let text = task.startText {
            if chart.dateFormat == "x" || chart.dateFormat == "X", let milliseconds = Int64(text), text.allSatisfy(\.isNumber) {
                guard let time = zone.wallClockTime(unixMilliseconds: milliseconds) else { throw .unreadableDate(text) }
                start = .time(time)
            } else if let identifiers = Self.references(after: "after", in: text) {
                start = .after(identifiers.compactMap { identifier in taskIndexByIdentifier[identifier] })
            } else if let date = dateFormat.parse(text, now: now, zone: zone) ?? GanttFallbackDate.parse(text, zone: zone) {
                start = .time(date)
            } else {
                start = .unreadable
            }
        }
        let end: GanttTaskTimes.End
        if let identifiers = Self.references(after: "until", in: task.endText) {
            end = .until(identifiers.compactMap { identifier in taskIndexByIdentifier[identifier] })
        } else if let date = dateFormat.parse(task.endText, now: now, zone: zone) {
            end = .date(chart.isEndDateInclusive ? date.addingDays(1) ?? date : date)
        } else {
            end = .duration(GanttDuration(task.endText))
        }
        let times = GanttTaskTimes(start: start, end: end, hasWrittenEnd: GanttDateFormat.isoDate.parse(task.endText, now: now, zone: zone) != nil)
        readTimes[index] = times
        return times
    }

    /// A task's start: its time, or the latest end of the tasks it comes after (today when it names none). Nil while a
    /// task named has no end yet, and for a text that is no date.
    private func startTime(_ start: GanttTaskTimes.Start, text: String) -> GanttTime? {
        switch start {
        case .time(let time): return time
        case .unreadable: return nil
        case .after(let tasks):
            guard let first = tasks.first else { return today }
            let latest = tasks.dropFirst().reduce(first) { latest, candidate in
                Self.isLater(entries[candidate].end, than: entries[latest].end) ? candidate : latest
            }
            return entries[latest].end
        }
    }

    /// A task's end: the earliest start of the tasks it lasts until (today when it names none), its date, or its
    /// duration after its start; a text that is none of these leaves the task no length.
    private func endTime(after start: GanttTime, _ end: GanttTaskTimes.End) -> GanttTime? {
        switch end {
        case .until(let tasks):
            guard let first = tasks.first else { return today }
            let earliest = tasks.dropFirst().reduce(first) { earliest, candidate in
                Self.isLater(entries[earliest].start, than: entries[candidate].start) ? candidate : earliest
            }
            return entries[earliest].start
        case .date(let date): return date
        case .duration(let duration): return duration?.added(to: start) ?? start
        }
    }

    /// Moves the end of a task whose length is a duration one day on for every excluded day it covers.
    private mutating func moveEndPastExcludedDays(ofTaskAt index: Int) throws(GanttLayoutError) {
        guard !chart.excludedDays.isEmpty, !entries[index].hasWrittenEnd, let start = entries[index].start, var end = entries[index].end,
              var day = start.addingDays(1), let latestEnd = end.addingDays(Self.maximumExcludedDayRun) else { return }
        var isExcluded = false
        var drawnEnd: GanttTime?
        while day <= end {
            steppedDayCount += 1
            guard steppedDayCount <= maximumDayCount else { throw .tooManyScheduledDays(limit: maximumDayCount) }
            if !isExcluded { drawnEnd = end }
            isExcluded = excludedDays.isExcluded(day)
            if isExcluded {
                guard let movedEnd = end.addingDays(1), movedEnd <= latestEnd else { throw .noDayLeftAfterExclusions(task: chart.tasks[index].name) }
                end = movedEnd
            }
            guard let nextDay = day.addingDays(1) else { break }
            day = nextDay
        }
        entries[index].end = end
        entries[index].drawnEnd = drawnEnd
    }

    /// The identifiers after `keyword` and spaces (`after a1 b2`): letters, digits, `_`, `-` and spaces, then
    /// anything; nil when the text does not start so.
    static func references(after keyword: String, in text: String) -> [String]? {
        if let references = text.utf8.withContiguousStorageIfAvailable({ bytes in asciiReferences(after: keyword, in: bytes) }), let references {
            return references
        }
        return referencesOfCharacters(after: keyword, in: text)
    }

    /// `references(after:in:)` of ASCII text, read on its bytes: within ASCII, the white space Foundation trims and Swift's
    /// characters call white space are the tab to the carriage return and the space, and a carriage return before a line
    /// feed, one character, is white space as both are. Nil within for text that does not start so; nil without for text
    /// with a byte beyond ASCII.
    private static func asciiReferences(after keyword: String, in bytes: UnsafeBufferPointer<UInt8>) -> [String]?? {
        var combined: UInt8 = 0
        for byte in bytes { combined |= byte }
        guard combined < 0x80 else { return nil }
        func isWhiteSpace(_ byte: UInt8) -> Bool { (byte >= 0x09 && byte <= 0x0D) || byte == 0x20 }
        var start = 0
        var end = bytes.count
        while start < end, isWhiteSpace(bytes[start]) { start += 1 }
        while end > start, isWhiteSpace(bytes[end - 1]) { end -= 1 }
        let keywordBytes = keyword.utf8
        guard end - start >= keywordBytes.count, zip(bytes[start..<end], keywordBytes).allSatisfy({ byte, expected in byte == expected }) else {
            return .some(nil)
        }
        var position = start + keywordBytes.count
        guard position < end, isWhiteSpace(bytes[position]) else { return .some(nil) }
        while position < end, isWhiteSpace(bytes[position]) { position += 1 }
        var identifiersEnd = position
        while identifiersEnd < end, MermaidByte.isLetter(bytes[identifiersEnd]) || MermaidByte.isDigit(bytes[identifiersEnd])
            || bytes[identifiersEnd] == UInt8(ascii: "_") || bytes[identifiersEnd] == UInt8(ascii: "-") || bytes[identifiersEnd] == UInt8(ascii: " ") {
            identifiersEnd += 1
        }
        guard identifiersEnd > position else { return .some(nil) }
        return .some(bytes[position..<identifiersEnd].split(separator: UInt8(ascii: " ")).map { piece in String(decoding: piece, as: UTF8.self) })
    }

    /// `references(after:in:)` read on Swift's characters, for any text.
    static func referencesOfCharacters(after keyword: String, in text: String) -> [String]? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix(keyword) else { return nil }
        let rest = trimmed.dropFirst(keyword.count)
        guard let first = rest.first, first.isWhitespace else { return nil }
        let identifiers = rest.drop { character in character.isWhitespace }
            .prefix { character in character.isASCII && (character.isLetter || character.isNumber || "_- ".contains(character)) }
        guard !identifiers.isEmpty else { return nil }
        return identifiers.split(separator: " ").map(String.init)
    }

    /// `left > right` as JavaScript compares two dates that may be missing: false when either is.
    private static func isLater(_ left: GanttTime?, than right: GanttTime?) -> Bool {
        guard let left, let right else { return false }
        return left > right
    }
}
