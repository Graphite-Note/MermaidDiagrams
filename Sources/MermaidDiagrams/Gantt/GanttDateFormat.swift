/**
 * File: GanttDateFormat.swift
 * ---------------------------
 * Layer: Core
 * Description: A Gantt chart's date format in the tokens of Mermaid's date library: splits its template into tokens and
 *              literal text, writes a time in it and reads a date strictly in it.
 *
 * Authors: Félix Chevalier, Bahey Shalash
 * Version: 0.3
 * Date: 23/11/2026
 */

/// A date format in the tokens of Mermaid's date library (dayjs with the plugins Mermaid loads, in English): it
/// formats a time, and reads a date strictly as `dayjs(text, format, true)` does, field by field, keeping the result
/// only when formatting it gives the text back. A token Mermaid's library cannot format (`w`, `gggg`, `z`) makes the
/// format write and read nothing.
struct GanttDateFormat {
    /// What a format is made of: tokens, and the text between them.
    enum Piece: Equatable {
        case literal(String)
        case token(GanttDateToken)
    }

    let pieces: [Piece]
    /// Whether no template was given: such a format writes dayjs's default and reads nothing.
    private let isEmpty: Bool

    /// dayjs's format when none is given.
    static let defaultTemplate = "YYYY-MM-DDTHH:mm:ssZ"
    static let isoDate = GanttDateFormat("YYYY-MM-DD")

    init(_ template: String) {
        isEmpty = template.isEmpty
        pieces = Self.pieces(of: template.isEmpty ? Self.defaultTemplate : template)
    }

    /// Splits a template into tokens, `[escaped text]` and the characters between, trying longer tokens first.
    private static func pieces(of template: String) -> [Piece] {
        // In ASCII without a carriage return every byte is a character of its own, so the bytes are split instead.
        if template.utf8.allSatisfy({ byte in byte < 0x80 && byte != 0x0D }) { return pieces(ofASCII: Array(template.utf8)) }
        return pieces(ofCharacters: template)
    }

    /// `pieces(of:)` read character by character, for any template.
    static func pieces(ofCharacters template: String) -> [Piece] {
        var pieces: [Piece] = []
        var rest = Substring(template)
        while let first = rest.first {
            if first == "[", let closing = rest.dropFirst().firstIndex(of: "]"), closing > rest.index(after: rest.startIndex) {
                pieces.append(.literal(String(rest[rest.index(after: rest.startIndex)..<closing])))
                rest = rest[rest.index(after: closing)...]
            } else if let (spelling, token) = GanttDateToken.spellings.first(where: { spelling, _ in rest.hasPrefix(spelling) }) {
                pieces.append(.token(token))
                rest = rest.dropFirst(spelling.count)
            } else {
                pieces.append(.literal(String(first)))
                rest = rest.dropFirst()
            }
        }
        return pieces
    }

    /// `pieces(of:)` on the bytes of an ASCII template.
    static func pieces(ofASCII bytes: [UInt8]) -> [Piece] {
        var pieces: [Piece] = []
        var index = 0
        while index < bytes.count {
            let byte = bytes[index]
            if byte == UInt8(ascii: "["), let closing = bytes[(index + 1)...].firstIndex(of: UInt8(ascii: "]")), closing > index + 1 {
                pieces.append(.literal(String(decoding: bytes[(index + 1)..<closing], as: UTF8.self)))
                index = closing + 1
            } else if let (spelling, token) = asciiSpellings.first(where: { spelling, _ in bytes[index...].starts(with: spelling) }) {
                pieces.append(.token(token))
                index += spelling.count
            } else {
                pieces.append(.literal(String(Unicode.Scalar(byte))))
                index += 1
            }
        }
        return pieces
    }

    private static let asciiSpellings = GanttDateToken.spellings.map { spelling, token in (Array(spelling.utf8), token) }

    /// The time written in this format, or nil when the format has a token Mermaid's library cannot format.
    func format(_ time: GanttTime, zone: GanttTimeZone) -> String? {
        var text = ""
        for piece in pieces {
            switch piece {
            case .literal(let literal): text += literal
            case .token(let token):
                guard let written = token.written(time, zone: zone) else { return nil }
                text += written
            }
        }
        return text
    }

    /// The date `text` writes in this format, missing fields taken from `now` as Mermaid's library takes them, or nil
    /// when the text is not exactly the format of a date.
    func parse(_ text: String, now: GanttTime, zone: GanttTimeZone) -> GanttTime? {
        guard !isEmpty else { return nil }
        if pieces.count == 1, case .token(let token) = pieces[0], let unitMilliseconds = token.unixUnitMilliseconds {
            guard let number = Int64(text), String(number) == text else { return nil }
            let (milliseconds, overflows) = number.multipliedReportingOverflow(by: unitMilliseconds)
            return overflows ? nil : zone.wallClockTime(unixMilliseconds: milliseconds)
        }
        var reader = GanttDateFieldReader(text: text)
        for piece in pieces {
            switch piece {
            case .literal(let literal): guard reader.skip(literal) else { return nil }
            case .token(let token): guard reader.read(token) else { return nil }
            }
        }
        guard let time = reader.fields.time(now: now, zone: zone), format(time, zone: zone) == text else { return nil }
        return time
    }

    /// A date as `YYYY-MM-DD`, as the chart's excluded days name dates.
    static func isoDateText(_ time: GanttTime) -> String {
        let (year, month, day) = time.date
        return GanttDateToken.padded(year, width: 4) + "-" + GanttDateToken.padded(month, width: 2) + "-" + GanttDateToken.padded(day, width: 2)
    }
}
