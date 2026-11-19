/**
 * File: GanttOptionsTests.swift
 * -----------------------------
 * Layer: Tests
 * Description: Gantt charts with the options of the front matter and directives, vertical markers, restyled today lines and
 *              clicks, and for a narrow column, as Pele's Gantt renderer draws them.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 19/11/2026
 */

import XCTest
@testable import MermaidDiagrams

/// Pele's Gantt options, with text of uniform width (the title 8 points a character at 16, rows 6 at 13, axis dates 6 at 12:
/// bars 24 points tall, rows 30, the axis 21), in UTC, on 2026-10-23 15:30.
final class GanttOptionsTests: XCTestCase {
    private let accuracy: CGFloat = 0.01

    private func laidOut(_ source: String, availableWidth: CGFloat? = nil) throws -> GanttLayout {
        let chart = try GanttChartReading.ganttChart(source)
        let zone = try GanttScheduling.zone("UTC")
        let moment = try GanttScheduling.now()
        let schedule = try GanttSchedule(chart: chart, now: moment, zone: zone, limits: .standard)
        let measurers = GanttMeasurers(title: UniformWidthTextMeasurer(), row: UniformWidthTextMeasurer(characterWidth: 6, fontSize: 13, lineHeight: 20),
                                       axis: UniformWidthTextMeasurer(characterWidth: 6, fontSize: 12, lineHeight: 18))
        return GanttLayoutEngine.layout(chart, schedule: schedule.entries, now: moment, zone: zone, measurers: measurers, font: UniformWidthLayout.font,
                                        availableWidth: availableWidth)
    }

    private func options(_ written: String) throws -> GanttOptions {
        try GanttChartReading.ganttChart("---\nconfig:\n  gantt:\n    " + written.replacingOccurrences(of: "; ", with: "\n    ") + "\n---\ngantt\nA : a, 2014-01-01, 3d").options
    }

    private func source(_ written: String, tasks: String = "section Section\nA task : a1, 2014-01-01, 30d\nAnother : a2, after a1, 20d") -> String {
        "---\nconfig:\n  gantt:\n    " + written.replacingOccurrences(of: "; ", with: "\n    ") + "\n---\ngantt\ndateFormat YYYY-MM-DD\n" + tasks
    }

    func testTheOptionsAreReadFromBlockFlowAndDirectiveFormsAndCutToTheirRange() throws {
        let read = try options("fontSize: 20; sectionFontSize: 14; barHeight: 30; barGap: 6; numberSectionStyles: 2.6; leftPadding: 50; rightPadding: 40; useWidth: 600; topPadding: 90; gridLineStartPadding: 70; topAxis: true; axisFormat: \"%m/%d\"; tickInterval: 1week")
        XCTAssertEqual([read.fontSize, read.sectionFontSize, read.barHeight, read.barGap], [20, 14, 30, 6])
        XCTAssertEqual(read.sectionStyleCount, 3, "Rounded, as Math.round rounds")
        XCTAssertEqual([read.leftPadding, read.rightPadding, read.useWidth, read.topPadding, read.gridLineStartPadding], [50, 40, 600, 90, 70])
        XCTAssertTrue(read.showsTopAxis)
        XCTAssertEqual(read.axisFormat, "%m/%d")
        XCTAssertEqual(read.tickInterval, "1week")
        let flow = try GanttChartReading.ganttChart("---\nconfig:\n  gantt: {barHeight: 28, useWidth: 700}\n---\ngantt\nA : a, 2014-01-01, 3d").options
        XCTAssertEqual([flow.barHeight, flow.useWidth], [28, 700])
        let directive = try GanttChartReading.ganttChart("%%{init: {'gantt': {'barGap': 2, 'topAxis': true}}}%%\ngantt\nA : a, 2014-01-01, 3d").options
        XCTAssertEqual(directive.barGap, 2)
        XCTAssertTrue(directive.showsTopAxis)
        let cut = try options("fontSize: 1; barHeight: 9000; barGap: -4; leftPadding: 99999; useWidth: 5; numberSectionStyles: 0; topAxis: yes; sectionFontSize: big")
        XCTAssertEqual([cut.fontSize, cut.barHeight, cut.barGap, cut.leftPadding, cut.useWidth], [4, 400, 0, 2_000, 100])
        XCTAssertEqual(cut.sectionStyleCount, 1)
        XCTAssertFalse(cut.showsTopAxis)
        XCTAssertNil(cut.sectionFontSize)
        XCTAssertEqual(try GanttChartReading.ganttChart("gantt\nA : a, 2014-01-01, 3d").options, GanttOptions())
    }

