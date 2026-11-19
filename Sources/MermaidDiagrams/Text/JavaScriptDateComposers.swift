/**
 * File: JavaScriptDateComposers.swift
 * -----------------------------------
 * Layer: Core
 * Description: The composers of V8's legacy date parser: the numbers of a date, the parts of a time and a zone's offset.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 19/11/2026
 */

/// The numbers of a date in the order they are written: up to three, with a month name apart.
struct JavaScriptDayComposer {
    var components: [Int64] = []
    var namedMonth: Int64?

    mutating func add(_ number: Int64) -> Bool {
        guard components.count < 3 else { return false }
        components.append(number)
        return true
    }

    private static func isDay(_ number: Int64) -> Bool { (1...31).contains(number) }
    private static func isMonth(_ number: Int64) -> Bool { (1...12).contains(number) }

    /// V8's `DayComposer::Write`: components not written are 1, which makes a year of 2001 where none is.
    var fields: (year: Int64, month: Int64, day: Int64)? {
        guard !components.isEmpty else { return nil }
        let numbers = components + Array(repeating: 1, count: 3 - components.count)
        var year: Int64 = 0
        var month: Int64
        var day: Int64
        if let namedMonth {
            month = namedMonth
            if !Self.isDay(numbers[0]) {
                year = numbers[0]
                day = numbers[1]
            } else {
                day = numbers[0]
                year = numbers[1]
            }
        } else if !Self.isDay(numbers[0]) {
            year = numbers[0]
            month = numbers[1]
            day = numbers[2]
        } else {
            month = numbers[0]
            day = numbers[1]
            year = numbers[2]
        }
        if (0...49).contains(year) { year += 2000 } else if (50...99).contains(year) { year += 1900 }
        guard Self.isMonth(month), Self.isDay(day) else { return nil }
        return (year, month, day)
    }
}

/// The hour, minute, second and fraction of a time of day, in the order they are written.
struct JavaScriptTimeComposer {
    var components: [Int64] = []
    var hourOffset: Int64?
    /// Whether no more components can follow: the last was written as final.
    private var isFinal = false

    var isEmpty: Bool { components.isEmpty }

    mutating func add(_ number: Int64) -> Bool {
        guard !isFinal, components.count < 4 else { return false }
        components.append(number)
        return true
    }

    mutating func addFinal(_ number: Int64) {
        if add(number) { isFinal = true }
    }

    func isExpecting(_ number: Int64) -> Bool {
        guard !isFinal else { return false }
        switch components.count {
        case 1: return (0...59).contains(number)
        case 2: return (0...59).contains(number)
        case 3: return (0...999).contains(number)
        default: return false
        }
    }

    var fields: (hour: Int64, minute: Int64, second: Int64, millisecond: Int64)? {
        var numbers = components + Array(repeating: 0, count: 4 - components.count)
        if let hourOffset {
            guard (0...12).contains(numbers[0]) else { return nil }
            numbers[0] = numbers[0] % 12 + hourOffset
        }
        let isValid = (0...23).contains(numbers[0]) && (0...59).contains(numbers[1]) && (0...59).contains(numbers[2]) && (0...999).contains(numbers[3])
        guard isValid || (numbers[0] == 24 && numbers[1] == 0 && numbers[2] == 0 && numbers[3] == 0) else { return nil }
        return (numbers[0], numbers[1], numbers[2], numbers[3])
    }
}

/// A zone's offset: a sign, an hour and a minute, each possibly not written.
struct JavaScriptZoneComposer {
    var sign: Int64?
    var hour: Int64?
    var minute: Int64?

    mutating func set(hours: Int64) {
        sign = hours < 0 ? -1 : 1
        hour = abs(hours)
        minute = 0
    }

    var isUniversal: Bool { hour == 0 && minute == 0 }

    func isExpecting(_ number: Int64) -> Bool {
        hour != nil && minute == nil && (0...59).contains(number)
    }

    /// The offset from UTC in minutes the text names: nil for no zone.
    var offsetMinutes: Int64? {
        guard let sign else { return nil }
        return sign * ((hour ?? 0) * 60 + (minute ?? 0))
    }
}
