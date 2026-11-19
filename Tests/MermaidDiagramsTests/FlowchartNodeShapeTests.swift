/**
 * File: FlowchartNodeShapeTests.swift
 * -----------------------------------
 * Layer: Tests
 * Description: The flowchart node shapes and the names Mermaid gives them.
 *
 * Authors: Félix Chevalier, Bahey Shalash
 * Version: 0.2
 * Date: 19/11/2026
 */

import XCTest
@testable import MermaidDiagrams

final class FlowchartNodeShapeTests: XCTestCase {
    func testEveryMermaidNameNamesItsOwnShape() {
        for shape in FlowchartNodeShape.allCases {
            for name in shape.mermaidNames {
                XCTAssertEqual(FlowchartNodeShape(shapeName: name), shape, name)
            }
        }
    }

    func testNoNameIsGivenToTwoShapes() {
        let names = FlowchartNodeShape.allCases.flatMap(\.mermaidNames)
        XCTAssertEqual(Set(names).count, names.count)
    }

    func testShapeNamesAreMatchedAsPeleWritesThem() {
        XCTAssertEqual(FlowchartNodeShape(shapeName: "squareRect"), .rectangle)
        XCTAssertEqual(FlowchartNodeShape(shapeName: "stateStart"), .smallCircle)
        XCTAssertEqual(FlowchartNodeShape(shapeName: "doublecircle"), .doubleCircle)
        XCTAssertNil(FlowchartNodeShape(shapeName: "DIAM"))
        XCTAssertNil(FlowchartNodeShape(shapeName: "doubleCircle"))
    }

    func testEveryShapeOfPelesCatalogueHasACase() {
        XCTAssertEqual(FlowchartNodeShape(shapeName: "cloud"), .cloud)
        XCTAssertEqual(FlowchartNodeShape(shapeName: "paper-tape"), .paperTape)
        XCTAssertEqual(FlowchartNodeShape(shapeName: "collate"), .hourglass)
        XCTAssertNil(FlowchartNodeShape(shapeName: ""))
        // Pele's catalogue lists 53 documented shapes; an ellipse is written in brackets and a collapsed group made by `view: collapsed`.
        XCTAssertEqual(FlowchartNodeShape.documentedNames.count, 53)
        XCTAssertEqual(FlowchartNodeShape.allCases.count, 55)
        XCTAssertEqual(Set(FlowchartNodeShape.allCases.filter { shape in shape.mermaidNames.isEmpty }), [.ellipse, .collapsedGroup])
    }

    func testOnlyTheFixedShapesHoldNoText() {
        let withoutText = Set(FlowchartNodeShape.allCases.filter { shape in !shape.holdsText })
        XCTAssertEqual(withoutText, [.smallCircle, .framedCircle, .forkJoin, .hourglass, .lightningBolt, .filledCircle, .crossedCircle])
    }
}
