/**
 * File: FlowchartShapeDrawingTests.swift
 * --------------------------------------
 * Layer: Tests
 * Description: The outlines and inner lines of the classic flowchart node shapes.
 *
 * Authors: Félix Chevalier, Bahey Shalash
 * Version: 0.2
 * Date: 19/11/2026
 */

import XCTest
@testable import MermaidDiagrams

final class FlowchartShapeDrawingTests: XCTestCase {
    private let frame = CGRect(x: 10, y: 20, width: 120, height: 60)

    func testEveryClassicOutlineFillsItsFrameAndBareTextHasNone() throws {
        for shape in FlowchartShapeCatalogue.classicShapes {
            guard let outline = FlowchartShapeDrawing.outline(of: shape, in: frame) else {
                XCTAssertEqual(shape, .text)
                continue
            }
            let bounds = outline.boundingBoxOfPath
            XCTAssertEqual(bounds.minX, frame.minX, accuracy: 0.5, "\(shape)")
            XCTAssertEqual(bounds.maxX, frame.maxX, accuracy: 0.5, "\(shape)")
            XCTAssertEqual(bounds.minY, frame.minY, accuracy: 0.5, "\(shape)")
            XCTAssertEqual(bounds.maxY, frame.maxY, accuracy: 0.5, "\(shape)")
            XCTAssertTrue(outline.contains(CGPoint(x: frame.midX, y: frame.midY)), "\(shape)")
        }
    }

    func testTheDiamondsCornersAreTheMiddlesOfItsFramesSides() throws {
        let outline = try XCTUnwrap(FlowchartShapeDrawing.outline(of: .diamond, in: frame))
        XCTAssertFalse(outline.contains(CGPoint(x: frame.minX + 2, y: frame.minY + 2)))
        XCTAssertTrue(outline.contains(CGPoint(x: frame.minX + 4, y: frame.midY)))
    }

    func testOnlyASubroutineACylinderAndADoubleCircleOfTheClassicShapesHaveInnerLines() {
        let withInnerLines = FlowchartShapeCatalogue.classicShapes.filter { shape in FlowchartShapeDrawing.innerLines(of: shape, in: frame) != nil }
        XCTAssertEqual(Set(withInnerLines), [.subroutine, .cylinder, .doubleCircle])
    }
}
