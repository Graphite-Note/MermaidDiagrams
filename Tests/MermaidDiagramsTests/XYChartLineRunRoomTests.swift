/**
 * File: XYChartLineRunRoomTests.swift
 * -----------------------------------
 * Layer: Tests
 * Description: The room an XY chart's line reserves for its runs grows with its values, not with their square: a
 *              line that leaves and enters the value range at every value, or cannot draw every other value, makes a
 *              run per value without each run reserving room for the rest of the line.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 25/11/2026
 */

import Foundation
import XCTest
@testable import MermaidDiagrams

final class XYChartLineRunRoomTests: XCTestCase {
    private let typography = DiagramTypography(font: DiagramFont(postScriptName: nil, size: 16))

    /// The points reserved for every run of the chart's lines, and how many runs they make.
    private func reservedRoom(_ source: String) throws -> (points: Int, runs: Int, values: Int) {
        let chart = try XYChartReading.chart(source)
        let layout = try XYChartLayoutEngine.layout(chart, typography: typography)
        let runs = layout.lines.flatMap(\.runs)
        return (runs.reduce(0) { total, run in total + run.capacity }, runs.count, chart.series.reduce(0) { total, series in total + series.values.count })
    }

    /// 4,000 values swinging across a narrow range: each value's segment is a run of its own, and the runs hold a few
    /// points each, not room for every value after them (eight million points before).
    func testALineCrossingTheRangeAtEveryValueReservesRoomOnce() throws {
        let values = (0..<4_000).map { index in index % 2 == 0 ? "0" : "100" }.joined(separator: ", ")
        let start = Date()
        let room = try reservedRoom("xychart-beta\n  y-axis 40 --> 60\n  line [\(values)]\n")
        XCTAssertLessThan(Date().timeIntervalSince(start), 2)
        XCTAssertGreaterThan(room.runs, 3_900)
        XCTAssertLessThan(room.points, 8 * room.values)
    }

    /// A line whose every other value cannot be drawn (310 digits, too large for a number) starts a run at each value it
    /// has.
    func testALineMissingEveryOtherValueReservesRoomOnce() throws {
        let tooLarge = String(repeating: "9", count: 310)
        let values = (0..<150).map { index in index % 2 == 0 ? "1" : tooLarge }.joined(separator: ", ")
        let room = try reservedRoom("xychart-beta\n  y-axis 0 --> 3\n  line [\(values)]\n")
        XCTAssertEqual(room.runs, 75)
        XCTAssertLessThan(room.points, 8 * room.values)
    }

    /// A line inside its range keeps one run with room for all its points, as the layout reserves it.
    func testALineInsideTheRangeIsOneRun() throws {
        let values = (0..<500).map { index in String(index % 7) }.joined(separator: ", ")
        let room = try reservedRoom("xychart-beta\n  y-axis 0 --> 10\n  line [\(values)]\n")
        XCTAssertEqual(room.runs, 1)
        XCTAssertGreaterThanOrEqual(room.points, 500)
    }
}
