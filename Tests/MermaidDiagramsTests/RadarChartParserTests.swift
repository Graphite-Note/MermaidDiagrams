/**
 * File: RadarChartParserTests.swift
 * ---------------------------------
 * Layer: Tests
 * Description: Reading radar charts: the inputs of Pele's ported specifications (radar.spec.ts, radar.test.ts), names the lexer keeps,
 *              errors with their lines, and the limits.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 19/11/2026
 */

import XCTest
@testable import MermaidDiagrams

final class RadarChartParserTests: XCTestCase {
    private func spacings(_ context: String) -> [String] { [context, "  \(context)  ", "\t\(context)\t", "\n    \t\(context)\n    "] }

    func testEveryKeywordFormIsReadInAnySpacing() throws {
        for keyword in ["radar-beta", "radar-beta:", "radar-beta :"] {
            for source in spacings(keyword) { XCTAssertEqual(try SimpleChartReading.radar(source), RadarChart(), source) }
        }
    }

    func testTitlesAreReadAfterTheKeywordOnItsLineOrOnLinesOfTheirOwn() throws {
        for context in spacings(" title My Title") + spacings("\n  title My Title") {
            XCTAssertEqual(try SimpleChartReading.radar("radar-beta\(context)").title, "My Title", context)
        }
        for context in spacings(" accDescr: My Accessible Description") + spacings("\n  accDescr: My Accessible Description") {
            XCTAssertEqual(try SimpleChartReading.radar("radar-beta\(context)").accessibilityDescription, "My Accessible Description")
        }
        let all = try SimpleChartReading.radar("radar-beta\n  title My Title\n  accDescr: My Accessible Description\n  accTitle: My Accessible Title")
        XCTAssertEqual([all.title, all.accessibilityDescription, all.accessibilityTitle], ["My Title", "My Accessible Description", "My Accessible Title"])
    }

    func testADiagramWithDataAndTitlesAsTheSpecificationWritesIt() throws {
        let chart = try SimpleChartReading.radar("radar-beta\n    title Radar diagram\n    accTitle: Radar accTitle\n    accDescr: Radar accDescription\n    axis A[\"Axis A\"], B[\"Axis B\"] ,C[\"Axis C\"]\n    curve mycurve[\"My Curve\"]{1,2,3}\n    ")
        XCTAssertEqual(chart.axes.map(\.name), ["A", "B", "C"])
        XCTAssertEqual(chart.axes.map { axis in axis.label.spokenText }, ["Axis A", "Axis B", "Axis C"])
        XCTAssertEqual(chart.curves.map(\.name), ["mycurve"])
        XCTAssertEqual(chart.curves[0].label.spokenText, "My Curve")
        XCTAssertEqual(chart.curves[0].values, [1, 2, 3])
        XCTAssertEqual(chart.options, RadarChartOptions())
        XCTAssertEqual(chart.options.tickCount, 5)
        XCTAssertNil(chart.options.maximum)
    }

    func testAxesAreListedOnOneLineOrSeveralAndLabelledOrNot() throws {
        for source in ["axis my-axis", "axis my-axis[\"My Axis Label\"]"] {
            XCTAssertEqual(try SimpleChartReading.radar("radar-beta\n\(source)").axes.map(\.name), ["my-axis"], source)
        }
        for source in ["axis my-axis[\"My Axis Label\"]\n      axis my-axis2", "axis my-axis, my-axis2", "axis my-axis[\"My Axis Label\"], my-axis2",
                       "axis my-axis, my-axis2[\"My Second Axis Label\"]", "axis my-axis [\"L\"], my-axis2\t[\"M\"]"] {
            XCTAssertEqual(try SimpleChartReading.radar("radar-beta\n\(source)").axes.map(\.name), ["my-axis", "my-axis2"], source)
        }
        XCTAssertEqual(try SimpleChartReading.radar("radar-beta\naxis my-axis [\"My Axis Label\"], my-axis2\t[\"My Second Axis Label\"]").axes.map { axis in axis.label.spokenText },
                       ["My Axis Label", "My Second Axis Label"])
        XCTAssertEqual(try SimpleChartReading.radar("radar-beta\naxis a[\"#35;x &amp;y\"]").axes[0].label.spokenText, "#x &y")
    }

