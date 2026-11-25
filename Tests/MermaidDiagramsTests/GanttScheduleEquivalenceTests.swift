/**
 * File: GanttScheduleEquivalenceTests.swift
 * -----------------------------------------
 * Layer: Tests
 * Description: The Gantt schedule that reads each task's texts once gives every start, end and drawn end 0.7.0's gave
 *              (ReferenceGanttSchedule), or the same error, on every corpus chart and thousands of random ones; the axis
 *              format read once writes every date as 0.7.0's did (ReferenceGanttAxisFormat), for random specifiers.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 25/11/2026
 */

import XCTest
@testable import MermaidDiagrams
@testable import MermaidDiagramsBenchmark

final class GanttScheduleEquivalenceTests: XCTestCase {
    private struct Random {
        var state: UInt64

        mutating func below(_ bound: Int) -> Int {
            state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            return Int((state >> 33) % UInt64(max(bound, 1)))
        }

        mutating func pick(_ choices: [String]) -> String { choices[below(choices.count)] }
    }

    /// The schedule of `source` and the reference's: the same entries, or the same error; nil when it is no Gantt chart.
    private func agree(_ source: String, limits: MermaidDiagramLimits = .standard) throws -> Bool? {
        guard let chart = try? GanttChartReading.ganttChart(source, limits: limits) else { return nil }
        let now = try GanttScheduling.now()
        let zone = try GanttScheduling.zone("Europe/Paris")
        let entries = Result { () throws(GanttLayoutError) in try GanttSchedule(chart: chart, now: now, zone: zone, limits: limits).entries }
        let expected = Result { () throws(GanttLayoutError) in try ReferenceGanttSchedule(chart: chart, now: now, zone: zone, limits: limits).entries }
        switch (entries, expected) {
        case (.success(let read), .success(let reference)):
            return read.map { entry in [entry.start, entry.end, entry.drawnEnd].map(String.init(describing:)) + ["\(entry.isScheduled) \(entry.hasWrittenEnd)"] }
                == reference.map { entry in [entry.start, entry.end, entry.drawnEnd].map(String.init(describing:)) + ["\(entry.isScheduled) \(entry.hasWrittenEnd)"] }
        case (.failure(let error), .failure(let reference)): return error == reference
        default: return false
        }
    }

    func testEveryCorpusChartIsScheduledAsZeroSevenScheduledIt() throws {
        var compared = 0
        for source in try OutputDigest.corpora().flatMap(\.sources) {
            guard let agrees = try agree(source) else { continue }
            XCTAssertTrue(agrees, String(source.prefix(200)))
            compared += 1
        }
        XCTAssertGreaterThan(compared, 10)
    }

    /// Charts of tasks that come after or last until others written before or after them, by dates in several formats,
    /// durations, Unix times, excluded and included days, inclusive end dates and texts that are no date.
    func testRandomChartsAreScheduledAsZeroSevenScheduledThem() throws {
        var random = Random(state: 0x6A_7712)
        var compared = 0
        var scheduled = 0
        for index in 0..<2_500 {
            let format = random.pick(["YYYY-MM-DD", "YYYY-MM-DD", "DD/MM/YYYY", "x", "YYYY-MM-DD HH:mm", "X"])
            var lines = ["gantt", "dateFormat " + format]
            if random.below(3) == 0 { lines.append("excludes " + random.pick(["weekends", "sunday", "2024-01-03", "weekends, 2024-01-10", "friday"])) }
            if random.below(6) == 0 { lines.append("includes 2024-01-06") }
            if random.below(5) == 0 { lines.append("inclusiveEndDates") }
            if random.below(5) == 0 { lines.append("weekend friday") }
            let taskCount = 1 + index % 12
            for task in 0..<taskCount {
                if random.below(4) == 0 { lines.append("section S\(random.below(3))") }
                let start: String
                switch random.below(7) {
                case 0: start = "after t\(random.below(taskCount)) t\(random.below(taskCount))"
                case 1: start = "after missing"
                case 2: start = format.hasPrefix("x") || format == "X" ? String(1_704_067_200 + random.below(100) * 86_400) + (format == "x" ? "000" : "")
                    : format == "DD/MM/YYYY" ? "0\(1 + random.below(9))/01/2024" : "2024-01-0\(1 + random.below(9))"
                case 3: start = random.pick(["2024-01-01", "not a date", "2024-13-40", "01/02/2024"])
                case 4: start = ""
                default: start = "after t\(max(0, task - 1))"
                }
                let end = random.pick(["1d", "3d", "2w", "12h", "1M", "0.5d", "until t\(random.below(taskCount))", "2024-01-20", "2024-02-01 10:00",
                                       "until missing", "x", "5"])
                let fields = start.isEmpty ? [end] : [start, end]
                lines.append("T\(task) :" + (random.below(3) == 0 ? "" : "t\(task), ") + fields.joined(separator: ", "))
            }
            guard let agrees = try agree(lines.joined(separator: "\n")) else { continue }
            XCTAssertTrue(agrees, lines.joined(separator: "\n"))
            compared += 1
            if (try? GanttScheduling.schedule(lines.joined(separator: "\n"))) != nil { scheduled += 1 }
        }
        XCTAssertGreaterThan(compared, 2_000)
        XCTAssertGreaterThan(scheduled, 800, "enough charts should be scheduled, not refused")
    }

