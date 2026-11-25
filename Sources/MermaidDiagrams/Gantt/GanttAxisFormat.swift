/**
 * File: GanttAxisFormat.swift
 * ---------------------------
 * Layer: Core
 * Description: Writes a Gantt chart's axis dates with d3's time format specifiers, in English, the specifier read once
 *              into its pieces for every date of an axis.
 *
 * Authors: felixchvl, Bahey Shalash
 * Version: 0.2
 * Date: 25/11/2026
 */

/// Writes the axis' dates with `axisFormat`'s d3 time format specifiers (`%Y-%m-%d`, `%b %e`), in English, as
/// d3-time-format writes them for Mermaid: `%` then an optional padding (`-` none, `_` spaces, `0` zeros) and a
/// letter; any other character is written as it is.
enum GanttAxisFormat {
    private static let percent: Character = "%"
    private static let paddings: [Character: String] = ["-": "", "_": " ", "0": "0"]

    static func format(_ specifier: String, _ time: GanttTime, zone: GanttTimeZone) -> String {
        GanttCompiledAxisFormat(specifier).format(time, zone: zone)
    }

    /// `specifier` read into its pieces, as `format(_:_:zone:)` reads it character by character: the text between the
    /// directives, and each directive's letter and padding.
    static func pieces(of specifier: String) -> [GanttCompiledAxisFormat.Piece] {
        var pieces: [GanttCompiledAxisFormat.Piece] = []
        var literal = ""
        var characters = Substring(specifier)
        while let character = characters.popFirst() {
            guard character == percent else {
                literal.append(character)
                continue
            }
            // A `%` that ends the specifier writes nothing.
            guard var directive = characters.popFirst() else { break }
            var padding = directive == "e" ? " " : "0"
            if let chosen = paddings[directive], let next = characters.popFirst() {
                padding = chosen
                directive = next
            }
            if !literal.isEmpty {
                pieces.append(.literal(literal))
                literal = ""
            }
            pieces.append(.directive(directive, padding: padding))
        }
        if !literal.isEmpty { pieces.append(.literal(literal)) }
        return pieces
    }

    static func directive(_ letter: Character, _ time: GanttTime, padding: String, zone: GanttTimeZone) -> String {
        if let calendarText = calendarDirective(letter, time, padding: padding) { return calendarText }
        if let clockText = clockDirective(letter, time, padding: padding, zone: zone) { return clockText }
        return String(letter)
    }

    /// The year, month, week and day directives.
    private static func calendarDirective(_ letter: Character, _ time: GanttTime, padding: String) -> String? {
        switch letter {
        case "a": return String(GanttCalendarToken.weekdayNames[Int(time.weekday)].prefix(3))
        case "A": return GanttCalendarToken.weekdayNames[Int(time.weekday)]
        case "b": return String(GanttCalendarToken.monthNames[Int(time.month - 1)].prefix(3))
        case "B": return GanttCalendarToken.monthNames[Int(time.month - 1)]
        case "d", "e": return padded(time.day, padding, 2)
        case "g": return padded(GanttIsoWeek.thursday(of: time).year % 100, padding, 2)
        case "G": return padded(GanttIsoWeek.thursday(of: time).year % 10_000, padding, 4)
        case "j": return padded(1 + time.dayNumber - GanttTime.dayNumber(year: time.year, month: 1, day: 1), padding, 3)
        case "m": return padded(time.month, padding, 2)
        case "q": return String((time.month + 2) / 3)
        case "u": return String(time.isoWeekday)
        case "U": return padded(weekOfYear(time, weekStart: 0), padding, 2)
        case "V": return padded(GanttIsoWeek.number(of: time), padding, 2)
        case "w": return String(time.weekday)
        case "W": return padded(weekOfYear(time, weekStart: 1), padding, 2)
        case "y": return padded(time.year % 100, padding, 2)
        case "Y": return padded(time.year % 10_000, padding, 4)
        default: return nil
        }
    }

    /// The time of day, Unix time, the offset and the combined directives.
    private static func clockDirective(_ letter: Character, _ time: GanttTime, padding: String, zone: GanttTimeZone) -> String? {
        switch letter {
        case "c": return format("%x, %X", time, zone: zone)
        case "f": return padded(time.millisecond, padding, 3) + "000"
        case "H": return padded(time.hour, padding, 2)
        case "I": return padded(time.hour % 12 == 0 ? 12 : time.hour % 12, padding, 2)
        case "L": return padded(time.millisecond, padding, 3)
        case "M": return padded(time.minute, padding, 2)
        case "p": return time.hour >= 12 ? "PM" : "AM"
        case "Q": return String(zone.unixMilliseconds(of: time))
        case "s": return String(GanttTime.floorDivision(zone.unixMilliseconds(of: time), GanttTime.millisecondsPerSecond))
        case "S": return padded(time.second, padding, 2)
        case "x": return format("%-m/%-d/%Y", time, zone: zone)
        case "X": return format("%-I:%M:%S %p", time, zone: zone)
        case "Z":
            let minutes = zone.offsetMinutes(at: time)
            return (minutes >= 0 ? "+" : "-") + padded(abs(minutes) / 60, "0", 2) + padded(abs(minutes) % 60, "0", 2)
        case "%": return "%"
        default: return nil
        }
    }

    /// Weeks since the last `weekStart` day (0 for Sunday) before the year began: d3's `%U` and `%W`.
    private static func weekOfYear(_ time: GanttTime, weekStart: Int64) -> Int64 {
        func weekStartDay(onOrBefore dayNumber: Int64) -> Int64 {
            dayNumber - GanttTime.modulo(GanttTime(milliseconds: dayNumber * GanttTime.millisecondsPerDay).weekday - weekStart, 7)
        }
        let lastDayBefore = GanttTime.dayNumber(year: time.year, month: 1, day: 1) - 1
        return (weekStartDay(onOrBefore: time.dayNumber) - weekStartDay(onOrBefore: lastDayBefore)) / 7
    }

    /// The number with `padding` before it up to `width` characters, a minus sign before the padding.
    private static func padded(_ number: Int64, _ padding: String, _ width: Int) -> String {
        let digits = String(abs(number))
        let filled = digits.count < width ? String(repeating: padding, count: width - digits.count) + digits : digits
        return (number < 0 ? "-" : "") + filled
    }
}

/// An axis format read once into its pieces, so that each date the axis writes is its pieces written in turn.
struct GanttCompiledAxisFormat {
    enum Piece {
        case literal(String)
        case directive(Character, padding: String)
    }

    let pieces: [Piece]

    init(_ specifier: String) {
        pieces = GanttAxisFormat.pieces(of: specifier)
    }

    /// `time` written in the format, as `GanttAxisFormat.format(_:_:zone:)` writes it.
    func format(_ time: GanttTime, zone: GanttTimeZone) -> String {
        var written = ""
        for piece in pieces {
            switch piece {
            case .literal(let literal): written += literal
            case .directive(let letter, let padding): written += GanttAxisFormat.directive(letter, time, padding: padding, zone: zone)
            }
        }
        return written
    }
}
