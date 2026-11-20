/**
 * File: UseCaseGraphTests.swift
 * -----------------------------
 * Layer: Tests
 * Description: A read use case diagram becomes the nodes and edges Pele draws, as its port of Mermaid's getData
 *              contract (usecase.spec.ts, usecaseDb.spec.ts) checks them: shapes, paddings, classes, compiled styles,
 *              marks, dashes, labels and JSON rows.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 19/11/2026
 */

import XCTest
@testable import MermaidDiagrams

final class UseCaseGraphTests: XCTestCase {
    private func graph(_ lines: String...) throws -> UseCaseGraph {
        UseCaseGraph(try UseCaseReading.diagram((["usecase-beta"] + lines).joined(separator: "\n")))
    }

    func testNodesComeInPelesOrderWithMermaidsShapesAndPaddings() throws {
        let graph = try graph("actor Normal", "actor Hollow@{ type: hollow, business: true }", "actor Awesome@{ type: awesome }",
                              "actor Icon@{ icon: \"fa:user\" }", "Business(Business)@{ business: true }", "Ellipse", "RectCase[Rectangle]",
                              "note for Ellipse \"n\"", "json Data@{}", "systemBoundary S", "Inside", "end")
        XCTAssertEqual(graph.nodes.map(\.identifier), ["Normal", "Hollow", "Awesome", "Icon", "Business", "Ellipse", "RectCase", "Inside", "note-0", "Data", "S"])
        XCTAssertEqual(graph.nodes.map(\.shape.rawValue), ["usecaseActor", "usecaseActorHollow", "usecaseActorAwesome", "usecaseActorIcon",
                                                            "usecaseBusiness", "usecaseEllipse", "rect", "usecaseEllipse", "note", "usecaseJsonTable",
                                                            "usecaseSystemBoundary"])
        XCTAssertEqual(graph.nodes.map(\.padding), [10, 10, 10, 10, 20, 20, 10, 20, 10, 10, 20])
        XCTAssertEqual(graph.nodes[1].classNames, "default usecase-actor usecase-actor-hollow usecase-business")
        XCTAssertEqual(graph.nodes[6].classNames, "default usecase-element usecase-rect")
        XCTAssertEqual(graph.nodes[8].classNames, "default usecase-note")
        XCTAssertEqual(graph.nodes[9].classNames, "default usecase-json-table")
        XCTAssertEqual(graph.nodes[10].classNames, "default system-boundary system-boundary-rect")
        XCTAssertEqual(graph.nodes[7].parentIdentifier, "S")
    }

    /// A later class wins a property but keeps the place the property first took; `default` applies to everything.
    func testClassStylesAreCompiledInPelesOrderBeforeTheElementsOwn() throws {
        let graph = try graph("classDef default fill: white, stroke: black", "classDef first fill: red, color: blue",
                              "classDef second stroke: green, fill: yellow", "actor Normal:::first,second", "style Normal fill:pink", "Plain")
        XCTAssertEqual(graph.nodes[0].styles, ["fill: yellow", "stroke: green", "color: blue", "fill:pink"])
        XCTAssertEqual(graph.nodes[0].classNames, "default usecase-actor usecase-actor-normal first second")
        XCTAssertEqual(graph.nodes[1].styles, ["fill: white", "stroke: black"])
    }

    func testEdgesTakeTheirMarksDashesLabelsAndClasses() throws {
        let graph = try graph("A --> B", "A <-- B", "A -- B", "A --o B", "A --x B", "A o-- B", "A x-- B", "A i@..> : include B", "A ..> : extend B",
                              "B --|> A", "note for A \"n\"", "A slow@--> B", "slow@{ animation: slow }", "classDef c stroke:blue", "class slow c",
                              "A on@--> B", "on@{ animate: true }")
        XCTAssertEqual(graph.edges.map(\.startMarker.rawValue), ["none", "arrow_point", "none", "none", "none", "arrow_circle", "arrow_cross", "none", "none",
                                                                 "none", "none", "none", "none"])
        XCTAssertEqual(graph.edges.map(\.endMarker.rawValue), ["arrow_point", "none", "none", "arrow_circle", "arrow_cross", "none", "none", "arrow_point",
                                                               "arrow_point", "extension", "arrow_point", "arrow_point", "none"])
        XCTAssertEqual(graph.edges.map(\.identifier).suffix(3), ["slow", "on", "note-0-edge"])
        XCTAssertEqual(graph.edges[7].label, "include")
        XCTAssertTrue(graph.edges[7].isDotted)
        XCTAssertTrue(graph.edges[7].isSemantic)
        XCTAssertEqual(graph.edges[10].classNames, "default relationship relationship-association c edge-animation-slow")
        XCTAssertEqual(graph.edges[10].styles, ["stroke:blue"])
        XCTAssertEqual(graph.edges[11].classNames, "default relationship relationship-association edge-animation-fast")
        XCTAssertTrue(graph.edges[11].isAnimated)
        XCTAssertTrue(graph.edges[12].isNoteConnector)
        XCTAssertEqual(graph.edges[12].start, "note-0")
        XCTAssertEqual(graph.edges[12].end, "A")
        XCTAssertEqual(graph.edges[12].classNames, "default relationship relationship-note")
    }

    func testJSONTablesFlattenToTheirRows() throws {
        let graph = try graph("classDef data fill:#eef,stroke:#369", "json Payload@{", "  \"2\": \"second\",", "  \"1\": \"first\",",
                              "  \"colors\": [\"Red\", \"Green\"],", "  \"items\": [{ \"name\": \"A\" }, {}],", "  \"empty\": {},",
                              "  \"duplicate\": \"old\",", "  \"duplicate\": \"new\"", "}:::data", "style Payload stroke-width:4px")
        let node = try XCTUnwrap(graph.nodes.first)
        XCTAssertEqual(node.classNames, "default usecase-json-table data")
        XCTAssertEqual(node.styles, ["fill:#eef", "stroke:#369", "stroke-width:4px"])
        XCTAssertEqual(node.jsonRows, [UseCaseJSONRow(key: "2", accessibleKey: "2", value: "second"),
                                       UseCaseJSONRow(key: "1", accessibleKey: "1", value: "first"),
                                       UseCaseJSONRow(key: "colors", accessibleKey: "colors", value: "Red"),
                                       UseCaseJSONRow(key: "", accessibleKey: "colors", value: "Green"),
                                       UseCaseJSONRow(key: "items[0].name", accessibleKey: "items[0].name", value: "A"),
                                       UseCaseJSONRow(key: "items[1]", accessibleKey: "items[1]", value: "{}"),
                                       UseCaseJSONRow(key: "empty", accessibleKey: "empty", value: "{}"),
                                       UseCaseJSONRow(key: "duplicate", accessibleKey: "duplicate", value: "new")])
    }
}
