/**
 * File: FlowchartShapeSyntaxTests.swift
 * -------------------------------------
 * Layer: Tests
 * Description: Reading a flowchart node's shape by name and the ellipse's brackets, with the inputs of Pele's
 *              tests/compat/flowchart/flow-node-data.spec.js that name shapes.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 19/11/2026
 */

import XCTest
@testable import MermaidDiagrams

final class FlowchartShapeSyntaxTests: XCTestCase {
    private func shapes(_ source: String) throws -> [FlowchartNodeShape] {
        try FlowchartReading.flowchart(source).nodes.map(\.shape)
    }

    func testEveryDocumentedNameReadsAsItsShape() throws {
        for (shape, names) in FlowchartNodeShape.documentedNames {
            for name in names where name == name.lowercased() && !name.contains("_") {
                XCTAssertEqual(try shapes("flowchart TB\nA@{ shape: \(name) }"), [shape], name)
            }
        }
    }

    func testAnUnknownShapeIsRefusedOnItsLine() {
        XCTAssertEqual(FlowchartReading.readError("flowchart TB\n      A@{ shape: this-shape-does-not-exist }\n      "),
                       .invalidSyntax(line: 2, problem: .unknownShape("this-shape-does-not-exist")))
    }

    func testAShapeNameWithACapitalOrAnUnderscoreIsRefused() {
        XCTAssertEqual(FlowchartReading.readError("flowchart TB\n      A@{ shape: rect_left_inv_arrow }\n      "),
                       .invalidSyntax(line: 2, problem: .shapeNameNotLowercase("rect_left_inv_arrow")))
        XCTAssertEqual(FlowchartReading.readError("flowchart TB\nA@{ shape: squareRect }"),
                       .invalidSyntax(line: 2, problem: .shapeNameNotLowercase("squareRect")))
        XCTAssertEqual(FlowchartReading.readError("flowchart TB\nA@{ shape: collapsedGroup }"),
                       .invalidSyntax(line: 2, problem: .shapeNameNotLowercase("collapsedGroup")))
    }

    func testAnUndocumentedShapeMermaidAcceptsIsARectangle() throws {
        XCTAssertEqual(try shapes("flowchart TB\nA@{ shape: state }\nB@{ shape: choice }\nC@{ shape: note }"), [.rectangle, .rectangle, .rectangle])
    }

    func testAQuotedOrEmptyShapeName() throws {
        XCTAssertEqual(try shapes("flowchart TB\nA@{ shape: \"cloud\" }"), [.cloud])
        XCTAssertEqual(try shapes("flowchart TB\nA(text)\nA@{ shape: }"), [.roundedRectangle], "An empty name changes nothing")
    }

    func testAnEllipseIsWrittenBetweenParenthesesAndHyphens() throws {
        let diagram = try FlowchartReading.flowchart("flowchart LR\nA(-An ellipse-) --> B(-Closed by a slash/)")
        XCTAssertEqual(diagram.nodes.map(\.shape), [.ellipse, .ellipse])
        XCTAssertEqual(diagram.nodes[0].label, DiagramLabel("An ellipse"))
        XCTAssertEqual(diagram.nodes[1].label, DiagramLabel("Closed by a slash"))
        XCTAssertEqual(FlowchartReading.readError("flowchart LR\nA(-1)"), .invalidSyntax(line: 2, problem: .unclosedShape(closingText: "-)")))
    }

    // tests/compat/flowchart/flow-node-data.spec.js: the shape data statements.
    func testBasicShapeDataStatements() throws {
        XCTAssertEqual(try shapes("flowchart TB\n      D@{ shape: rounded}"), [.roundedRectangle])
        XCTAssertEqual(try shapes("flowchart TB\n      D@{ shape: rounded }"), [.roundedRectangle])
        XCTAssertEqual(try shapes("flowchart TB\n      D@{shape: rounded}"), [.roundedRectangle])
        XCTAssertEqual(try shapes("flowchart TB\n      D@{       shape: rounded}"), [.roundedRectangle])
        XCTAssertEqual(try shapes("flowchart TB\n      D@{ shape: rounded         }"), [.roundedRectangle])
    }

    func testShapeDataWithAmpersandsAndEdges() throws {
        XCTAssertEqual(try shapes("flowchart TB\n      D@{ shape: rounded } & E"), [.roundedRectangle, .rectangle])
        XCTAssertEqual(try shapes("flowchart TB\n      D@{ shape: rounded } --> E"), [.roundedRectangle, .rectangle])
        XCTAssertEqual(try shapes("flowchart TB\n      D@{ shape: rounded } & E --> F"), [.roundedRectangle, .rectangle, .rectangle])
        XCTAssertEqual(try shapes("flowchart TB\n      D@{ shape: rounded } & E@{ shape: rounded } --> F"), [.roundedRectangle, .roundedRectangle, .rectangle])
        XCTAssertEqual(try shapes("flowchart TB\n      D@{ shape: rounded } & E@{ shape: rounded } --> F & G@{ shape: rounded }"),
                       [.roundedRectangle, .roundedRectangle, .rectangle, .roundedRectangle])
        XCTAssertEqual(try shapes("flowchart TB\n      D@{ shape: rounded } & E@{ shape: rounded } --> F@{ shape: rounded } & G@{ shape: rounded }"),
                       [.roundedRectangle, .roundedRectangle, .roundedRectangle, .roundedRectangle])
        let trailing = try FlowchartReading.flowchart(
            "flowchart TB\n         D@{ shape: rounded } & E@{ shape: rounded } --> F{ shape: rounded } & G{ shape: rounded }    ")
        XCTAssertEqual(trailing.nodes[0].shape, .roundedRectangle)
        XCTAssertEqual(trailing.nodes[2].shape, .diamond, "Without @ the braces are a diamond around the text")
    }

    func testShapeDataWithALabel() throws {
        let diagram = try FlowchartReading.flowchart("flowchart TB\n      D@{ shape: rounded , label: \"DD\"}")
        XCTAssertEqual(diagram.nodes.map(\.shape), [.roundedRectangle])
        XCTAssertEqual(diagram.nodes[0].label, DiagramLabel("DD"))
    }

    func testALinkToANodeWithMoreData() throws {
        let diagram = try FlowchartReading.flowchart("flowchart TB\n      A --> D@{\n        shape: circle\n        other: \"clock\"\n     }\n\n      ")
        XCTAssertEqual(diagram.nodes.map(\.shape), [.rectangle, .circle])
        XCTAssertEqual(diagram.nodes.map(\.label), [DiagramLabel("A"), DiagramLabel("D")])
        XCTAssertEqual(diagram.edges.count, 1)
    }

    func testNodesWithDataOneAfterTheOther() throws {
        let diagram = try FlowchartReading.flowchart(
            "flowchart TB\n      A[hello]\n      B@{\n        shape: circle\n        other: \"clock\"\n     }\n      C[Hello]@{\n        shape: circle\n        other: \"clock\"\n     }\n      ")
        XCTAssertEqual(diagram.nodes.map(\.shape), [.rectangle, .circle, .circle])
        XCTAssertEqual(diagram.nodes.map(\.label), [DiagramLabel("hello"), DiagramLabel("B"), DiagramLabel("Hello")])
    }

    func testDiamondShapesWorkAsUsual() throws {
        let diagram = try FlowchartReading.flowchart("flowchart TB\n      A{This is a label}\n")
        XCTAssertEqual(diagram.nodes.map(\.shape), [.diamond])
        XCTAssertEqual(diagram.nodes[0].label, DiagramLabel("This is a label"))
    }
}
