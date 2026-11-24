/**
 * File: RadarChartLayoutTests.swift
 * ---------------------------------
 * Layer: Tests
 * Description: Laying out and painting radar charts with Pele's measurements: scaling, splines, labels, the legend, and the examples.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 19/11/2026
 */

import XCTest
@testable import MermaidDiagrams
@testable import MermaidDiagramsBenchmark

final class RadarChartLayoutTests: XCTestCase {
    private let basic = "radar-beta\n  axis A, B, C, D\n  curve one[\"First\"]{1,2,3,4}\n  curve two{4,3,2,1}"

    private func layout(_ source: String) throws -> RadarChartLayout {
        RadarChartLayoutEngine.layout(try SimpleChartReading.radar(source), text: UniformWidthTextMeasurer(characterWidth: 8, fontSize: 16, lineHeight: 24),
                                      smallText: UniformWidthTextMeasurer(characterWidth: 7, fontSize: 14, lineHeight: 21),
                                      boldText: UniformWidthTextMeasurer(characterWidth: 9, fontSize: 16, lineHeight: 24), font: UniformWidthLayout.font)
    }

    func testRelativeRadiusScalesBetweenMinAndMaxAndCutsToThem() {
        func radius(_ value: Double, _ minimum: Double, _ maximum: Double) -> Double { RadarChartGeometry.relativeRadius(of: value, minimum: minimum, maximum: maximum, radius: 100) }
        XCTAssertEqual(radius(5, 0, 10), 50)
        XCTAssertEqual(radius(0, 0, 10), 0)
        XCTAssertEqual(radius(10, 0, 10), 100)
        XCTAssertEqual(radius(-5, 0, 10), 0)
        XCTAssertEqual(radius(15, 0, 10), 100)
        XCTAssertEqual(radius(5, -10, 10), 75)
        XCTAssertFalse(radius(1, 1, 1).isFinite, "A range of nothing has no scale; the layout puts such a point at the center")
    }

    func testSplinesAreClosedCatmullRomCurves() {
        func segments(_ path: CGPath) -> [[CGPoint]] {
            var result: [[CGPoint]] = []
            path.applyWithBlock { element in
                let pointer = element.pointee
                result.append(Array(UnsafeBufferPointer(start: pointer.points, count: { switch pointer.type { case .moveToPoint, .addLineToPoint: 1; case .addQuadCurveToPoint: 2; case .addCurveToPoint: 3; default: 0 } }())))
            }
            return result
        }
        let square = [CGPoint(x: 0, y: 0), CGPoint(x: 100, y: 0), CGPoint(x: 100, y: 100), CGPoint(x: 0, y: 100)]
        // No tension: every control point sits on an end point, a polygon drawn as curves.
        XCTAssertEqual(segments(RadarCurveSpline.closedPath(through: square, tension: 0).coreGraphicsPath)[1], [CGPoint(x: 0, y: 0), CGPoint(x: 100, y: 0), CGPoint(x: 100, y: 0)])
        let round = segments(RadarCurveSpline.closedPath(through: square, tension: 0.5).coreGraphicsPath)
        XCTAssertEqual(round[1], [CGPoint(x: 50, y: -50), CGPoint(x: 50, y: -50), CGPoint(x: 100, y: 0)])
        XCTAssertEqual(round[2], [CGPoint(x: 150, y: 50), CGPoint(x: 150, y: 50), CGPoint(x: 100, y: 100)])
        XCTAssertEqual(round[4], [CGPoint(x: -50, y: 50), CGPoint(x: -50, y: 50), CGPoint(x: 0, y: 0)])
        XCTAssertEqual(round.count, 6, "A move, four curves and the close")
        let two = segments(RadarCurveSpline.closedPath(through: [CGPoint(x: 0, y: 0), CGPoint(x: 100, y: 100)], tension: 0.5).coreGraphicsPath)
        XCTAssertEqual(two[1], [CGPoint(x: 0, y: 0), CGPoint(x: 100, y: 100), CGPoint(x: 100, y: 100)])
        XCTAssertTrue(RadarCurveSpline.closedPath(through: [], tension: 0.5).isEmpty)
    }

