/**
 * File: FlowchartPeleParityTests.swift
 * ------------------------------------
 * Layer: Tests
 * Description: Flowchart statements read as Pele's parser and database read them, found by comparing the package with
 *              Pele on Mermaid's flowchart specs: a style naming a node into being, and a rectangle with a property.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 19/11/2026
 */

import XCTest
@testable import MermaidDiagrams

final class FlowchartPeleParityTests: XCTestCase {
    /// flow-style.spec.js: `style Q background:#fff` alone makes Q, as Pele's style statement calls `addVertex`.
    func testAStyleNamesANodeIntoBeingWhereItIsWritten() throws {
        let diagram = try FlowchartReading.flowchart("graph TD;\nAA-->BB;\nstyle A fill:#f00;\nC")
        XCTAssertEqual(diagram.nodes.map(\.identifier), ["AA", "BB", "A", "C"])
        XCTAssertEqual(diagram.nodes[2].style, DiagramElementStyle(fill: DiagramColor(red: 1, green: 0, blue: 0)))
        XCTAssertEqual(diagram.unappliedStatementCount, 0)
    }

    /// Pele's parser lists no member for a style statement, so a node a style makes inside a group is not in the group;
    /// and a group's own identifier makes no node.
    func testAStyleInsideAGroupAndAStyleOfAGroupMakeNoMembersOrNodes() throws {
        let diagram = try FlowchartReading.flowchart("flowchart TD\nsubgraph one\nA\nstyle B fill:#0f0\nend\nstyle one fill:#00f")
        XCTAssertEqual(diagram.nodes.map(\.identifier), ["A", "B"])
        XCTAssertEqual(diagram.subgraphs.first?.nodeIndices, [0])
    }

    /// flow-text.spec.js: `B[|borders:lt|This node has a graph as text]` is a rectangle whose text follows the property.
    func testARectangleWithAPropertyKeepsTheTextAfterIt() throws {
        let diagram = try FlowchartReading.flowchart("graph TD;A_graph_node-->B[|borders:lt|This node has a graph as text];")
        XCTAssertEqual(diagram.nodes[1].label, DiagramLabel("This node has a graph as text"))
        XCTAssertEqual(diagram.nodes[1].shape, .rectangle)
    }

    /// Written without its `name:value|`, it is refused, as Pele's parser expects those tokens.
    func testARectangleWithAPropertyWrittenOtherwiseIsRefused() {
        XCTAssertEqual(FlowchartReading.readError("flowchart TD\nA[|borders|text]"), .invalidSyntax(line: 2, problem: .unexpectedText("|text]")))
        XCTAssertNotNil(FlowchartReading.readError("flowchart TD\nA[|a:b"))
    }
}
