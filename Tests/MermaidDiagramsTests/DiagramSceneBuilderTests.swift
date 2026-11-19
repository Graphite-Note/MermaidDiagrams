/**
 * File: DiagramSceneBuilderTests.swift
 * ------------------------------------
 * Layer: Tests
 * Description: A scene leaves out what paints nothing, merges opaque shapes painted alike that are apart, and keeps
 *              apart shapes that touch or are translucent, and its paints resolve in any palette.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 19/11/2026
 */

import XCTest
@testable import MermaidDiagrams

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
