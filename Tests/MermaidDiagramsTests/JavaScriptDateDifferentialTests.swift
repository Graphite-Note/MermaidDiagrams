/**
 * File: JavaScriptDateDifferentialTests.swift
 * -------------------------------------------
 * Layer: Tests
 * Description: The dates a Gantt chart's start falls back to, compared with what V8's `new Date(text)` itself read in
 *              Pele's sandbox: month names, commas, two-digit years, times, zones and the texts V8 refuses.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 23/11/2026
 */

import XCTest
@testable import MermaidDiagrams
@testable import MermaidDiagramsBenchmark

/// `pele-preprocessing.json`'s `dates` (scripts/pele/preprocessing-recorder.ts, run with TZ=UTC): each text and the
/// moment V8 read, or nothing; `GanttFallbackDate` in UTC must read the same moment, or refuse the text.
final class JavaScriptDateDifferentialTests: XCTestCase {
    func testEveryTextIsReadAsVEightReadsIt() throws {
        let dates = try PeleResults.preprocessing().dates
        XCTAssertGreaterThan(dates.count, 40)
        let zone = GanttTimeZone(timeZone: TimeZone(identifier: "UTC") ?? .gmt)
        for date in dates {
            // Pele trims a start date before it is read (gantt/db.ts `getStartDate`).
            let mine = GanttFallbackDate.parse(date.text.trimmingCharacters(in: .whitespaces), zone: zone)
            XCTAssertEqual(mine.map { time in Double(time.milliseconds) }, date.milliseconds, date.text.debugDescription)
        }
    }
}