    /// Axis formats of every directive and padding, literal text beyond ASCII, a `%` joined to a mark, and a `%` at the
    /// end, each written for dates across the years as 0.7.0 wrote them.
    func testAxisFormatsWriteDatesAsZeroSevenWroteThem() throws {
        let pieces = ["%Y", "%m", "%d", "%e", "%-d", "%_e", "%0e", "%a", "%A", "%b", "%B", "%H", "%I", "%p", "%M", "%S", "%L", "%f", "%j", "%U", "%W",
                      "%V", "%G", "%g", "%u", "%w", "%y", "%q", "%x", "%X", "%c", "%Q", "%s", "%Z", "%%", "%k", "-", "/", " ", "é", "%\u{301}",
                      "%-\u{301}", "中", "%"]
        let zone = try GanttScheduling.zone("Europe/Paris")
        var random = Random(state: 0xA815_F0)
        for _ in 0..<3_000 {
            let specifier = (0..<random.below(6)).map { _ in pieces[random.below(pieces.count)] }.joined()
            let time = try GanttScheduling.time(Int64(1_990 + random.below(60)), Int64(1 + random.below(12)), Int64(1 + random.below(28)),
                                                Int64(random.below(24)), Int64(random.below(60)), Int64(random.below(60)), Int64(random.below(1_000)))
            XCTAssertEqual(GanttAxisFormat.format(specifier, time, zone: zone), ReferenceGanttAxisFormat.format(specifier, time, zone: zone),
                           specifier.debugDescription)
        }
    }
}

extension GanttScheduleEquivalenceTests {
    /// The tasks a start or an end names after `after` or `until`, read on the bytes of an ASCII text, are those Swift's
    /// characters and Foundation's trimming give, for texts of every spacing, line break and name character.
    func testReferencesAreReadAsSwiftsCharactersReadThem() {
        let pieces = ["after", "until", " ", "  ", "\t", "\n", "\r\n", "\u{0B}", "\u{0C}", "\u{1C}", "a1", "b-2", "c_3", "x.y", "é", "\u{A0}", "\u{85}",
                      "aft", "er", "#", "1", ""]
        var state: UInt64 = 0x2EF_E2E
        func below(_ bound: Int) -> Int {
            state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            return Int((state >> 33) % UInt64(bound))
        }
        for _ in 0..<30_000 {
            let text = (0..<below(7)).map { _ in pieces[below(pieces.count)] }.joined()
            for keyword in ["after", "until"] {
                XCTAssertEqual(GanttSchedule.references(after: keyword, in: text), GanttSchedule.referencesOfCharacters(after: keyword, in: text),
                               text.debugDescription)
            }
        }
    }
}