    func testAxesStartAtTheTopAndGoClockwise() throws {
        let chart = try layout(basic)
        XCTAssertEqual(chart.axisDirections.count, 4)
        XCTAssertEqual(chart.axisDirections[0].x, 0, accuracy: 1e-12)
        XCTAssertEqual(chart.axisDirections[0].y, -1, accuracy: 1e-12)
        XCTAssertEqual(chart.axisDirections[1].x, 1, accuracy: 1e-12)
        XCTAssertEqual(chart.radius, 160)
        XCTAssertEqual(chart.ringRadii, [32, 64, 96, 128, 160])
        XCTAssertEqual(chart.spokeLength, 160)
    }

    func testValuesAreScaledBetweenMinAndMax() throws {
        func top(_ extra: String) throws -> CGFloat {
            let chart = try layout("radar-beta\n axis A, B, C\n curve c{50, 0, 0}\n graticule polygon" + extra)
            return chart.center.y - chart.curves[0].points[0].y
        }
        XCTAssertEqual(try top(""), 160)
        XCTAssertEqual(try top("\n max 100"), 80)
        XCTAssertEqual(try top("\n max 100\n min 20"), 60)
        XCTAssertEqual(try top("\n max 25"), 160, "A value beyond the range is cut to it")
        XCTAssertEqual(try top("\n min 60\n max 100"), 0)
    }

    func testValuesNearTheLargestDoubleScaleLikeSmallOnes() throws {
        func points(_ values: String) throws -> [CGPoint] { try layout("radar-beta\n axis A, B, C\n curve c{\(values)}\n graticule polygon").curves[0].points }
        let huge = ["1" + String(repeating: "0", count: 308), "5" + String(repeating: "0", count: 307), "25" + String(repeating: "0", count: 306)].joined(separator: ",")
        let expected = try points("4,2,1")
        for (a, b) in zip(try points(huge), expected) {
            XCTAssertEqual(a.x, b.x, accuracy: 1e-9)
            XCTAssertEqual(a.y, b.y, accuracy: 1e-9)
        }
    }

    func testDegenerateChartsAreLaidOutWithFiniteNumbers() throws {
        for source in ["radar-beta", "radar-beta\n axis A, B, C", "radar-beta\n axis A\n curve c{5}", "radar-beta\n curve c{1,2,3}",
                       "radar-beta\n axis A, B\n curve c{1,1}\n min 1\n max 1", "radar-beta\n axis A, B\n curve c{1,2}\n min 9\n max 2", "radar-beta\n axis A, B\n curve c{0,0}",
                       "radar-beta\n axis A, B\n curve c{1,2}\n ticks 0", "radar-beta\n axis A, B\n curve c{1,2}\n ticks 0.3\n graticule polygon",
                       "radar-beta\n axis A, B\n curve c{1,2}\n max " + String(repeating: "9", count: 400), "radar-beta\n axis A, B\n curve c{" + String(repeating: "9", count: 400) + ",2}",
                       "---\nconfig:\n  radar:\n    width: -5\n    height: \"tall\"\n    curveTension: 99\n    marginTop: -1\n---\n" + basic] {
            let chart = try layout(source)
            XCTAssertTrue(chart.size.width.isFinite && chart.size.height.isFinite && chart.size.width > 0, source)
            for curve in chart.curves { for point in curve.points { XCTAssertTrue(point.x.isFinite && point.y.isFinite, source) } }
            let scene = DiagramScene(layout: chart)
            for shape in scene.shapes { XCTAssertTrue(shape.path.boundingBoxOfPath.width.isFinite, source) }
        }
        XCTAssertEqual(try layout("radar-beta\n axis A, B\n curve c{1,2}\n ticks 0.3").ringRadii, [160], "A fraction of a tick is a ring")
        XCTAssertTrue(try layout("radar-beta\n axis A, B\n curve c{1,2}\n ticks 0").ringRadii.isEmpty)
    }

