/**
 * File: XYChartOptionsTests.swift
 * -------------------------------
 * Layer: Tests
 * Description: The XY chart options of the front matter and directives, and the narrow column's page, as Pele's XY
 *              renderer applies them.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 19/11/2026
 */

import XCTest
@testable import MermaidDiagrams

/// XY charts laid out with text of fixed widths: the title 8 points a character, the axes and legend 7, point labels 6.
final class XYChartOptionsTests: XCTestCase {
    private let text = XYChartText(titleText: UniformWidthTextMeasurer(), smallText: UniformWidthTextMeasurer(characterWidth: 7, fontSize: 14, lineHeight: 21),
                                   tinyText: UniformWidthTextMeasurer(characterWidth: 6, fontSize: 12, lineHeight: 18))
    private let body = "xychart\ntitle \"Sales\"\nx-axis Month [jan, feb, mar]\ny-axis Revenue 0 --> 100\nbar Revenue [30, 60, 90]\nline Trend [20, 50, 70]"

    private func chart(_ options: String, body: String? = nil) throws -> XYChart {
        let written = options.isEmpty ? "" : "---\nconfig:\n  xyChart:\n    " + options.replacingOccurrences(of: ", ", with: "\n    ") + "\n---\n"
        return try XYChartReading.chart(written + (body ?? self.body))
    }

    private func laidOut(_ options: String, body: String? = nil, availableWidth: CGFloat? = nil) throws -> XYChartLayout {
        try XYChartLayoutEngine.layout(try chart(options, body: body), text: text, font: DiagramFont(postScriptName: nil, size: 16), availableWidth: availableWidth)
    }

    func testOptionsAreReadFromBlockFlowNestedAndDirectiveForms() throws {
        let block = try chart("width: 500, height: 300, chartOrientation: horizontal, showDataLabel: true, showLegend: false").options
        XCTAssertEqual(block.width, 500)
        XCTAssertEqual(block.height, 300)
        XCTAssertEqual(block.orientation, .horizontal)
        XCTAssertTrue(block.showsDataLabels)
        XCTAssertFalse(block.showsLegend)
        XCTAssertTrue(block.showsTitle)
        let nested = try XYChartReading.chart("---\nconfig:\n  xyChart:\n    xAxis:\n      showLabel: false\n      showTick: false\n    yAxis:\n      showAxisLine: false\n      showTitle: false\n---\n" + body).options
        XCTAssertFalse(nested.xAxis.showsLabels)
        XCTAssertFalse(nested.xAxis.showsTicks)
        XCTAssertTrue(nested.xAxis.showsTitle)
        XCTAssertFalse(nested.yAxis.showsAxisLine)
        XCTAssertFalse(nested.yAxis.showsTitle)
        XCTAssertTrue(nested.yAxis.showsLabels)
        let flow = try XYChartReading.chart("---\nconfig:\n  xyChart: {width: 400, xAxis: {showTitle: false}, showTitle: false}\n---\n" + body).options
        XCTAssertEqual(flow.width, 400)
        XCTAssertFalse(flow.xAxis.showsTitle)
        XCTAssertFalse(flow.showsTitle)
        let directive = try XYChartReading.chart("%%{init: {'xyChart': {'height': 320, 'yAxis': {'showLabel': false}}}}%%\n" + body).options
        XCTAssertEqual(directive.height, 320)
        XCTAssertFalse(directive.yAxis.showsLabels)
        XCTAssertEqual(try XYChartReading.chart(body).options, XYChartOptions())
    }

    func testSizesAreRoundedAndKeptFromAHundredToFourThousandAndOtherValuesAreLeftAtTheirDefaults() throws {
        let options = try chart("width: 99999, height: 40.6, showTitle: yes, showLegend: 1, chartOrientation: sideways").options
        XCTAssertEqual(options.width, 4_000)
        XCTAssertEqual(options.height, 100)
        XCTAssertTrue(options.showsTitle)
        XCTAssertTrue(options.showsLegend)
        XCTAssertEqual(options.orientation, .vertical)
        XCTAssertNil(try chart("width: 0, height: -3").options.width)
        XCTAssertEqual(try chart("height: 333.4").options.height, 333)
    }

