/**
 * File: QuadrantChartOptionsTests.swift
 * -------------------------------------
 * Layer: Tests
 * Description: The quadrant chart options of the front matter and directives, and the narrow column's page, as
 *              Pele's quadrant renderer applies them.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 19/11/2026
 */

import XCTest
@testable import MermaidDiagrams

final class QuadrantChartOptionsTests: XCTestCase {
    private let body = "quadrantChart\n title Reach\n x-axis Low --> High\n y-axis Down --> Up\n quadrant-1 Expand\n quadrant-3 Drop\n A: [0.3, 0.6]\n B: [0.8, 0.2]"

    private func chart(_ options: String, flow: Bool = false) throws -> QuadrantChart {
        let front = flow ? "---\nconfig:\n  quadrantChart: {\(options)}\n---\n" : "---\nconfig:\n  quadrantChart:\n    " + options.replacingOccurrences(of: ", ", with: "\n    ") + "\n---\n"
        return try QuadrantChartReading.quadrantChart(front + body)
    }

    private func layout(_ options: String, availableWidth: CGFloat? = nil) throws -> QuadrantChartLayout {
        let source = "---\nconfig:\n  quadrantChart:\n    " + options.replacingOccurrences(of: ", ", with: "\n    ") + "\n---\n" + body
        return try QuadrantChartReading.uniformLayout(source, availableWidth: availableWidth)
    }

    private func plot(_ layout: QuadrantChartLayout) -> CGRect {
        layout.quadrants.map(\.frame).reduce(layout.quadrants[0].frame) { union, frame in union.union(frame) }
    }

    func testOptionsAreReadFromBlockFlowAndDirectiveForms() throws {
        let written = "chartWidth: 300, chartHeight: 250, titleFontSize: 20, quadrantPadding: 12, pointRadius: 7, xAxisPosition: bottom, yAxisPosition: right"
        for flow in [false, true] {
            let options = try chart(written, flow: flow).options
            XCTAssertEqual(options.chartWidth, 300)
            XCTAssertEqual(options.chartHeight, 250)
            XCTAssertEqual(options.titleFontSize, 20)
            XCTAssertEqual(options.quadrantPadding, 12)
            XCTAssertEqual(options.pointRadius, 7)
            XCTAssertTrue(options.xAxisIsBelow)
            XCTAssertTrue(options.yAxisIsRight)
        }
        let directive = try QuadrantChartReading.quadrantChart("%%{init: {'quadrantChart': {'chartWidth': 320, 'pointTextPadding': 9}}}%%\n" + body).options
        XCTAssertEqual(directive.chartWidth, 320)
        XCTAssertEqual(directive.pointTextPadding, 9)
        XCTAssertEqual(try QuadrantChartReading.quadrantChart(body).options, QuadrantChartOptions())
    }

    func testValuesOutOfRangeOrOfTheWrongKindAreCutOrLeftAtTheirDefaults() throws {
        let options = try chart("chartWidth: 99999, chartHeight: -5, titleFontSize: 200, quadrantLabelFontSize: 1, pointRadius: big, quadrantPadding: 900, xAxisPosition: top").options
        XCTAssertEqual(options.chartWidth, 4_000, "Cut to its most")
        XCTAssertNil(options.chartHeight, "Below zero is no length")
        XCTAssertEqual(options.titleFontSize, 72)
        XCTAssertEqual(options.quadrantLabelFontSize, 4)
        XCTAssertNil(options.pointRadius)
        XCTAssertEqual(options.quadrantPadding, 200)
        XCTAssertFalse(options.xAxisIsBelow)
    }

    func testTheChartsOwnSizeIsThePageFromAHundredPoints() throws {
        XCTAssertEqual(try layout("chartWidth: 300, chartHeight: 250").size, CGSize(width: 300, height: 250))
        XCTAssertEqual(try layout("chartWidth: 20, chartHeight: 30").size, CGSize(width: 100, height: 100))
        XCTAssertEqual(try layout("chartWidth: 333.6").size, CGSize(width: 334, height: 500), "A width is rounded")
    }

