/**
 * File: GanttConfigurationAndClickTests.swift
 * -------------------------------------------
 * Layer: Tests
 * Description: A Gantt chart's weekday and display mode from its front matter, its compact rows packed as Pele packs them,
 *              and click statements whose call runs past the line or that a statement follows on the line.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 19/11/2026
 */

import CoreGraphics
import XCTest
@testable import MermaidDiagrams

final class GanttConfigurationAndClickTests: XCTestCase {
    private let header = "gantt\n    dateFormat YYYY-MM-DD\n"

    private func chart(_ source: String) throws -> GanttChart {
        try GanttChartReading.ganttChart(source)
    }

    private func rowMiddles(_ source: String) throws -> [CGFloat] {
        let chart = try GanttChartReading.ganttChart(source)
        let zone = try GanttScheduling.zone("UTC")
        let moment = try GanttScheduling.now()
        let schedule = try GanttSchedule(chart: chart, now: moment, zone: zone, limits: .standard)
        let measurers = GanttMeasurers(title: UniformWidthTextMeasurer(), row: UniformWidthTextMeasurer(characterWidth: 6, fontSize: 13, lineHeight: 20),
                                       axis: UniformWidthTextMeasurer(characterWidth: 6, fontSize: 12, lineHeight: 18))
        let layout = GanttLayoutEngine.layout(chart, schedule: schedule.entries, now: moment, zone: zone, measurers: measurers, font: UniformWidthLayout.font)
        return try XCTUnwrap(layout.plot).tasks.map(\.label.center.y)
    }

    func testTheConfigsWeekdayStartsTheWeekUnlessAStatementSaysOtherwise() throws {
        XCTAssertEqual(try chart("---\nconfig:\n  gantt:\n    weekday: monday\n---\n" + header).weekStart, .monday)
        XCTAssertEqual(try chart("---\nconfig:\n  gantt:\n    weekday: monday\n---\n" + header + "    weekday friday\n").weekStart, .friday)
        XCTAssertEqual(try chart("---\nconfig:\n  gantt:\n    weekday: Monday\n---\n" + header).weekStart, .sunday, "Pele looks the name up as written.")
        XCTAssertEqual(try chart("%%{init: {\"gantt\": {\"weekday\": \"wednesday\"}}}%%\n" + header).weekStart, .wednesday)
    }

    func testTheFrontMattersOwnDisplayModeIsTheChartsAsPeleMovesItThere() throws {
        XCTAssertTrue(try chart("---\ndisplayMode: compact\n---\n" + header).isCompact)
        XCTAssertTrue(try chart("---\ndisplayMode: compact\nconfig:\n  gantt:\n    displayMode: standard\n---\n" + header).isCompact,
                      "The front matter's own key is set over its config.")
        XCTAssertFalse(try chart("---\ndisplayMode: compact\n---\n%%{init: {\"gantt\": {\"displayMode\": \"standard\"}}}%%\n" + header).isCompact,
                       "A directive is applied over both.")
        XCTAssertFalse(try chart("---\nconfig:\n  gantt:\n    displayMode: Compact\n---\n" + header).isCompact, "Pele compares the mode as written.")
    }

    func testCompactRowsGroupASectionWrittenTwiceAndPackItsTasksByStart() throws {
        let middles = try rowMiddles("---\ndisplayMode: compact\n---\n" + header + """
            section A
                Late    :2014-01-10, 2d
                Early   :2014-01-01, 2d
                Middle  :2014-01-03, 3d
            section B
                Other   :2014-01-01, 2d
            section A
                Again   :2014-01-20, 2d
        """)
        XCTAssertEqual(Set([middles[0], middles[1], middles[2], middles[4]]).count, 1,
                       "Sorted by start, A's tasks follow each other on one row, the second A included.")
        XCTAssertNotEqual(middles[3], middles[0], "B has a row of its own.")
        XCTAssertLessThan(middles[0], middles[3], "A's rows come first, as A appears first.")
    }

    func testACallWithoutItsParenthesisRunsToTheEndOfTheTextAsInPele() throws {
        let chart = try chart(header + "    One :t1, 2014-01-01, 1d\n    click t1 call notify\n    Two :t2, 2014-01-02, 1d\n")
        XCTAssertEqual(chart.tasks.map(\.name), ["One"], "The call's name takes in the rest of the text.")
        XCTAssertTrue(chart.tasks[0].isClickable)
    }

    func testAStatementAfterAClickOnItsLineIsRead() throws {
        let chart = try chart(header + "    One :t1, 2014-01-01, 1d\n    click t1 href \"https://example.com\" Two : 2014-01-02, 1d\n")
        XCTAssertEqual(chart.tasks.map(\.name), ["One", "Two"])
        XCTAssertEqual(chart.tasks[0].link, "https://example.com")
        XCTAssertNotNil(GanttChartReading.readError(header + "    One :t1, 2014-01-01, 1d\n    click t1 call notify() extra\n"),
                        "Text after the click with no colon is a task without data, refused as in Pele.")
    }
}
