/**
 * File: DiagramSceneBuilderTests.swift
 * ------------------------------------
 * Layer: Tests
 * Description: A scene leaves out what paints nothing, merges opaque shapes painted alike that are apart in time linear
 *              in their count, paints a fill and the stroke of its path as one shape, keeps apart shapes that touch or are
 *              translucent, and its paints resolve in any palette.
 *
 * Authors: Bahey Shalash
 * Version: 0.2
 * Date: 19/11/2026
 */

import XCTest
@testable import MermaidDiagrams
@testable import MermaidDiagramsBenchmark

final class DiagramSceneBuilderTests: XCTestCase {
    private func square(at x: CGFloat) -> CGPath {
        CGPath(rect: CGRect(x: x, y: 0, width: 10, height: 10), transform: nil)
    }

    func testEmptyPathsAndTextsWithoutLinesAreLeftOut() {
        var builder = DiagramSceneBuilder()
        builder.fill(CGMutablePath(), .surface, part: .node)
        builder.text(nil, .foreground, part: .label)
        XCTAssertTrue(builder.items.isEmpty)
    }

    func testOpaqueShapesPaintedAlikeAndApartAreMergedIntoOne() throws {
        var builder = DiagramSceneBuilder()
        builder.fill(square(at: 0), .surface, part: .node)
        builder.fill(square(at: 100), .surface, part: .node)
        let scene = builder.scene(size: CGSize(width: 110, height: 10), font: DiagramFont(postScriptName: nil, size: 16))
        XCTAssertEqual(scene.shapes.count, 1)
        let merged = try XCTUnwrap(scene.shapes.first)
        XCTAssertEqual(merged.path.boundingBoxOfPath, CGRect(x: 0, y: 0, width: 110, height: 10))
    }

    func testTouchingTranslucentOrDifferentShapesStayApart() {
        var builder = DiagramSceneBuilder()
        builder.fill(square(at: 0), .surface, part: .node)
        builder.fill(square(at: 5), .surface, part: .node)
        builder.fill(square(at: 100), DiagramPaint.surface.atOpacity(0.5), part: .node)
        builder.fill(square(at: 200), DiagramPaint.surface.atOpacity(0.5), part: .node)
        builder.fill(square(at: 300), .surface, part: .cluster)
        builder.fill(square(at: 400), .color(DiagramColor(red: 1, green: 0, blue: 0, alpha: 0.5)), part: .cluster)
        builder.fill(square(at: 500), .color(DiagramColor(red: 1, green: 0, blue: 0, alpha: 0.5)), part: .cluster)
        XCTAssertEqual(builder.items.count, 7)
    }

    func testALongRunOfShapesMergedOneByOneIsJoinedOnceInLinearTime() throws {
        let shapeCount = 40_000
        let squares = (0..<shapeCount).map { index in square(at: CGFloat(index) * 20) }
        let clock = ContinuousClock()
        var builder = DiagramSceneBuilder()
        let elapsed = clock.measure {
            for square in squares { builder.fill(square, .surface, part: .node) }
            _ = builder.items
        }
        let merged = try XCTUnwrap(builder.scene(size: CGSize(width: 800_000, height: 10), font: DiagramFont(postScriptName: nil, size: 16)).shapes.first)
        XCTAssertEqual(builder.items.count, 1)
        XCTAssertEqual(merged.path.boundingBoxOfPath.width, CGFloat(shapeCount - 1) * 20 + 10)
        // Copying the merged path again for each shape took about 5 s for 40,000 squares in a debug build; joining them
        // once takes milliseconds.
        XCTAssertLessThan(elapsed, .seconds(1))
    }

    func testAPathFilledThenStrokedIsOneShapePaintedBothWays() throws {
        let line = DiagramStroke(lineWidth: 1)
        var builder = DiagramSceneBuilder()
        builder.fillAndStroke(square(at: 0), fill: .surface, stroke: .border, line, part: .node)
        builder.fillAndStroke(square(at: 100), fill: .surface, stroke: .border, line, part: .node)
        builder.fill(square(at: 200), .surface, part: .cluster)
        builder.stroke(square(at: 200), .border, line, part: .cluster)
        builder.fill(square(at: 300), .surface, part: .label)
        builder.stroke(square(at: 400), .border, line, part: .label)
        XCTAssertEqual(builder.items.compactMap { item -> DiagramShapePainting? in
            guard case .shape(let shape) = item else { return nil }
            return shape.painting
        }, [.fillAndStroke(.surface, .border, line), .fillAndStroke(.surface, .border, line), .fill(.surface), .stroke(.border, line)],
                       "Two outlined boxes apart are merged; a fill and the stroke of another path stay two")
        var outlinedCount = 0
        var strokedAgainCount = 0
        for sample in try DiagramSceneSamples.all() {
            guard let prepared = try? MermaidDiagramPreparation.prepare(source: sample.source, typography: DiagramSceneSamples.typography,
                                                                        now: GanttChartCorpus.now, timeZone: GanttChartCorpus.timeZone) else { continue }
            let shapes = prepared.scene.shapes
            outlinedCount += shapes.filter { shape in if case .fillAndStroke = shape.painting { true } else { false } }.count
            strokedAgainCount += zip(shapes, shapes.dropFirst()).filter { filled, stroked in
                guard case .fill = filled.painting, case .stroke = stroked.painting else { return false }
                return filled.part == stroked.part && filled.path == stroked.path
            }.count
        }
        XCTAssertEqual(strokedAgainCount, 0, "No sample fills a path and then strokes it as a second shape")
        XCTAssertGreaterThan(outlinedCount, 0)
    }

    func testPaintsResolveToTheirRolesMixturesAndOpacitiesInAPalette() throws {
        let palette = DiagramPalette.peleLight
        XCTAssertEqual(DiagramPaint.border.color(in: palette), palette.border)
        XCTAssertEqual(DiagramPaint.series(9).color(in: palette), palette.seriesColor(at: 1))
        let faint = try XCTUnwrap(DiagramPaint.accent.atOpacity(0.25).color(in: palette).components)
        XCTAssertEqual(faint[3], 0.25, accuracy: 1e-9)
        let note = try XCTUnwrap(DiagramPaint.betweenBackgroundAndForeground(share: DiagramPalette.noteTextShare).color(in: palette).components)
        let expected = try XCTUnwrap(palette.noteText.components)
        for (component, expectedComponent) in zip(note, expected) { XCTAssertEqual(component, expectedComponent, accuracy: 1e-9) }
    }
}