    func testTheBarsHeightAndTheGapBetweenRowsFollowTheOptions() throws {
        let plain = try XCTUnwrap(try laidOut(source("")).plot)
        XCTAssertEqual(plain.frame.height, 60)
        let sized = try XCTUnwrap(try laidOut(source("barHeight: 40; barGap: 5")).plot)
        XCTAssertEqual(sized.frame.height, 90, "Two rows of 45")
        guard case .bar(let bar) = sized.tasks[0].shape else { return XCTFail("A bar") }
        XCTAssertEqual(bar.height, 40)
        XCTAssertEqual(sized.tasks[1].label.center.y - sized.tasks[0].label.center.y, 45, accuracy: accuracy)
        let onlyHeight = try XCTUnwrap(try laidOut(source("barHeight: 40")).plot)
        XCTAssertEqual(onlyHeight.frame.height, 2 * (40 + 10), "The gap is a quarter of the bar's height")
    }

    func testThePaddingsAndTheUsedWidthSetThePlot() throws {
        let plain = try XCTUnwrap(try laidOut(source("")).plot)
        XCTAssertEqual(plain.frame.minX, 74)
        XCTAssertEqual(plain.frame.width, 688)
        let padded = try laidOut(source("leftPadding: 20; rightPadding: 12"))
        let plot = try XCTUnwrap(padded.plot)
        XCTAssertEqual(plot.frame.minX, 28, "The page's padding and the option")
        XCTAssertEqual(plot.frame.width, 800 - 28 - 12 - 8)
        XCTAssertEqual(padded.size.width, 800, accuracy: 1)
        let narrower = try laidOut(source("useWidth: 500"))
        XCTAssertEqual(try XCTUnwrap(narrower.plot).frame.width, 500 - 74 - 30 - 8)
        XCTAssertEqual(narrower.size.width, 500)
        XCTAssertEqual(try laidOut(source("useWidth: 100")).size.width, 74 + 240 + 30 + 8, "The plot is never under 240 points")
    }

    func testANarrowColumnNarrowsThePageAsPeleCapsIt() throws {
        let narrow = try laidOut(source(""), availableWidth: 400)
        XCTAssertEqual(narrow.size.width, 400)
        XCTAssertEqual(try XCTUnwrap(narrow.plot).frame.width, 400 - 74 - 30 - 8)
        XCTAssertEqual(try laidOut(source(""), availableWidth: 900).size.width, 800)
        XCTAssertEqual(try laidOut(source(""), availableWidth: 100).size.width, 74 + 240 + 30 + 8, "Not under 280 points of target, and the plot's own least")
        XCTAssertEqual(try laidOut(source("useWidth: 600"), availableWidth: 500).size.width, 500)
        XCTAssertEqual(try laidOut(source("useWidth: 600"), availableWidth: nil).size.width, 600)
    }

    func testTheSectionStylesAlternateAsManyTimesAsTheOptionSays() throws {
        let tasks = "section A\nx : 2014-01-01, 2d\nsection B\ny : 2014-01-03, 2d\nsection C\nz : 2014-01-05, 2d"
        XCTAssertEqual(try XCTUnwrap(try laidOut(source("", tasks: tasks)).plot).sectionBands.count, 2, "Styles 0 and 2 of four are shaded")
        XCTAssertEqual(try XCTUnwrap(try laidOut(source("numberSectionStyles: 1", tasks: tasks)).plot).sectionBands.count, 3)
        XCTAssertEqual(try XCTUnwrap(try laidOut(source("numberSectionStyles: 2", tasks: tasks)).plot).sectionBands.count, 2)
        XCTAssertEqual(try XCTUnwrap(try laidOut(source("numberSectionStyles: 3", tasks: tasks)).plot).sectionBands.count, 2, "0 and 2")
        XCTAssertEqual(try XCTUnwrap(try laidOut(source("numberSectionStyles: 6", tasks: tasks)).plot).sectionBands.count, 2)
    }