    func testAxisListsAreRefusedWhereTheyBreak() {
        XCTAssertEqual(SimpleChartReading.readError("radar-beta\naxis"), .invalidSyntax(line: 2, problem: .radar(.expectedName)))
        XCTAssertNotNil(SimpleChartReading.readError("radar-beta\naxis my-axis my-axis2"))
        XCTAssertEqual(SimpleChartReading.readError("radar-beta\naxis A,\nB"), .invalidSyntax(line: 2, problem: .radar(.expectedName)))
        XCTAssertEqual(SimpleChartReading.readError("radar-beta\naxis A[x]"), .invalidSyntax(line: 2, problem: .radar(.expectedLabel)))
        XCTAssertEqual(SimpleChartReading.readError("radar-beta\naxis A[\"x\""), .invalidSyntax(line: 2, problem: .radar(.expectedLabel)))
        XCTAssertEqual(SimpleChartReading.readError("radar-beta\naxis a[\"x"), .invalidSyntax(line: 2, problem: .unclosedQuotation))
        XCTAssertNotNil(SimpleChartReading.readError("radar-beta\naxis 1a"))
        XCTAssertNotNil(SimpleChartReading.readError("radar-beta\naxis a-"))
    }

    func testCurvesTakeNumbersOrNamedEntriesInAnyOrder() throws {
        let numbers = try SimpleChartReading.radar("radar-beta\naxis A,B,C\ncurve mycurve{1,2,3}")
        XCTAssertEqual(numbers.curves[0].values, [1, 2, 3])
        let named = try SimpleChartReading.radar("radar-beta\naxis A,B,C\ncurve mycurve{ C: 3, A: 1, B: 2 }")
        XCTAssertEqual(named.curves[0].values, [1, 2, 3])
        XCTAssertEqual(try SimpleChartReading.radar("radar-beta\naxis ax1, ax2\ncurve c{ ax2 2, ax1 1.5 }").curves[0].values, [1.5, 2])
        XCTAssertEqual(try SimpleChartReading.radar("radar-beta\naxis ax1, ax2\ncurve c{ ax1 1, ax1 5, ax2 2 }").curves[0].values, [1, 2], "The first entry of an axis wins")
        for source in ["curve my-curve { 1 }", "curve my-curve {\n        1\n      }", "curve my-curve {\n\n      1\n\n      }"] {
            XCTAssertEqual(try SimpleChartReading.radar("radar-beta\naxis my-axis\n\(source)").curves[0].values, [1], source)
        }
        XCTAssertEqual(try SimpleChartReading.radar("radar-beta\naxis ax1, ax2\ncurve c1{ ax1 1, ax2 2 }\ncurve c2{\n ax1 3,\n ax2 4\n}").curves.map(\.values), [[1, 2], [3, 4]])
        XCTAssertEqual(try SimpleChartReading.radar("radar-beta\naxis ax1, ax2\ncurve c1{ 1, 2 }, c2{ 3, 4 }").curves.map(\.name), ["c1", "c2"])
        XCTAssertEqual(try SimpleChartReading.radar("radar-beta\ncurve a{1,2,3}").curves[0].values, [1, 2, 3], "Numbers need no axes; the curve is left out when drawn")
    }

    func testCurvesWithNamedEntriesAreMatchedWithTheAxesOnceTheyAreAllRead() throws {
        XCTAssertEqual(try SimpleChartReading.radar("radar-beta\ncurve c{ B: 2, A: 1 }\naxis A, B").curves[0].values, [1, 2])
        XCTAssertEqual(SimpleChartReading.readError("radar-beta\naxis A[\"Alpha\"], B\ncurve c{ B: 2 }"),
                       .invalidSyntax(line: 3, problem: .radar(.missingEntry(curve: "c", axis: "Alpha"))))
        XCTAssertEqual(SimpleChartReading.readError("radar-beta\n curve c{ B: 2 }"), .invalidSyntax(line: 2, problem: .radar(.entriesNamedBeforeAxes(curve: "c"))))
    }

