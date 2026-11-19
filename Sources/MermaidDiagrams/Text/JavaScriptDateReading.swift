/**
 * File: JavaScriptDateReading.swift
 * ---------------------------------
 * Layer: Core
 * Description: Reads the date forms JavaScript's `new Date(text)` reads beyond ISO 8601, as V8's legacy date parser reads them.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 19/11/2026
 */

/// What V8's legacy date parser (`DateParser`, the one `new Date("March 7, 2014")` uses) makes of a text: the year, month,
/// day, time of day and, when the text names one, the zone's offset. Words before the first number are ignored (`Fri,`), a
/// word after it must be a month name, `AM` or `PM`, or a zone (`UT`, `UTC`, `GMT`, `Z`, `EST`, `EDT`, `CST`, `CDT`, `MST`,
/// `MDT`, `PST`, `PDT`); a month name is matched by its first three letters, and parentheses are skipped. Numbers are a
/// day, a month and a year in the order V8 composes them (a first number over 31 starts a year-month-day date; a month name
/// puts the day and the year in the order they are written; otherwise month, day, year), times (`10:30`, `10:30:15`,
/// `10:30:15.250`, with `AM` or `PM`), and a zone offset after `UTC`, `GMT` or a time (`+0100`, `-5`, `+01:00`). A year of
/// two digits is 2000 to 2049, or 1950 to 1999; a date of one or two numbers takes V8's defaults (month and day 1, and
/// 2001 for a year not written). A text V8 refuses is nil. This is the part of the parser the ISO forms leave to it.
struct JavaScriptDateReading: Equatable {
    var year: Int64
    var month: Int64
    var day: Int64
    var hour: Int64
    var minute: Int64
    var second: Int64
    var millisecond: Int64
    /// The zone's offset from UTC in minutes the text names, or nil for the local time.
    var offsetMinutes: Int64?

    /// The date `text` writes, or nil.
    static func read(_ text: String) -> JavaScriptDateReading? {
        var reading = LegacyReading(scanner: JavaScriptDateScanner(text: text))
        return reading.run()
    }

    /// V8's loop over the tokens after the ISO part: each number, word and sign goes to the composer it belongs to.
    private struct LegacyReading {
        var scanner: JavaScriptDateScanner
        var day = JavaScriptDayComposer()
        var time = JavaScriptTimeComposer()
        var zone = JavaScriptZoneComposer()
        var hasReadNumber = false

        init(scanner: JavaScriptDateScanner) {
            self.scanner = scanner
        }

        mutating func run() -> JavaScriptDateReading? {
            while true {
                let token = scanner.next()
                let isAccepted: Bool
                switch token {
                case .end: return finished()
                case .number(let value, _): isAccepted = readNumber(value)
                case .keyword(let keyword): isAccepted = readKeyword(keyword)
                case .sign(let sign) where zone.isUniversal || !time.isEmpty: isAccepted = readZoneOffset(sign: sign)
                // An extra sign or a closing parenthesis is illegal once a number has been read.
                case .sign, .symbol(41): isAccepted = !hasReadNumber
                case .symbol, .whitespace, .unknown: isAccepted = true
                }
                guard isAccepted else { return nil }
            }
        }

        private func finished() -> JavaScriptDateReading? {
            guard let date = day.fields, let clock = time.fields else { return nil }
            return JavaScriptDateReading(year: date.year, month: date.month, day: date.day, hour: clock.hour, minute: clock.minute, second: clock.second,
                                         millisecond: clock.millisecond, offsetMinutes: zone.offsetMinutes)
        }

        /// A number is a part of a time (before a colon, a dot or when one is expected), a zone's minute, or a date's number.
        private mutating func readNumber(_ value: Int64) -> Bool {
            hasReadNumber = true
            if scanner.skipSymbol(58) { return readNumberBeforeColon(value) }
            if time.isExpecting(value), scanner.skipSymbol(46) {
                _ = time.add(value)
                guard case .number(let fraction, let fractionLength) = scanner.next() else { return false }
                time.addFinal(Self.milliseconds(value: fraction, length: fractionLength))
                return true
            }
            if zone.isExpecting(value) {
                zone.minute = value
                return true
            }
            if time.isExpecting(value) {
                time.addFinal(value)
                // After the time's last part comes the end, white space, `Z`, `+` or `-`.
                switch scanner.peek() {
                case .end, .whitespace, .sign, .keyword(.zone): return true
                default: return false
                }
            }
            guard day.add(value) else { return false }
            if scanner.peek() == .sign(-1) { _ = scanner.next() }
            return true
        }

        /// `n:` is an hour or a minute; `n::` an hour with no minute.
        private mutating func readNumberBeforeColon(_ value: Int64) -> Bool {
            if scanner.skipSymbol(58) {
                guard time.isEmpty else { return false }
                _ = time.add(value)
                _ = time.add(0)
                return true
            }
            guard time.add(value) else { return false }
            if scanner.peek() == .symbol(46) { _ = scanner.next() }
            return true
        }

        private mutating func readKeyword(_ keyword: JavaScriptDateKeyword) -> Bool {
            switch keyword {
            case .amPm(let offset) where !time.isEmpty:
                time.hourOffset = offset
            case .month(let month):
                day.namedMonth = month
                if scanner.peek() == .sign(-1) { _ = scanner.next() }
            case .zone(let hours) where hasReadNumber:
                zone.set(hours: hours)
            default:
                // A word is illegal after a number, and a number must not follow a word without a separator.
                if hasReadNumber { return false }
                if case .number = scanner.peek() { return false }
            }
            return true
        }

        /// A zone's offset after `UTC` or a time: `+0100`, `-5`, `+01:00`.
        private mutating func readZoneOffset(sign: Int64) -> Bool {
            zone.sign = sign
            var value: Int64 = 0
            var length = 0
            if case .number(let number, let numberLength) = scanner.peek() {
                _ = scanner.next()
                value = number
                length = numberLength
            }
            hasReadNumber = true
            if scanner.peek() == .symbol(58) {
                zone.hour = value
                zone.minute = nil
            } else if length == 1 || length == 2 {
                zone.hour = value
                zone.minute = 0
            } else if length == 3 || length == 4 {
                zone.hour = value / 100
                zone.minute = value % 100
            } else {
                return false
            }
            return true
        }

        /// The first three digits of a fraction's numeral, as milliseconds.
        private static func milliseconds(value: Int64, length: Int) -> Int64 {
            var number = value
            var digits = min(length, JavaScriptDateScanner.maximumSignificantDigits)
            if digits < 3 {
                number *= digits == 1 ? 100 : 10
            } else {
                while digits > 3 {
                    number /= 10
                    digits -= 1
                }
            }
            return number
        }
    }
}
