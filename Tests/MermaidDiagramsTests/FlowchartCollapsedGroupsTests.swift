/**
 * File: FlowchartCollapsedGroupsTests.swift
 * -----------------------------------------
 * Layer: Tests
 * Description: Collapsed flowchart groups drawn as single nodes, their content left out and their edges redirected.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 19/11/2026
 */

import XCTest
@testable import MermaidDiagrams

final class FlowchartCollapsedGroupsTests: XCTestCase {
    private func collapsed(_ source: String) throws -> FlowchartDiagram {
        FlowchartCollapsedGroups.collapsing(try FlowchartReading.flowchart(source))
    }

    func testTheDocumentationsCollapsedGroupIsOneNodeBetweenItsEdges() throws {
        // Mermaid's documentation example, as the benchmark's corpus holds it.
        let source = "flowchart TD\n    Start --> one\n    subgraph one [My Group]\n        A --> B\n        B --> C\n    end\n    one --> End\n    one@{ view: collapsed }\n"
        let diagram = try collapsed(source)
        XCTAssertEqual(diagram.nodes.map(\.identifier), ["one", "Start", "End"])
        XCTAssertEqual(diagram.nodes[0].shape, .collapsedGroup)
        XCTAssertEqual(diagram.nodes[0].label, DiagramLabel("My Group"))
        XCTAssertTrue(diagram.subgraphs.isEmpty)
        XCTAssertEqual(diagram.edges.map { edge in [edge.sourceIndex, edge.targetIndex] }, [[1, 0], [0, 2]])
        let layout = try UniformWidthLayout.layout(source)
        XCTAssertEqual(layout.nodes.map(\.shape), [.collapsedGroup, .rectangle, .rectangle])
        XCTAssertTrue(layout.clusters.isEmpty)
        XCTAssertEqual(layout.edges.count, 2)
        // Pele's collapsedGroup: the title's box widened by 8 and heightened by 8.
        let title = layout.nodes[0].text.size
        XCTAssertEqual(layout.nodes[0].frame.size.width, title.width + 44, accuracy: 0.001)
        XCTAssertEqual(layout.nodes[0].frame.size.height, title.height + 32, accuracy: 0.001)
    }

    func testEdgesOutOfTheGroupMeetItsNodeAndThoseInsideItAreLeftOut() throws {
        let diagram = try collapsed("flowchart LR\nX --> A\nsubgraph one\nA --> B\nB --> one\nend\nB --> Y\none --> one\none@{ view: collapsed }")
        XCTAssertEqual(diagram.nodes.map(\.identifier), ["one", "X", "Y"])
        // X --> A and B --> Y meet the group's node; A --> B and B --> one fold onto it and are left out; one --> one stays a loop.
        XCTAssertEqual(diagram.edges.map { edge in [edge.sourceIndex, edge.targetIndex] }, [[1, 0], [0, 2], [0, 0]])
    }

    func testTheOutermostCollapsedGroupStandsForTheGroupsInsideIt() throws {
        let source = "flowchart TD\nsubgraph outer\nsubgraph inner\nA --> B\nend\nC\nend\nA --> D\ninner --> D\nouter@{ view: collapsed }\ninner@{ view: collapsed }"
        let diagram = try collapsed(source)
        XCTAssertEqual(diagram.nodes.map(\.identifier), ["outer", "D"])
        XCTAssertEqual(diagram.edges.map { edge in [edge.sourceIndex, edge.targetIndex] }, [[0, 1], [0, 1]])
        XCTAssertTrue(diagram.subgraphs.isEmpty)
    }

    func testACollapsedGroupInsideAnOpenOneIsANodeInItsBox() throws {
        let source = "flowchart TD\nsubgraph outer\nsubgraph inner [Folded]\nA --> B\nend\nC --> inner\nend\ninner@{ view: collapsed }"
        let diagram = try collapsed(source)
        XCTAssertEqual(diagram.nodes.map(\.identifier), ["inner", "C"])
        XCTAssertEqual(diagram.subgraphs.map(\.identifier), ["outer"])
        XCTAssertEqual(Set(diagram.subgraphs[0].nodeIndices), [0, 1])
        XCTAssertTrue(diagram.subgraphs[0].childSubgraphIndices.isEmpty)
        let layout = try UniformWidthLayout.layout(source)
        XCTAssertEqual(layout.clusters.count, 1)
        for node in layout.nodes { XCTAssertTrue(layout.clusters[0].frame.contains(node.frame)) }
        XCTAssertEqual(layout.nodes[0].shape, .collapsedGroup)
    }

    func testTheGroupsNodeTakesTheStyleItsIdentifierSets() throws {
        let layout = try UniformWidthLayout.layout("flowchart TD\nsubgraph one\nA\nend\none@{ view: collapsed }\nstyle one fill:#ff0000")
        XCTAssertEqual(layout.nodes[0].style?.fill, DiagramColor(red: 1, green: 0, blue: 0))
        let pieces = DiagramScene(layout: layout).shapes.filter { shape in shape.part == .node }
        XCTAssertEqual(pieces.count, 2, "The box behind and the box in front")
    }

    func testAFlowchartWithoutCollapsedGroupsIsUnchanged() throws {
        let diagram = try FlowchartReading.flowchart("flowchart TD\nsubgraph one\nA --> B\nend\nB --> C")
        XCTAssertEqual(FlowchartCollapsedGroups.collapsing(diagram), diagram)
    }
}