    func testTheChartsOwnSizeIsThePage() throws {
        XCTAssertEqual(try laidOut("width: 500, height: 300").size, CGSize(width: 500, height: 300))
        XCTAssertEqual(try laidOut("").size, CGSize(width: 700, height: 500))
    }

    func testTheOptionsOrientationApplyesWhenTheTextWritesNoneAndTheTextsOverridesIt() throws {
        XCTAssertEqual(try chart("chartOrientation: horizontal").orientation, .horizontal)
        XCTAssertEqual(try chart("chartOrientation: horizontal", body: "xychart vertical\nbar [1, 2]").orientation, .vertical)
        XCTAssertEqual(try chart("", body: "xychart horizontal\nbar [1, 2]").orientation, .horizontal)
        let horizontal = try laidOut("chartOrientation: horizontal")
        XCTAssertEqual(horizontal.plotFrame.height / horizontal.plotFrame.width < 1, true)
        XCTAssertTrue(horizontal.axisLabels.contains { label in label.lines == ["jan"] && label.center.x < horizontal.plotFrame.minX }, "The categories stand on the left")
    }

    func testTitleLegendAndAxisTitlesCanBeHidden() throws {
        let shown = try laidOut("")
        XCTAssertNotNil(shown.title)
        XCTAssertEqual(shown.legend.count, 2)
        XCTAssertNotNil(shown.leftAxisTitle)
        XCTAssertNotNil(shown.bottomAxisTitle)
        let hidden = try laidOut("showTitle: false, showLegend: false")
        XCTAssertNil(hidden.title)
        XCTAssertTrue(hidden.legend.isEmpty)
        XCTAssertGreaterThan(hidden.plotFrame.width, shown.plotFrame.width, "The legend's room goes to the plot")
        XCTAssertLessThan(hidden.plotFrame.minY, shown.plotFrame.minY, "So does the title's")
        let axes = try XYChartReading.chart("---\nconfig:\n  xyChart:\n    xAxis:\n      showTitle: false\n    yAxis:\n      showTitle: false\n---\n" + body)
        let untitled = try XYChartLayoutEngine.layout(axes, text: text, font: DiagramFont(postScriptName: nil, size: 16))
        XCTAssertNil(untitled.leftAxisTitle)
        XCTAssertNil(untitled.bottomAxisTitle)
        XCTAssertGreaterThan(untitled.plotFrame.height, shown.plotFrame.height)
    }

    func testAnAxisWithoutLabelsTicksOrLineDrawsNoneAndKeepsNoRoomForThem() throws {
        let plain = try laidOut("")
        let source = "---\nconfig:\n  xyChart:\n    xAxis:\n      showLabel: false\n      showTick: false\n      showAxisLine: false\n    yAxis:\n      showLabel: false\n      showTick: false\n---\n" + body
        let bare = try XYChartLayoutEngine.layout(try XYChartReading.chart(source), text: text, font: DiagramFont(postScriptName: nil, size: 16))
        XCTAssertTrue(bare.axisLabels.isEmpty)
        XCTAssertEqual(bare.axisLines.count, 1, "Only the left axis' line is left")
        XCTAssertEqual(bare.axisLines.first?.start.x, bare.plotFrame.minX)
        XCTAssertGreaterThan(plain.axisLines.count, 4)
        XCTAssertLessThan(bare.plotFrame.minX, plain.plotFrame.minX, "No room for the labels and ticks at the left")
        XCTAssertGreaterThan(bare.plotFrame.height, plain.plotFrame.height, "No room for them below")
        XCTAssertEqual(bare.gridLines.count, plain.gridLines.count, "The grid stays")
    }