    func testTheTopPaddingAndTheGridLinesStartDecideWhereRowsAndLinesBegin() throws {
        let plain = try XCTUnwrap(try laidOut(source("")).plot)
        XCTAssertEqual(plain.frame.minY, 8)
        XCTAssertEqual(plain.gridTop, 8)
        let padded = try XCTUnwrap(try laidOut(source("topPadding: 100")).plot)
        XCTAssertEqual(padded.frame.minY, 100)
        XCTAssertEqual(padded.gridTop, 100, "Without gridLineStartPadding the lines start at the first row")
        let both = try XCTUnwrap(try laidOut(source("topPadding: 100; gridLineStartPadding: 70")).plot)
        XCTAssertEqual(both.frame.minY, 100)
        XCTAssertEqual(both.gridTop, 70, "Thirty points above the first row")
        let tall = try XCTUnwrap(try laidOut(source("topPadding: 100; gridLineStartPadding: 0")).plot)
        XCTAssertEqual(tall.gridTop, 8, "Only the room above the first row is used")
        XCTAssertEqual(try XCTUnwrap(try laidOut(source("topPadding: 3")).plot).frame.minY, 8, "A smaller padding keeps the room the title and axis take")
        let parts = GanttDrawingParts(layout: try laidOut(source("topPadding: 100; gridLineStartPadding: 70")))
        XCTAssertEqual(parts.gridLines.boundingBoxOfPath.minY, 70)
    }

    func testTheTopAxisIsShownByTheOptionToo() throws {
        let plain = try XCTUnwrap(try laidOut(source("")).plot)
        XCTAssertFalse(plain.showsTopAxis)
        let withAxis = try XCTUnwrap(try laidOut(source("topAxis: true")).plot)
        XCTAssertTrue(withAxis.showsTopAxis)
        XCTAssertEqual(withAxis.frame.minY, plain.frame.minY + 21, "A row of dates over the rows")
        XCTAssertEqual(withAxis.axisDates.count, 2 * plain.axisDates.count)
        XCTAssertEqual(try XCTUnwrap(try laidOut(source("", tasks: "topAxis\nA : a, 2014-01-01, 3d")).plot).showsTopAxis, true, "The chart's own statement too")
    }

    func testTheConfigurationsAxisFormatAndTickIntervalApplyUnlessTheChartSetsItsOwn() throws {
        let configured = try XCTUnwrap(try laidOut(source("axisFormat: \"%m/%d\"")).plot)
        XCTAssertTrue(configured.axisDates.allSatisfy { date in date.lines[0].contains("/") && date.lines[0].count == 5 })
        let own = try XCTUnwrap(try laidOut(source("axisFormat: \"%m/%d\"", tasks: "axisFormat %Y\nA : a, 2014-01-01, 30d")).plot)
        XCTAssertTrue(own.axisDates.allSatisfy { date in date.lines[0] == "2014" || date.lines[0] == "2013" })
        let ticked = try XCTUnwrap(try laidOut(source("tickInterval: 1week", tasks: "A : a, 2014-01-01, 30d")).plot)
        XCTAssertEqual(ticked.gridLineOffsets.count, 4, "A grid line each Sunday, a week apart, over 30 days")
    }

