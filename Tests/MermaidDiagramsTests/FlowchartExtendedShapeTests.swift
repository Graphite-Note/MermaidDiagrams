/**
 * File: FlowchartExtendedShapeTests.swift
 * ---------------------------------------
 * Layer: Tests
 * Description: The flowchart node shapes beyond the classic ones: their sizes, insets, spans and drawings, Pele's.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 19/11/2026
 */

import XCTest
@testable import MermaidDiagrams

final class FlowchartExtendedShapeTests: XCTestCase {
    private let textSize = CGSize(width: 40, height: 24)
    private let frame = CGRect(x: 10, y: 20, width: 120, height: 60)

    func testEachShapeIsSizedAroundItsTextWithPelesNumbers() {
        // Pele's svg/shapes.ts for a text 40 by 24: its box 76 by 48 before each shape's own room.
        let expected: [(FlowchartNodeShape, CGFloat, CGFloat, CGFloat)] = [
            (.ellipse, 88, 52.8, 0), (.dataStore, 76, 48, 0), (.card, 76, 48, 0), (.taggedRectangle, 76, 48, 0),
            (.linedRectangle, 84, 48, 0), (.dividedRectangle, 76, 56, 4), (.windowPane, 84, 56, 4), (.stackedRectangle, 84, 56, 4),
            (.collapsedGroup, 84, 56, -2), (.smallCircle, 14, 14, 0), (.filledCircle, 14, 14, 0), (.framedCircle, 18, 18, 0),
            (.forkJoin, 72, 8, 0), (.hourglass, 32, 40, 0), (.crossedCircle, 44, 44, 0), (.lightningBolt, 36, 56, 0),
            (.slopedRectangle, 76, 58, 5), (.notchedPentagon, 76, 48, 0), (.delay, 88, 48, 0), (.horizontalCylinder, 100, 48, 0),
            (.document, 76, 58, -5), (.taggedDocument, 76, 58, -5), (.linedDocument, 84, 58, -5), (.stackedDocument, 84, 66, -1),
            (.paperTape, 76, 64, 0), (.folder, 76, 56, 4), (.bucket, 96, 58, 3), (.console, 76, 60, 6), (.browser, 76, 60, 6),
            (.person, 76, 74, 13), (.bang, 104, 72, 0), (.cloud, 108, 72, 0), (.leftBrace, 88, 48, 0), (.rightBrace, 88, 48, 0),
            (.braces, 100, 48, 0), (.linedCylinder, 76, 68, 7), (.curvedTrapezoid, 104.8, 48, 0), (.bowTieRectangle, 95.2, 48, 0),
            (.triangle, 104, 34 * 104 / 56, 34 * 104 / 112 - 22), (.flippedTriangle, 104, 34 * 104 / 56, 22 - 34 * 104 / 112),
        ]
        XCTAssertEqual(Set(expected.map(\.0)), Set(FlowchartShapeCatalogue.extendedShapes))
        for (shape, width, height, textOffset) in expected {
            let measured = FlowchartShapeGeometry.size(of: shape, textSize: textSize)
            XCTAssertEqual(measured.size.width, width, accuracy: 0.001, "\(shape)")
            XCTAssertEqual(measured.size.height, height, accuracy: 0.001, "\(shape)")
            XCTAssertEqual(measured.textOffset, textOffset, accuracy: 0.001, "\(shape)")
        }
    }

    func testTheWidestOfTheMinimumWidthsHoldForShortText() {
        let short = CGSize(width: 2, height: 24)
        XCTAssertEqual(FlowchartShapeGeometry.size(of: .folder, textSize: short).size.width, 64)
        XCTAssertEqual(FlowchartShapeGeometry.size(of: .console, textSize: short).size.width, 72)
        XCTAssertEqual(FlowchartShapeGeometry.size(of: .person, textSize: short).size.width, 56)
        XCTAssertEqual(FlowchartShapeGeometry.size(of: .card, textSize: short).size.width, 48)
        XCTAssertEqual(FlowchartShapeGeometry.size(of: .notchedPentagon, textSize: short).size.width, 38, "Pele gives a loop limit no minimum")
        XCTAssertEqual(FlowchartShapeGeometry.size(of: .triangle, textSize: short).size.width, 80)
    }