    func testBarValuesStandPastTheBarsEndsWhereTheyFit() throws {
        let layout = try laidOut("showDataLabel: true", body: "xychart\nx-axis [a, b, c]\ny-axis -50 --> 100\nbar [30, 60, -10]")
        XCTAssertEqual(layout.barValues.map { block in block.lines.joined() }, ["30", "60", "-10"])
        XCTAssertEqual(layout.bars.count, 3)
        for (bar, value) in zip(layout.bars, layout.barValues) {
            XCTAssertEqual(value.center.x, bar.frame.midX, accuracy: 0.001)
        }
        XCTAssertEqual(layout.barValues[0].center.y, layout.bars[0].frame.minY - (18 / 2 + 2), accuracy: 0.001, "Above a bar that runs up")
        XCTAssertEqual(layout.barValues[2].center.y, layout.bars[2].frame.maxY + (18 / 2 + 2), accuracy: 0.001, "Below one that runs down")
        let without = try laidOut("", body: "xychart\nx-axis [a, b, c]\ny-axis -50 --> 100\nbar [30, 60, -10]")
        XCTAssertTrue(without.barValues.isEmpty)
        XCTAssertEqual(layout.plotFrame.minY, 8 + 18 + 4, "A line of value text and its gap over the plot")
        XCTAssertEqual(without.plotFrame.minY, 8 + 10.5, "Half a line for the top mark's label without them")
        let narrow = try laidOut("showDataLabel: true, width: 100", body: "xychart\nx-axis [a, b, c, d, e, f, g, h]\nbar [3000000, 6000000, 1, 2, 3, 4, 5, 6]")
        XCTAssertLessThan(narrow.barValues.count, 8, "A value wider than its bar's place is left out")
        let horizontal = try laidOut("showDataLabel: true", body: "xychart horizontal\nx-axis [a, b]\nbar [30, 60]")
        XCTAssertEqual(horizontal.barValues.map { block in block.lines.joined() }, ["30", "60"])
        for (bar, value) in zip(horizontal.bars, horizontal.barValues) {
            XCTAssertEqual(value.frame.minX, bar.frame.maxX + 6, accuracy: 0.001, "Six points past the bar's end")
            XCTAssertEqual(value.center.y, bar.frame.midY, accuracy: 0.001)
            XCTAssertLessThan(value.frame.maxX, horizontal.plotFrame.maxX + 100)
        }
        XCTAssertTrue(CGRect(origin: .zero, size: horizontal.size).contains(horizontal.barValues[1].frame), "Room is kept at the right for the values")
    }

    func testANarrowColumnCapsTheWidthAndScalesTheHeightButNotUnderSixTenths() throws {
        let narrow = try laidOut("", availableWidth: 490)
        XCTAssertEqual(narrow.size, CGSize(width: 490, height: 350), "0.7 of the width, 0.7 of the height")
        XCTAssertEqual(try laidOut("", availableWidth: 350).size, CGSize(width: 350, height: 300), "Half the width, but six tenths of the height")
        let least = try laidOut("", availableWidth: 100)
        XCTAssertEqual(least.size.width, 240)
        XCTAssertEqual(least.size.height, 300, "The height keeps at least six tenths: 500 by 0.6")
        XCTAssertEqual(try laidOut("", availableWidth: 900).size, CGSize(width: 700, height: 500))
        XCTAssertEqual(try laidOut("", availableWidth: nil), try laidOut(""))
        XCTAssertEqual(try laidOut("width: 400, height: 200", availableWidth: 300).size, CGSize(width: 300, height: 150))
        for layout in [narrow, least] {
            let page = CGRect(origin: .zero, size: layout.size)
            XCTAssertTrue(page.contains(layout.plotFrame))
            XCTAssertTrue(layout.axisLabels.allSatisfy { label in page.contains(label.frame) })
            XCTAssertTrue(layout.legend.allSatisfy { entry in page.contains(entry.text.frame) })
        }
    }

    func testAChartPreparedForANarrowColumnHasANarrowSceneOnlyWhenItWouldNotFit() throws {
        let typography = DiagramTypography(font: DiagramFont(postScriptName: nil, size: 16))
        let prepared = try MermaidDiagramPreparation.prepare(source: body, typography: typography)
        XCTAssertEqual(prepared.scene.size, CGSize(width: 700, height: 500))
        XCTAssertEqual(try XCTUnwrap(prepared.narrowScene).size, CGSize(width: 280, height: 300), "The column's 280 points, and 0.6 of the height")
        let small = try MermaidDiagramPreparation.prepare(source: "---\nconfig:\n  xyChart:\n    width: 250\n---\n" + body, typography: typography)
        XCTAssertNil(small.narrowScene, "No wider than the narrowest column")
    }
}