    func testTheTextSizesOfTheOptionsSetTheTasksAndTheSectionsFonts() throws {
        let typography = DiagramTypography(font: DiagramFont(postScriptName: nil, size: 16))
        func layout(_ written: String) throws -> GanttLayout {
            try GanttLayoutEngine.layout(try GanttChartReading.ganttChart(source(written)), typography: typography, now: Date(timeIntervalSince1970: 0),
                                         timeZone: .gmt, limits: .standard)
        }
        let plain = try XCTUnwrap(try layout("").plot)
        XCTAssertEqual(plain.tasks[0].label.fontSize, 13)
        XCTAssertEqual(plain.sectionNames[0].fontSize, 13)
        let sized = try XCTUnwrap(try layout("fontSize: 20").plot)
        XCTAssertEqual(sized.tasks[0].label.fontSize, 20)
        XCTAssertEqual(sized.sectionNames[0].fontSize, 20, "The sections follow the tasks' size")
        guard case .bar(let bar) = sized.tasks[0].shape else { return XCTFail("A bar") }
        XCTAssertEqual(bar.height, 37, "1.85 times the size, rounded")
        let both = try XCTUnwrap(try layout("fontSize: 20; sectionFontSize: 10").plot)
        XCTAssertEqual(both.tasks[0].label.fontSize, 20)
        XCTAssertEqual(both.sectionNames[0].fontSize, 10)
        XCTAssertLessThan(both.frame.minX, sized.frame.minX, "Smaller section names leave less room at the left")
    }

    // MARK: Vertical markers

    private let markers = "section S\nTask A : a, 2014-01-01, 10d\nTask B : b, 2014-01-11, 10d\nRelease : vert, v1, 2014-01-11, 0d\nReview : vert, v2, 2014-01-12, 0d"

    func testAVerticalMarkerTakesNoRowAndIsALineWithItsTextUnderTheAxis() throws {
        let layout = try laidOut(source("", tasks: markers))
        let plot = try XCTUnwrap(layout.plot)
        XCTAssertEqual(plot.tasks.count, 2, "The markers are not rows")
        XCTAssertEqual(plot.frame.height, 60)
        XCTAssertEqual(plot.verticalMarkers.count, 2)
        let release = plot.verticalMarkers[0]
        XCTAssertEqual(release.offset, plot.frame.minX + plot.frame.width * 10 / 20, accuracy: 0.01, "At its start")
        XCTAssertEqual(release.label.lines, ["Release"])
        XCTAssertEqual(release.label.center.x, release.offset, accuracy: accuracy, "Centered on its line")
        // Under the axis' dates (21 points) and 4 more, in a row of 20 points.
        XCTAssertEqual(release.label.center.y, plot.frame.maxY + 21 + 4 + 10, accuracy: accuracy)
        XCTAssertEqual(layout.size.height, (plot.frame.maxY + 21 + 4 + 2 * 20 + 8).rounded(.up), "Two rows of texts: the second marker is too near the first")
    }

    func testTheTextsOfNearMarkersStandOnSeparateRowsAndFarOnesShareOne() throws {
        let plot = try XCTUnwrap(try laidOut(source("", tasks: markers)).plot)
        XCTAssertEqual(plot.verticalMarkers[1].label.center.y - plot.verticalMarkers[0].label.center.y, 20, accuracy: accuracy, "Too near: a row below")
        let far = "section S\nTask A : a, 2014-01-01, 30d\nOne : vert, v1, 2014-01-02, 0d\nTwo : vert, v2, 2014-01-25, 0d"
        let farPlot = try XCTUnwrap(try laidOut(source("", tasks: far)).plot)
        XCTAssertEqual(farPlot.verticalMarkers[0].label.center.y, farPlot.verticalMarkers[1].label.center.y, accuracy: accuracy)
        let order = try XCTUnwrap(try laidOut(source("", tasks: "section S\nA : a, 2014-01-01, 30d\nLate : vert, v1, 2014-01-25, 0d\nEarly : vert, v2, 2014-01-02, 0d")).plot)
        XCTAssertEqual(order.verticalMarkers.map { marker in marker.label.lines[0] }, ["Early", "Late"], "By their start")
    }