    func testCurvesAreRefusedWhereTheyBreak() {
        XCTAssertNotNil(SimpleChartReading.readError("radar-beta\ncurve my-curve"))
        XCTAssertNotNil(SimpleChartReading.readError("radar-beta\naxis my-axis\ncurve my-curve[\"Label\"]"))
        XCTAssertEqual(SimpleChartReading.readError("radar-beta\naxis a\ncurve"), .invalidSyntax(line: 3, problem: .radar(.expectedName)))
        XCTAssertEqual(SimpleChartReading.readError("radar-beta\naxis a\ncurve c{}"), .invalidSyntax(line: 3, problem: .radar(.expectedName)))
        XCTAssertEqual(SimpleChartReading.readError("radar-beta\naxis a\ncurve c{1,}"), .invalidSyntax(line: 3, problem: .radar(.expectedNumber)))
        XCTAssertEqual(SimpleChartReading.readError("radar-beta\naxis a\ncurve c{1 2}"), .invalidSyntax(line: 3, problem: .radar(.expectedClosingBrace)))
        XCTAssertEqual(SimpleChartReading.readError("radar-beta\naxis a\ncurve c 1"), .invalidSyntax(line: 3, problem: .radar(.expectedOpeningBrace)))
        XCTAssertNotNil(SimpleChartReading.readError("radar-beta\naxis ax1, ax2\ncurve my-curve { 1, ax1 2 }"))
        XCTAssertNotNil(SimpleChartReading.readError("radar-beta\naxis ax1, ax2\ncurve my-curve { ax1 1 ax2 2 }"))
        XCTAssertNotNil(SimpleChartReading.readError("radar-beta\naxis a\ncurve c{-5}"))
        XCTAssertNotNil(SimpleChartReading.readError("radar-beta\naxis a\ncurve c{1.2.3}"))
        XCTAssertNotNil(SimpleChartReading.readError("radar-beta\naxis a\ncurve c{05}"))
    }

    func testOptionsAreReadWithTheirKinds() throws {
        let options = try SimpleChartReading.radar("radar-beta\n    ticks 10\n    showLegend false\n    graticule polygon\n    min 1\n    max 10\n    ").options
        XCTAssertEqual(options, { var expected = RadarChartOptions(); expected.tickCount = 10; expected.showsLegend = false; expected.graticule = .polygon; expected.minimum = 1; expected.maximum = 10; return expected }())
        for number in ["ticks 5", "min 50", "max 50", "max 1.5", "min 0"] { XCTAssertNil(SimpleChartReading.readError("radar-beta\naxis a\n\(number)"), number) }
        XCTAssertEqual(try SimpleChartReading.radar("radar-beta\nshowLegend true, ticks 3, max 1.5, min 0, graticule polygon").options.tickCount, 3)
        XCTAssertEqual(try SimpleChartReading.radar("radar-beta\nticks 5\nticks 6\nticks 7").options.tickCount, 7, "The last of an option wins")
        XCTAssertEqual(try SimpleChartReading.radar("radar-beta\nticks 3\nticks 100").options.tickCount, 32)
        XCTAssertEqual(try SimpleChartReading.radar("radar-beta\nticks \(String(repeating: "9", count: 400))").options.tickCount, 32)
    }

    func testTickCountsAreCutToThirtyTwoAsTheSpecificationHasIt() throws {
        for (ticks, expected) in [(12, 12.0), (32, 32), (33, 32)] {
            XCTAssertEqual(try SimpleChartReading.radar("radar-beta\n      ticks \(ticks)\n      ").options.tickCount, expected)
        }
    }

    func testOptionsAreRefusedWhereTheyBreak() {
        XCTAssertEqual(SimpleChartReading.readError("radar-beta\nshowLegend TRUE"), .invalidSyntax(line: 2, problem: .radar(.expectedBoolean)))
        XCTAssertEqual(SimpleChartReading.readError("radar-beta\ngraticule square"), .invalidSyntax(line: 2, problem: .radar(.expectedGraticule)))
        XCTAssertEqual(SimpleChartReading.readError("radar-beta\nmax -5"), .invalidSyntax(line: 2, problem: .radar(.expectedNumber)))
        XCTAssertEqual(SimpleChartReading.readError("radar-beta\nmax 5."), .invalidSyntax(line: 2, problem: .radar(.expectedNumber)))
        XCTAssertEqual(SimpleChartReading.readError("radar-beta\nticks 5, axis"), .invalidSyntax(line: 2, problem: .radar(.expectedOption)))
        XCTAssertEqual(SimpleChartReading.readError("radar-beta\nticks\n5"), .invalidSyntax(line: 2, problem: .radar(.expectedNumber)))
    }