    func testACurveWithoutAValueForEveryAxisIsLeftOutButStaysInTheLegend() throws {
        let chart = try layout("radar-beta\n axis A, B, C\n curve full{1,2,3}\n curve short{1,2}\n curve third{3,2,1}")
        XCTAssertEqual(chart.curves.map(\.seriesIndex), [0, 2], "A drawn curve keeps the color its place among all the curves gives")
        XCTAssertEqual(chart.legend.map(\.seriesIndex), [0, 1, 2])
    }

    func testTheLegendStandsBesideTheChartAndCanBeHidden() throws {
        let shown = try layout(basic)
        let hidden = try layout(basic + "\n showLegend false")
        XCTAssertTrue(hidden.legend.isEmpty)
        XCTAssertLessThan(hidden.size.width, shown.size.width)
        let swatch = shown.legend[0].swatch
        XCTAssertEqual(swatch.size, CGSize(width: 12, height: 12))
        XCTAssertEqual(shown.legend[1].swatch.minY - swatch.minY, 26)
        XCTAssertEqual(shown.legend[0].text.center.x - shown.legend[0].text.size.width / 2, swatch.maxX + 8, accuracy: 1e-9)
        XCTAssertGreaterThan(swatch.minX, shown.center.x + 160 + 24, "At least 24 points right of the chart and its labels")
    }

    func testLabelsHangOffTheirSpokesAwayFromTheCenter() throws {
        let chart = try layout("radar-beta\n axis a[\"Top\"], b[\"Right label\"], c[\"Bottom\"], d[\"Left label\"]\n showLegend false")
        let distance: CGFloat = 160 * 1.05 + 6
        let top = chart.axisLabels[0], right = chart.axisLabels[1], bottom = chart.axisLabels[2], left = chart.axisLabels[3]
        XCTAssertEqual(top.center.x, chart.center.x, accuracy: 1e-9)
        XCTAssertEqual(top.center.y, chart.center.y - distance - 21 / 2 + 0, accuracy: 1e-9)
        XCTAssertEqual(right.center.x, chart.center.x + distance + right.size.width / 2, accuracy: 1e-9)
        XCTAssertEqual(bottom.center.y, chart.center.y + distance + 21 / 2, accuracy: 1e-9)
        XCTAssertEqual(left.center.x, chart.center.x - distance - left.size.width / 2, accuracy: 1e-9)
        XCTAssertGreaterThan(chart.size.width, 320 + 2 * 11 * 7 - 5, "The page holds the long labels")
        for label in chart.axisLabels { XCTAssertTrue(CGRect(origin: .zero, size: chart.size).contains(label.frame)) }
    }

    func testWidthHeightMarginsAndFactorsMoveTheChart() throws {
        let base = try layout(basic + "\n showLegend false")
        let large = try layout("---\nconfig:\n  radar:\n    width: 600\n    height: 600\n---\n" + basic + "\n showLegend false")
        XCTAssertGreaterThanOrEqual(large.size.width - base.size.width, 280)
        XCTAssertLessThan(large.size.width - base.size.width, 300)
        let roomy = try layout("---\nconfig:\n  radar:\n    marginTop: 100\n    marginLeft: 120\n---\n" + basic + "\n showLegend false")
        XCTAssertGreaterThan(roomy.size.height, base.size.height)
        XCTAssertGreaterThan(roomy.size.width, base.size.width)
        XCTAssertEqual(try layout("---\nconfig:\n  radar:\n    axisScaleFactor: 0.5\n---\n" + basic).spokeLength, 80)
        XCTAssertGreaterThan(try layout("---\nconfig:\n  radar:\n    axisLabelFactor: 1.5\n---\n" + basic).size.height, base.size.height)
    }