    func testEdgesMeetEachOutlineWherePeleInsetsIt() {
        let size = CGSize(width: 80, height: 48)
        XCTAssertEqual(FlowchartShapeGeometry.inset(of: .triangle, size: size, side: .left, offset: 0), 20)
        XCTAssertEqual(FlowchartShapeGeometry.inset(of: .triangle, size: size, side: .top, offset: 0), 0)
        XCTAssertEqual(FlowchartShapeGeometry.inset(of: .hourglass, size: size, side: .right, offset: 0), 40)
        XCTAssertEqual(FlowchartShapeGeometry.inset(of: .document, size: size, side: .bottom, offset: 0), 10)
        XCTAssertEqual(FlowchartShapeGeometry.inset(of: .document, size: size, side: .top, offset: 0), 0)
        XCTAssertEqual(FlowchartShapeGeometry.inset(of: .paperTape, size: size, side: .top, offset: 0), 8)
        XCTAssertEqual(FlowchartShapeGeometry.inset(of: .paperTape, size: size, side: .left, offset: 0), 0)
        XCTAssertEqual(FlowchartShapeGeometry.inset(of: .cloud, size: size, side: .left, offset: 0), 2)
        XCTAssertEqual(FlowchartShapeGeometry.inset(of: .cloud, size: size, side: .bottom, offset: 0), 1)
        XCTAssertEqual(FlowchartShapeGeometry.inset(of: .bang, size: size, side: .right, offset: 0), 3)
        XCTAssertEqual(FlowchartShapeGeometry.inset(of: .bucket, size: size, side: .left, offset: 0), 4)
        XCTAssertEqual(FlowchartShapeGeometry.inset(of: .slopedRectangle, size: size, side: .top, offset: 0), 5)
        XCTAssertEqual(FlowchartShapeGeometry.inset(of: .bowTieRectangle, size: size, side: .right, offset: 0), 9.6, accuracy: 0.001)
        XCTAssertEqual(FlowchartShapeGeometry.inset(of: .ellipse, size: size, side: .top, offset: 40), 24, accuracy: 0.001)
        XCTAssertEqual(FlowchartShapeGeometry.inset(of: .person, size: size, side: .top, offset: 0), 0)
    }

    func testEdgesSpreadAlongTheSidesPeleGivesASpan() {
        let size = CGSize(width: 80, height: 48)
        XCTAssertEqual(FlowchartShapeGeometry.span(of: .card, size: size, side: .top), 56)
        XCTAssertEqual(FlowchartShapeGeometry.span(of: .card, size: size, side: .left), 24)
        XCTAssertEqual(FlowchartShapeGeometry.span(of: .forkJoin, size: CGSize(width: 72, height: 8), side: .bottom), 64)
        XCTAssertEqual(FlowchartShapeGeometry.span(of: .forkJoin, size: CGSize(width: 72, height: 8), side: .left), 0)
        XCTAssertEqual(FlowchartShapeGeometry.span(of: .stackedRectangle, size: size, side: .top), 48)
        XCTAssertEqual(FlowchartShapeGeometry.span(of: .ellipse, size: size, side: .top), 48, accuracy: 0.001)
        XCTAssertEqual(FlowchartShapeGeometry.span(of: .linedCylinder, size: CGSize(width: 80, height: 68), side: .right), 24)
        for shape in [FlowchartNodeShape.triangle, .cloud, .person, .document, .bang, .collapsedGroup] {
            XCTAssertEqual(FlowchartShapeGeometry.span(of: shape, size: size, side: .top), 0, "\(shape) keeps its edges at the middle")
        }
    }

    func testEveryShapeIsDrawnWithinItsFrameButTheCloudsArcs() {
        for shape in FlowchartShapeCatalogue.extendedShapes {
            let frame = CGRect(origin: CGPoint(x: 10, y: 20), size: FlowchartShapeGeometry.size(of: shape, textSize: textSize).size)
            // Pele's cloud draws arcs whose radii SVG widens to reach their ends, about 5 points past its box on the left and right (Pele draws it so).
            let reach: CGFloat = shape == .cloud ? 6 : 0.5
            let paths = [FlowchartShapeDrawing.outline(of: shape, in: frame), FlowchartShapeDrawing.innerLines(of: shape, in: frame)].compactMap { path in path }
                + (FlowchartShapeDrawing.layers(of: shape, in: frame) ?? []).map(\.path)
            XCTAssertFalse(paths.isEmpty, "\(shape) draws nothing")
            for path in paths {
                let bounds = path.boundingBoxOfPath
                XCTAssertGreaterThanOrEqual(bounds.minX, frame.minX - reach, "\(shape)")
                XCTAssertLessThanOrEqual(bounds.maxX, frame.maxX + reach, "\(shape)")
                XCTAssertGreaterThanOrEqual(bounds.minY, frame.minY - 0.5, "\(shape)")
                XCTAssertLessThanOrEqual(bounds.maxY, frame.maxY + 0.5, "\(shape)")
            }
        }
    }