    func testNamesThatStartWithAKeptWordAreNamesAndTheKeptWordsAloneAreNot() throws {
        let chart = try SimpleChartReading.radar("radar-beta\n axis circles, polygonal, trueNorth, falsey, titles\n curve titles{1, 2, 3, 4, 5}, circles{ circles: 1, polygonal 2, trueNorth: 3, falsey 4, titles: 5 }")
        XCTAssertEqual(chart.axes.map(\.name), ["circles", "polygonal", "trueNorth", "falsey", "titles"])
        XCTAssertEqual(chart.curves.map(\.values), [[1, 2, 3, 4, 5], [1, 2, 3, 4, 5]])
        XCTAssertNil(chart.title)
        XCTAssertNotNil(SimpleChartReading.readError("radar-beta\n axis circle, b"))
        XCTAssertNotNil(SimpleChartReading.readError("radar-beta\naxis true"))
        XCTAssertNotNil(SimpleChartReading.readError("radar-beta\naxis axis"))
        XCTAssertEqual(try SimpleChartReading.radar("radar-beta\naxis maxi, min-1, _x, axis-1").axes.map(\.name), ["maxi", "min-1", "_x", "axis-1"])
        XCTAssertNotNil(SimpleChartReading.readError("radar-beta\naxisx a"))
        XCTAssertNotNil(SimpleChartReading.readError("radar-beta\ntitleaxis a"))
    }

    func testAValueTakesTheKeptWordsGluedToIt() throws {
        let glued = try SimpleChartReading.radar("radar-beta\n axis a, b\n showLegend falsecurve x{1, 2}\n graticule polygonaxis c")
        XCTAssertFalse(glued.options.showsLegend)
        XCTAssertEqual(glued.options.graticule, .polygon)
        XCTAssertEqual(glued.axes.map(\.name), ["a", "b", "c"])
        XCTAssertEqual(glued.curves.map(\.name), ["x"])
    }

    func testStatementsFollowOneAnotherOnALine() throws {
        let chart = try SimpleChartReading.radar("radar-beta axis A, B curve c{1, 2} ticks 5 max 10")
        XCTAssertEqual(chart.axes.count, 2)
        XCTAssertEqual(chart.options.maximum, 10)
    }

    func testCommentsDirectivesAndFrontMatterAreSkippedAndOptionsComeFromThem() throws {
        let chart = try SimpleChartReading.radar("---\ntitle: From front matter\nconfig:\n  radar:\n    axisScaleFactor: 0.25\n    curveTension: 0.1\n    width: 99999\n    marginTop: -1\n---\n%%{init: {'radar': {'marginLeft': 80}}}%%\nradar-beta\n    %% This is a comment\n    axis A,B,C\n    curve mycurve{1,2,3}\n")
        XCTAssertEqual(chart.title, "From front matter")
        XCTAssertEqual(chart.appearance.axisScaleFactor, 0.25)
        XCTAssertEqual(chart.appearance.curveTension, 0.1)
        XCTAssertEqual(chart.appearance.width, 4_000)
        XCTAssertEqual(chart.appearance.marginTop, 16)
        XCTAssertEqual(chart.appearance.marginLeft, 80)
        XCTAssertEqual(RadarAppearance(), try SimpleChartReading.radar("radar-beta").appearance)
    }

    func testCountsPastTheLimitsAreRefused() {
        var limits = MermaidDiagramLimits.standard
        limits.maximumNodeCount = 4
        limits.maximumEdgeCount = 6
        XCTAssertEqual(SimpleChartReading.readError("radar-beta\naxis a, b, c, d, e", limits: limits), .tooManyNodes(limit: 4))
        XCTAssertEqual(SimpleChartReading.readError("radar-beta\naxis a, b\ncurve c{1}, d{2}, e{3}", limits: limits), .tooManyNodes(limit: 4))
        XCTAssertEqual(SimpleChartReading.readError("radar-beta\ncurve c{1,2,3,4,5,6,7}", limits: limits), .tooManyChartValues(limit: 6))
        XCTAssertEqual(SimpleChartReading.readError("radar-beta\ncurve c{" + String(repeating: "0,", count: 50_000) + "0}"), .sourceTooLarge(limitBytes: 50_000))
    }
}