    func testTextSizesPaddingsAndTheAxesFollowTheOptions() throws {
        let plain = try layout("")
        let large = try layout("titleFontSize: 30, quadrantLabelFontSize: 20, pointLabelFontSize: 20, xAxisLabelFontSize: 18")
        XCTAssertEqual(try XCTUnwrap(large.title).fontSize, 30)
        XCTAssertEqual(try XCTUnwrap(large.quadrants[0].text).fontSize, 20)
        XCTAssertEqual(large.points[0].text.fontSize, 20)
        XCTAssertEqual(large.axisLabels[0].text.fontSize, 18)
        XCTAssertEqual(large.axisLabels[2].text.fontSize, 14, "The y axis keeps its own size")
        XCTAssertGreaterThan(try XCTUnwrap(large.title).size.height, try XCTUnwrap(plain.title).size.height)
        let padded = try layout("quadrantPadding: 20, xAxisLabelPadding: 11, yAxisLabelPadding: 13, titlePadding: 30")
        XCTAssertEqual(plot(padded).minX - plot(plain).minX, 12 + 8, "Twelve more around, and eight more beside the y axis's texts")
        XCTAssertEqual(plot(padded).maxX, 500 - 20)
        XCTAssertEqual(padded.axisLabels[0].text.frame.minY - plot(padded).maxY, 11)
        XCTAssertEqual(plot(padded).minX - padded.axisLabels[2].text.center.x, 13 + 21 / 2, "Its padding and half its turned height")
        XCTAssertEqual(try XCTUnwrap(padded.title).center.y, (24 + 30) / 2)
        let radius = try layout("pointRadius: 9")
        XCTAssertEqual(radius.points.map(\.radius), [9, 9])
        let topPadding = try layout("quadrantTextTopPadding: 15")
        XCTAssertEqual(try XCTUnwrap(topPadding.quadrants[0].text).frame.minY - topPadding.quadrants[0].frame.minY, 15)
    }

    func testTheAxesCanStandBelowBeforeTheChartHasPointsAndAtTheRight() throws {
        let source = "quadrantChart\n x-axis Left --> Right\n y-axis Down --> Up\n"
        let before = try QuadrantChartReading.uniformLayout(source)
        XCTAssertLessThan(before.axisLabels[0].text.center.y, 100, "Above before there are points")
        let below = try QuadrantChartReading.uniformLayout("---\nconfig:\n  quadrantChart:\n    xAxisPosition: bottom\n    yAxisPosition: right\n---\n" + source)
        XCTAssertGreaterThan(below.axisLabels[0].text.center.y, 400)
        let right = plot(below)
        XCTAssertEqual(right.minX, 8, "Nothing is kept at the left")
        XCTAssertEqual(below.axisLabels[2].text.center.x, right.maxX + 5 + 21 / 2)
        XCTAssertEqual(right.width, 484 - 26)
    }

    func testANarrowColumnShrinksThePageAndItsHeightWithIt() throws {
        let narrow = try QuadrantChartReading.uniformLayout(body, availableWidth: 300)
        XCTAssertEqual(narrow.size, CGSize(width: 300, height: 300))
        XCTAssertEqual(try QuadrantChartReading.uniformLayout(body, availableWidth: 280).size, CGSize(width: 280, height: 280))
        XCTAssertEqual(try QuadrantChartReading.uniformLayout(body, availableWidth: 100).size, CGSize(width: 280, height: 280), "Not under 280 points")
        XCTAssertEqual(try QuadrantChartReading.uniformLayout(body, availableWidth: 900).size, CGSize(width: 500, height: 500))
        XCTAssertEqual(try QuadrantChartReading.uniformLayout(body, availableWidth: nil), try QuadrantChartReading.uniformLayout(body))
        let own = try layout("chartWidth: 600, chartHeight: 300", availableWidth: 300)
        XCTAssertEqual(own.size, CGSize(width: 300, height: 150), "The height keeps the chart's proportion")
        for laidOut in [narrow, own] {
            let page = CGRect(origin: .zero, size: laidOut.size)
            XCTAssertTrue(page.contains(plot(laidOut)))
            XCTAssertTrue(laidOut.points.allSatisfy { point in page.contains(point.text.frame) })
            XCTAssertTrue(laidOut.axisLabels.allSatisfy { label in page.contains(label.text.frame) || label.isTurned })
        }
    }

    func testAChartPreparedForANarrowColumnHasANarrowSceneOnlyWhenItWouldNotFit() throws {
        let typography = DiagramTypography(font: DiagramFont(postScriptName: nil, size: 16))
        let prepared = try MermaidDiagramPreparation.prepare(source: body, typography: typography)
        XCTAssertEqual(prepared.scene.size, CGSize(width: 500, height: 500))
        XCTAssertEqual(try XCTUnwrap(prepared.narrowScene).size, CGSize(width: 280, height: 280))
        XCTAssertTrue(prepared.showsNarrowScene(inColumnWidth: 360))
        let small = try MermaidDiagramPreparation.prepare(source: "---\nconfig:\n  quadrantChart:\n    chartWidth: 250\n---\n" + body, typography: typography)
        XCTAssertNil(small.narrowScene, "No wider than the narrowest column")
    }
}
