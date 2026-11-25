/**
 * File: GanttExcludedDays.swift
 * -----------------------------
 * Layer: Core
 * Description: Which days a Gantt chart's excludes leave out, by weekday, weekend or date, and the dates its includes keep.
 *
 * Authors: felixchvl, Bahey Shalash
 * Version: 0.2
 * Date: 25/11/2026
 */

/// Which days a Gantt chart's `excludes` leaves out, as Mermaid decides it: a day is excluded by its weekday's name,
/// by `weekends` (Saturday and Sunday, or Friday and Saturday after `weekend friday`), or by its date written as
/// `YYYY-MM-DD` or in the chart's `dateFormat`; a date `includes` names is never excluded.
struct GanttExcludedDays {
    private let excludedWeekdays: [Bool]
    private let excludedWords: Set<String>
    private let includedWords: Set<String>
    private let dateFormat: GanttDateFormat
    private let writesDatesAsISO: Bool
    private let zone: GanttTimeZone
    /// Whether a day can be excluded or included by its date, so that each day's date must be written.
    private let namesDates: Bool

    private static let weekendWord = "weekends"
    private static let dayWords = ["sunday", "monday", "tuesday", "wednesday", "thursday", "friday", "saturday"]
    private static let isoDateFormat = "YYYY-MM-DD"

    init(chart: GanttChart, zone: GanttTimeZone) {
        self.init(chart: chart, zone: zone, dateFormat: GanttDateFormat(chart.dateFormat))
    }

    /// The chart's excluded days, its `dateFormat` already read into `dateFormat`.
    init(chart: GanttChart, zone: GanttTimeZone, dateFormat: GanttDateFormat) {
        excludedWords = Set(chart.excludedDays)
        includedWords = Set(chart.includedDays)
        let weekend: Set<Int64> = chart.weekendStart == .friday ? [5, 6] : [6, 0]
        let excludesWeekends = excludedWords.contains(Self.weekendWord)
        excludedWeekdays = Self.dayWords.enumerated().map { weekday, word in
            (excludesWeekends && weekend.contains(Int64(weekday))) || chart.excludedDays.contains(word)
        }
        self.dateFormat = dateFormat
        writesDatesAsISO = chart.dateFormat == Self.isoDateFormat
        self.zone = zone
        namesDates = !chart.includedDays.isEmpty || chart.excludedDays.contains { word in word != Self.weekendWord && !Self.dayWords.contains(word) }
            || !Self.isNumericFormat(chart.dateFormat)
    }

    /// Whether the chart excludes or includes any day, so that excluded days can be shaded.
    var isEmpty: Bool { excludedWords.isEmpty && includedWords.isEmpty }

    func isExcluded(_ day: GanttTime) -> Bool {
        let isExcludedWeekday = excludedWeekdays[Int(day.weekday)]
        guard namesDates else { return isExcludedWeekday }
        let isoDate = GanttDateFormat.isoDateText(day)
        let formatted = writesDatesAsISO ? isoDate : dateFormat.format(day, zone: zone)
        func isNamed(in words: Set<String>) -> Bool {
            words.contains(isoDate) || formatted.map(words.contains) == true
        }
        if isNamed(in: includedWords) { return false }
        return isExcludedWeekday || isNamed(in: excludedWords)
    }

    /// Whether a format writes only digits and separators, so that a date written with it is never a day's name.
    private static func isNumericFormat(_ format: String) -> Bool {
        if let isNumeric = format.utf8.withContiguousStorageIfAvailable({ bytes in bytes.allSatisfy { byte in numericFormatBytes.contains(byte) } }) {
            // Bytes of those ASCII characters alone are those characters alone; any other byte is part of another character.
            return isNumeric
        }
        return format.allSatisfy { character in "YMDHhmsSZXx-/.:, T".contains(character) }
    }

    private static let numericFormatBytes = Set("YMDHhmsSZXx-/.:, T".utf8)
}