    func testAMarkersTextStaysInsideThePagesPaddingAndWidensThePage() throws {
        let plot = try XCTUnwrap(try laidOut("gantt\ndateFormat YYYY-MM-DD\nTask : a, 2014-01-01, 30d\nA very long marker text that is wide : vert, v, 2014-01-30, 0d").plot)
        let label = plot.verticalMarkers[0].label
        XCTAssertGreaterThanOrEqual(label.frame.minX, 8 - accuracy)
        let early = try XCTUnwrap(try laidOut("gantt\ndateFormat YYYY-MM-DD\nTask : a, 2014-01-01, 30d\nA very long marker text that is wide : vert, v, 2014-01-01, 0d").plot)
        XCTAssertEqual(early.verticalMarkers[0].label.frame.minX, 8, accuracy: accuracy, "As far left as the padding lets it")
        let layout = try laidOut("gantt\ndateFormat YYYY-MM-DD\nTask : a, 2014-01-01, 30d\nA very long marker text that is wide : vert, v, 2014-01-30, 0d")
        XCTAssertGreaterThanOrEqual(layout.size.width, (layout.plot?.verticalMarkers[0].label.frame.maxX ?? 0) + 8 - 1)
    }

    func testAChartOfMarkersAloneAndAnUnscheduledMarkerLayOut() throws {
        let only = try laidOut("gantt\ndateFormat YYYY-MM-DD\nA : vert, v1, 2014-01-01, 3d")
        XCTAssertEqual(only.plot?.tasks.count, 0)
        XCTAssertEqual(only.plot?.verticalMarkers.count, 1)
        XCTAssertEqual(only.plot?.frame.height, 30, "A chart without rows keeps the room of one")
        let waiting = try laidOut("gantt\ndateFormat YYYY-MM-DD\nTask : a, 2014-01-01, 3d\nW : vert, w, after nothing, 1d")
        XCTAssertEqual(waiting.plot?.verticalMarkers.count, 1, "A marker after a task that does not exist starts today, as a task does")
    }

    func testTheMarkersAreDrawnAsDashedLinesInTheLineColorWithTheirTextsInTheForeground() throws {
        let layout = try laidOut(source("", tasks: markers))
        let parts = GanttDrawingParts(layout: layout)
        XCTAssertEqual(parts.verticalMarkerLines.boundingBoxOfPath.height, try XCTUnwrap(layout.plot).frame.height, accuracy: accuracy)
        XCTAssertEqual(parts.verticalMarkerTexts.map { block in block.lines[0] }, ["Release", "Review"])
        let scene = DiagramScene(layout: layout)
        let dashed = scene.shapes.first { shape in
            if case .stroke(let paint, let stroke) = shape.painting { return paint == .line && stroke.dashLengths == [4, 3] && stroke.lineWidth == 1.5 }
            return false
        }
        XCTAssertNotNil(dashed)
        XCTAssertTrue(scene.texts.contains { text in text.block.lines == ["Release"] && text.paint == .foreground })
    }

    // MARK: Today's line

    func testAStyledTodayLineTakesItsStyleAndLosesItsTriangle() throws {
        let tasks = "A : a, 2026-10-01, 40d"
        let standard = GanttDrawingParts(layout: try laidOut(source("", tasks: tasks)))
        XCTAssertFalse(standard.todayMark.isEmpty)
        XCTAssertNil(standard.todayLineStyle)
        let styledSource = "gantt\ndateFormat YYYY-MM-DD\ntodayMarker stroke:red,stroke-width:4px,stroke-dasharray:5 3,opacity:0.5\n" + tasks
        let layout = try laidOut(styledSource)
        let styled = GanttDrawingParts(layout: layout)
        XCTAssertTrue(styled.todayMark.isEmpty, "Pele leaves the triangle out of a styled line")
        let style = try XCTUnwrap(styled.todayLineStyle)
        XCTAssertEqual(style.color, DiagramColor(red: 1, green: 0, blue: 0))
        XCTAssertEqual(style.lineWidth, 4)
        XCTAssertEqual(style.dashLengths, [5, 3])
        XCTAssertEqual(style.opacity, 0.5)
        let scene = DiagramScene(layout: layout)
        let line = scene.shapes.first { shape in
            if case .stroke(let paint, let stroke) = shape.painting { return paint == DiagramPaint.color(DiagramColor(red: 1, green: 0, blue: 0)).atOpacity(0.5) && stroke.lineWidth == 4 && stroke.dashLengths == [5, 3] }
            return false
        }
        XCTAssertNotNil(line)
    }

