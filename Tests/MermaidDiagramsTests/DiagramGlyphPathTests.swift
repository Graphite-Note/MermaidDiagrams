/**
 * File: DiagramGlyphPathTests.swift
 * ---------------------------------
 * Layer: Tests
 * Description: SVG path data of glyphs is read as SVG reads it: every command, absolute and relative, numbers without
 *              separators, arcs by their flags, and data SVG refuses refused; a glyph is placed in its frame.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 19/11/2026
 */

import XCTest
@testable import MermaidDiagrams

final class DiagramGlyphPathTests: XCTestCase {
    private func bounds(_ data: String) throws -> CGRect {
        try XCTUnwrap(DiagramGlyphPath(pathData: data)).gridPath.boundingBoxOfPath
    }

    private func assertEqual(_ rectangle: CGRect, _ expected: CGRect, accuracy: CGFloat = 0.01, _ message: String = "", line: UInt = #line) {
        XCTAssertEqual(rectangle.minX, expected.minX, accuracy: accuracy, message, line: line)
        XCTAssertEqual(rectangle.minY, expected.minY, accuracy: accuracy, message, line: line)
        XCTAssertEqual(rectangle.maxX, expected.maxX, accuracy: accuracy, message, line: line)
        XCTAssertEqual(rectangle.maxY, expected.maxY, accuracy: accuracy, message, line: line)
    }

    /// Pele's built-in folder and file glyphs of the tree view fill their 24 by 24 grid as Pele's SVG draws them.
    func testTheTreeViewsFolderAndFileGlyphsAreReadToTheirOutlines() throws {
        assertEqual(try bounds("M3 6.5A1.5 1.5 0 0 1 4.5 5h4.6l2.4 2.5h8A1.5 1.5 0 0 1 21 9v9a1.5 1.5 0 0 1-1.5 1.5h-15A1.5 1.5 0 0 1 3 18z"), CGRect(x: 3, y: 5, width: 18, height: 14.5))
        assertEqual(try bounds("M6.5 3h7L19 8.5v11a1.5 1.5 0 0 1-1.5 1.5h-11A1.5 1.5 0 0 1 5 19.5v-15A1.5 1.5 0 0 1 6.5 3zM13.5 3v5.5H19"), CGRect(x: 5, y: 3, width: 14, height: 18))
    }

    func testRelativeAndAbsoluteCommandsAndRepeatedArgumentsDrawTheSameSquare() throws {
        let absolute = try bounds("M2 2L10 2L10 10L2 10Z")
        assertEqual(absolute, CGRect(x: 2, y: 2, width: 8, height: 8))
        assertEqual(try bounds("m2,2 8,0 0,8 -8,0z"), absolute, "Pairs after a move are lines")
        assertEqual(try bounds("M2 2H10V10H2z"), absolute)
        assertEqual(try bounds("M2 2h8v8h-8z"), absolute)
        assertEqual(try bounds("M2-2l1.5.5"), CGRect(x: 2, y: -2, width: 1.5, height: 0.5), "Numbers end where the next cannot continue them")
        assertEqual(try bounds("M0 0L1e1 0 1E1 1e+1"), CGRect(x: 0, y: 0, width: 10, height: 10))
    }

    func testCurvesAndTheirSmoothContinuationsReflectTheLastControlPoint() throws {
        let cubic = try bounds("M0 0C0 10 10 10 10 0S20 -10 20 0")
        XCTAssertEqual(cubic.minY, -7.5, accuracy: 0.01)
        XCTAssertEqual(cubic.maxY, 7.5, accuracy: 0.01)
        let quadratic = try bounds("M0 0Q5 10 10 0T20 0")
        XCTAssertEqual(quadratic.maxY, 5, accuracy: 0.01)
        XCTAssertEqual(quadratic.minY, -5, accuracy: 0.01)
    }

    /// From (0, 0) to (10, 0) with a radius of 5, the four arcs are the half circles above and below; the flags pick them.
    func testAnArcsFlagsPickWhichOfItsArcsIsDrawn() throws {
        assertEqual(try bounds("M0 0A5 5 0 0 1 10 0"), CGRect(x: 0, y: -5, width: 10, height: 5), "Swept positively, over the top on a page whose y runs down")
        assertEqual(try bounds("M0 0A5 5 0 0 0 10 0"), CGRect(x: 0, y: 0, width: 10, height: 5))
        assertEqual(try bounds("M0 0A10 10 0 1 1 10 0"), CGRect(x: -5, y: -18.66, width: 20, height: 18.66), accuracy: 0.05)
        assertEqual(try bounds("M0 0a10 10 0 0110 0"), try bounds("M0 0A10 10 0 0 1 10 0"), "Flags written without separators")
        assertEqual(try bounds("M0 0A1 1 0 0 1 10 0"), CGRect(x: 0, y: -5, width: 10, height: 5), "Radii too small to reach are scaled up")
        assertEqual(try bounds("M0 0A0 5 0 0 1 10 0"), CGRect(x: 0, y: 0, width: 10, height: 0), "A zero radius is a line")
        let turned = try bounds("M0 0A10 5 90 0 1 0 20")
        XCTAssertEqual(turned.width, 5, accuracy: 0.05, "An ellipse turned a quarter turn is five wide")
    }

    func testDataSVGRefusesIsRefused() {
        for data in ["", "L1 1", "M1", "M1 1 L", "M1 1 X2 2", "M1 1 A1 1 0 2 1 2 2", "M1 1 Z 2 2", "1 1", "M1e999 1"] {
            XCTAssertNil(DiagramGlyphPath(pathData: data), data)
        }
        XCTAssertNil(DiagramGlyphPath(pathData: "M0 0" + String(repeating: " 1 1", count: 3_000)), "More numbers than a glyph holds")
    }

    func testAGlyphIsScaledIntoTheSquareCenteredInItsFrame() throws {
        let glyph = try XCTUnwrap(DiagramGlyphPath(pathData: "M0 0H24V24H0Z"))
        assertEqual(glyph.path(in: CGRect(x: 10, y: 20, width: 16, height: 16)).boundingBoxOfPath, CGRect(x: 10, y: 20, width: 16, height: 16))
        assertEqual(glyph.path(in: CGRect(x: 0, y: 0, width: 40, height: 20)).boundingBoxOfPath, CGRect(x: 10, y: 0, width: 20, height: 20))
    }
}