    func testEachShapeIsDrawnAsOneOutlineOrPieceByPieceNeverBoth() {
        for shape in FlowchartNodeShape.allCases {
            let layers = FlowchartShapeDrawing.layers(of: shape, in: frame)
            if layers != nil { XCTAssertNil(FlowchartShapeDrawing.outline(of: shape, in: frame), "\(shape)") }
        }
        let layered = Set(FlowchartNodeShape.allCases.filter { shape in FlowchartShapeDrawing.layers(of: shape, in: frame) != nil })
        XCTAssertEqual(layered, [.person, .stackedDocument, .stackedRectangle, .collapsedGroup, .forkJoin, .filledCircle, .framedCircle, .dataStore])
        let linesOnly = Set(FlowchartNodeShape.allCases.filter { shape in
            FlowchartShapeDrawing.outline(of: shape, in: frame) == nil && FlowchartShapeDrawing.layers(of: shape, in: frame) == nil
                && FlowchartShapeDrawing.innerLines(of: shape, in: frame) != nil
        })
        XCTAssertEqual(linesOnly, [.leftBrace, .rightBrace, .braces])
    }

    func testTheOutlinesHoldTheirShapesFeatures() throws {
        let triangle = try XCTUnwrap(FlowchartShapeDrawing.outline(of: .triangle, in: frame))
        XCTAssertTrue(triangle.contains(CGPoint(x: frame.midX, y: frame.minY + 2)))
        XCTAssertFalse(triangle.contains(CGPoint(x: frame.minX + 2, y: frame.minY + 2)))
        let document = try XCTUnwrap(FlowchartShapeDrawing.outline(of: .document, in: frame))
        // The wave rises over the right half of the bottom and falls under the left half.
        XCTAssertFalse(document.contains(CGPoint(x: frame.maxX - 30, y: frame.maxY - 12)))
        XCTAssertTrue(document.contains(CGPoint(x: frame.minX + 30, y: frame.maxY - 8)))
        let delay = try XCTUnwrap(FlowchartShapeDrawing.outline(of: .delay, in: frame))
        XCTAssertTrue(delay.contains(CGPoint(x: frame.minX + 1, y: frame.minY + 1)))
        XCTAssertFalse(delay.contains(CGPoint(x: frame.maxX - 1, y: frame.minY + 1)))
        let hourglass = try XCTUnwrap(FlowchartShapeDrawing.outline(of: .hourglass, in: frame))
        XCTAssertTrue(hourglass.contains(CGPoint(x: frame.midX, y: frame.minY + 4)))
        XCTAssertFalse(hourglass.contains(CGPoint(x: frame.minX + 4, y: frame.midY)))
    }

    func testAShapeWithoutTextLaysOutAtItsFixedSizeWithNoLines() throws {
        let layout = try UniformWidthLayout.layout("flowchart TD\nA@{ shape: fork } --> B@{ shape: cloud, label: \"Sky\" } --> C@{ shape: f-circ }")
        XCTAssertEqual(layout.nodes[0].frame.size, CGSize(width: 72, height: 8))
        XCTAssertTrue(layout.nodes[0].text.lines.isEmpty)
        XCTAssertEqual(layout.nodes[1].text.lines, ["Sky"])
        XCTAssertEqual(layout.nodes[2].frame.size, CGSize(width: 14, height: 14))
        XCTAssertEqual(layout.nodes[1].frame.minY - layout.nodes[0].frame.maxY, 48, accuracy: 0.01)
    }

    func testTheScenePaintsAPieceByPieceShapeInItsOrderAndColors() throws {
        let layout = try UniformWidthLayout.layout("flowchart TD\nA@{ shape: person, label: \"User\" } --> B@{ shape: fork }")
        let paintings = DiagramScene(layout: layout).shapes.filter { shape in shape.part == .node }.map(\.painting)
        let line = DiagramStroke.rounded(lineWidth: 1)
        XCTAssertEqual(paintings, [.fillAndStroke(.surface, .border, line), .fillAndStroke(.surface, .border, line), .fillAndStroke(.line, .border, line)])
    }

    func testAStyledPieceByPieceShapeTakesItsStylesColors() throws {
        let layout = try UniformWidthLayout.layout("flowchart TD\nA@{ shape: docs }\nstyle A fill:#ff0000,stroke:#00ff00")
        let nodeShapes = DiagramScene(layout: layout).shapes.filter { shape in shape.part == .node }
        XCTAssertEqual(nodeShapes.count, 3)
        let line = DiagramStroke.rounded(lineWidth: 1)
        for shape in nodeShapes {
            XCTAssertEqual(shape.painting, .fillAndStroke(.color(DiagramColor(red: 1, green: 0, blue: 0)), .color(DiagramColor(red: 0, green: 1, blue: 0)), line))
        }
    }
}