    func testOnlyDeclarationsOfALineStyleItAndTheOthersLeaveTheStandardLine() throws {
        XCTAssertNil(GanttTodayLineStyle(declarations: "fill:red"))
        XCTAssertNil(GanttTodayLineStyle(declarations: "color:red,font-size:20px"))
        XCTAssertNil(GanttTodayLineStyle(declarations: "stroke:url(#x)"), "An unsafe value is no declaration")
        XCTAssertNil(GanttTodayLineStyle(declarations: "stroke:"))
        XCTAssertNotNil(GanttTodayLineStyle(declarations: "rx:3"), "A line property whose value is not applied still makes the line a styled one")
        XCTAssertNotNil(GanttTodayLineStyle(declarations: "fill:red, stroke-linecap:round"))
        XCTAssertEqual(GanttTodayLineStyle(declarations: "stroke-linecap:round,stroke-linejoin:bevel")?.lineCap, .round)
        XCTAssertEqual(GanttTodayLineStyle(declarations: "stroke-linecap:round,stroke-linejoin:bevel")?.lineJoin, .bevel)
        XCTAssertEqual(GanttTodayLineStyle(declarations: "stroke:#00f !important")?.color, DiagramColor(red: 0, green: 0, blue: 1))
        XCTAssertEqual(GanttTodayLineStyle(declarations: "stroke-width:99px")?.lineWidth, 16, "Never wider than 16 points")
        XCTAssertEqual(GanttTodayLineStyle(declarations: "opacity:0.5,stroke-opacity:0.5")?.opacity, 0.25)
        XCTAssertNil(GanttTodayLineStyle(declarations: "stroke-dasharray:0 0")?.dashLengths, "Dashes that add up to nothing are not applied")
    }

    // MARK: Clicks

    func testAClickIsAcceptedMarksItsTasksAndAMalformedOneIsASyntaxError() throws {
        let chart = try GanttChartReading.ganttChart("gantt\ndateFormat YYYY-MM-DD\nA : a, 2014-01-01, 3d\nB : b, 2014-01-02, 3d\nC : c, 2014-01-03, 3d\n"
                                                     + "click a,b href \"https://example.com\" call f(1, 2)\nclick c call g()\nclick missing href \"x\"\nclick b call h(x) href \"https://b.example\"")
        XCTAssertEqual(chart.tasks.map(\.isClickable), [true, true, true])
        XCTAssertEqual(chart.tasks.map(\.link), ["https://example.com", "https://b.example", nil])
        XCTAssertTrue(chart.statementsNotDrawn.isEmpty)
        XCTAssertNotNil(try laidOut("gantt\ndateFormat YYYY-MM-DD\nA : a, 2014-01-01, 3d\nclick a href \"https://example.com\"").plot)
        XCTAssertEqual(GanttChartReading.readError("gantt\nA : a, 2014-01-01, 3d\nclick a"), .invalidSyntax(line: 3, problem: .unexpectedText("")))
        XCTAssertNotNil(GanttChartReading.readError("gantt\nA : a, 2014-01-01, 3d\nclick"))
        XCTAssertNotNil(GanttChartReading.readError("gantt\nA : a, 2014-01-01, 3d\nclick a b c"))
    }

    // MARK: Preparation

    func testAGanttChartIsPreparedForANarrowColumn() throws {
        let typography = DiagramTypography(font: DiagramFont(postScriptName: nil, size: 16))
        let prepared = try MermaidDiagramPreparation.prepare(source: source("", tasks: markers), typography: typography)
        XCTAssertEqual(prepared.scene.size.width, 800, accuracy: 100)
        let narrow = try XCTUnwrap(prepared.narrowScene)
        XCTAssertLessThan(narrow.size.width, prepared.scene.size.width)
        XCTAssertLessThanOrEqual(narrow.size.width, 400)
        XCTAssertNil(try MermaidDiagramPreparation.prepare(source: source("useWidth: 300", tasks: "A : a, 2014-01-01, 3d"), typography: typography).narrowScene,
                     "Its plot is never under 240 points: no narrower scene when its own page is that narrow already")
    }
}
