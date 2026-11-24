/**
 * File: FlowchartDiagramFacadeTests.swift
 * ---------------------------------------
 * Layer: Tests
 * Description: FlowchartDiagram over its flat model: the accessors read what the arrays made from the model hold, a
 *              flowchart made from arrays reads them back, and turning or retitling its groups changes only them.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 24/11/2026
 */

import XCTest
@testable import MermaidDiagrams
@testable import MermaidDiagramsBenchmark

final class FlowchartDiagramFacadeTests: XCTestCase {
    private func flowcharts() throws -> [FlowchartDiagram] {
        try (FlowchartCorpus.documentationExamples() + PeleResults.sources(ofCorpus: "swimlane-docs")).compactMap { source in
            switch try? MermaidDiagramReader.read(source, limits: .standard) {
            case .flowchart(let diagram)?, .swimlane(let diagram)?: diagram
            default: nil
            }
        }
    }

    /// Every accessor gives what the made arrays hold, for every documentation example.
    func testAccessorsReadWhatTheArraysHold() throws {
        let diagrams = try flowcharts()
        XCTAssertGreaterThan(diagrams.count, 100)
        for diagram in diagrams {
            let nodes = diagram.nodes
            let edges = diagram.edges
            let subgraphs = diagram.subgraphs
            XCTAssertEqual([diagram.nodeCount, diagram.edgeCount, diagram.subgraphCount], [nodes.count, edges.count, subgraphs.count])
            for (index, node) in nodes.enumerated() {
                XCTAssertEqual(diagram.node(at: index), node)
                XCTAssertEqual(diagram.nodeShape(at: index), node.shape)
                XCTAssertEqual(diagram.nodeLabel(at: index), node.label)
                XCTAssertEqual(diagram.nodeLabel(at: index).isReadWithoutMarkup, node.label.isReadWithoutMarkup)
                XCTAssertEqual(diagram.nodeStyle(at: index), node.style)
                XCTAssertEqual(diagram.nodeAsset(at: index), node.asset)
            }
            for (index, edge) in edges.enumerated() {
                XCTAssertEqual(diagram.edge(at: index), edge)
                let drawing = diagram.edgeDrawing(at: index)
                XCTAssertEqual([drawing.sourceIndex, drawing.targetIndex, drawing.minimumRankSpan], [edge.sourceIndex, edge.targetIndex, edge.minimumRankSpan])
                XCTAssertEqual(drawing.style, edge.style)
                XCTAssertEqual(diagram.edgeLabel(at: index), edge.label)
            }
            for (index, subgraph) in subgraphs.enumerated() { XCTAssertEqual(diagram.subgraph(at: index), subgraph) }
            XCTAssertEqual(diagram.hasCollapsedSubgraph, subgraphs.contains(where: \.isCollapsed))
        }
    }

    /// A flowchart made from the arrays of another is equal to it.
    func testAFlowchartMadeFromArraysReadsThemBack() throws {
        for diagram in try flowcharts() {
            let made = FlowchartDiagram(direction: diagram.direction, nodes: diagram.nodes, edges: diagram.edges, subgraphs: diagram.subgraphs,
                                        title: diagram.title, accessibilityTitle: diagram.accessibilityTitle,
                                        accessibilityDescription: diagram.accessibilityDescription,
                                        unappliedStatementCount: diagram.unappliedStatementCount)
            XCTAssertEqual(made, diagram)
            var renamed = diagram
            renamed.nodes = diagram.nodes
            XCTAssertEqual(renamed, diagram)
        }
    }

    /// Turning a flowchart to run down turns its groups' directions, and retitling its groups changes their titles only.
    func testTurningAndRetitlingChangeOnlyTheGroups() throws {
        let diagram = try FlowchartReading.flowchart("flowchart LR\nsubgraph a [A]\ndirection RL\nx --> y\nend\nsubgraph b\nz\nend\na --> b")
        let turned = try XCTUnwrap(diagram.turnedToRunDown)
        XCTAssertEqual(turned.direction, .topToBottom)
        XCTAssertEqual(turned.subgraphs.map(\.direction), [.bottomToTop, nil])
        XCTAssertEqual(turned.nodes, diagram.nodes)
        let retitled = diagram.retitlingSubgraphs([DiagramLabel("First"), DiagramLabel("Second")])
        XCTAssertEqual(retitled.subgraphs.map(\.title), [DiagramLabel("First"), DiagramLabel("Second")])
        XCTAssertEqual(retitled.subgraphs.map(\.nodeIndices), diagram.subgraphs.map(\.nodeIndices))
        XCTAssertEqual(retitled.edges, diagram.edges)
    }
}