    func testTheTitleIsAboveEverythingAndCentered() throws {
        let chart = try layout("---\ntitle: From front matter\n---\n" + basic)
        XCTAssertEqual(chart.title?.center.x ?? 0, chart.size.width / 2, accuracy: 1e-9)
        XCTAssertEqual(chart.title?.center.y ?? 0, 8 + 12, accuracy: 1e-9)
        XCTAssertGreaterThan(chart.title?.frame.maxY ?? 99, 0)
        XCTAssertLessThan(chart.title?.frame.maxY ?? 99, chart.axisLabels[0].frame.minY)
    }

    func testTheSceneIsTheTitleGraticuleSpokesCurvesLabelsAndLegendInPelesPaints() throws {
        let scene = DiagramScene(layout: RadarChartLayoutEngine.layout(try SimpleChartReading.radar("radar-beta\ntitle T\n" + String(basic.dropFirst("radar-beta".count))),
                                                                       typography: SimpleChartReading.typography))
        XCTAssertEqual(scene.texts[0].part, .title)
        XCTAssertEqual(scene.items.count, scene.texts.count + scene.shapes.count)
        XCTAssertEqual(scene.shapes.map(\.part), [.graticule, .axis, .curve, .curve, .legend, .legend])
        XCTAssertEqual(scene.shapes[0].painting, .stroke(.alternateSurface, DiagramStroke(lineWidth: 1)))
        XCTAssertEqual(scene.shapes[1].painting, .stroke(.border, DiagramStroke(lineWidth: 1)))
        XCTAssertEqual(scene.shapes[2].painting, .fillAndStroke(DiagramPaint.series(0).atOpacity(0.2), .series(0), DiagramStroke(lineWidth: 1.5, lineJoin: .round)))
        XCTAssertEqual(scene.shapes[5].painting, .fillAndStroke(DiagramPaint.series(1).atOpacity(0.4), .series(1), DiagramStroke(lineWidth: 1)))
        XCTAssertEqual(scene.texts.map(\.part), [.title, .axisLabel, .axisLabel, .axisLabel, .axisLabel, .legend, .legend])
        let polygons = DiagramScene(layout: try layout(basic + "\n graticule polygon\n ticks 3"))
        XCTAssertEqual(polygons.shapes[0].path.boundingBoxOfPath.width, 2 * 160, accuracy: 1e-9)
    }

    func testTheDocumentationExamplesAreLaidOutInsideTheirPages() throws {
        let examples = try RadarChartCorpus.documentationExamples()
        XCTAssertEqual(examples.count, 3)
        for example in examples + [RadarChartCorpus.generated(axisCount: 12, curveCount: 5)] {
            let chart = RadarChartLayoutEngine.layout(try SimpleChartReading.radar(example), typography: SimpleChartReading.typography)
            XCTAssertFalse(chart.curves.isEmpty, example)
            let page = CGRect(origin: .zero, size: chart.size)
            for label in chart.axisLabels { XCTAssertTrue(page.contains(label.frame), example) }
            for entry in chart.legend { XCTAssertTrue(page.contains(entry.swatch) && page.contains(entry.text.frame), example) }
            let scene = DiagramScene(layout: chart)
            XCTAssertTrue(page.insetBy(dx: -2, dy: -2).contains(scene.shapes.map { shape in shape.path.boundingBoxOfPath }.reduce(CGRect.null) { $0.union($1) }), example)
        }
    }

    func testTheAccessibilityValueNamesEachCurveWithItsValuesOnTheAxes() throws {
        let prepared = try MermaidDiagramPreparation.prepare(source: "radar-beta\ntitle T\naxis m[\"Math\"], s[\"Science\"]\ncurve a[\"Alice\"]{85, 90}\ncurve b{1}", typography: SimpleChartReading.typography)
        XCTAssertEqual(prepared.kind, .radar)
        XCTAssertEqual(prepared.accessibility.label, "T")
        XCTAssertEqual(prepared.accessibility.value, "Alice: Math 85, Science 90; b")
    }
}
