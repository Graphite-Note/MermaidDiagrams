/**
 * File: AgentFlowCorpusTests.swift
 * --------------------------------
 * Layer: Tests
 * Description: Reads and lays out Mermaid's 12 agent flow documentation examples, across and turned to run down, and
 *              generated flows: every node on the page, apart from the others, inside the flows that hold it.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 19/11/2026
 */

import XCTest
@testable import MermaidDiagrams
@testable import MermaidDiagramsBenchmark

final class AgentFlowCorpusTests: XCTestCase {
    private let typography = DiagramTypography(font: DiagramFont(postScriptName: nil, size: 16))

    func testDocumentationExamplesAreLaidOutWithNodesApartAndInsideTheirFlows() throws {
        let examples = try AgentFlowCorpus.documentationExamples()
        XCTAssertEqual(examples.count, 12)
        for (index, source) in examples.enumerated() {
            let diagram = try AgentFlowReading.diagram(source)
            XCTAssertFalse(diagram.graph.nodes.isEmpty, source)
            for isTurned in [false, true] {
                let layout = try AgentFlowLayoutEngine.layout(diagram, typography: typography, isTurnedToRunDown: isTurned)
                assertSound(layout, diagram: diagram, source: source)
                PlaneMapPictures.write(DiagramScene(layout: layout), named: "agentflow-docs-\(index)\(isTurned ? "-down" : "")")
            }
        }
    }

    func testGeneratedFlowsAreLaidOutSoundly() throws {
        for (flowCount, nodesPerFlow) in [(6, 8), (12, 10)] {
            let source = AgentFlowCorpus.generated(flowCount: flowCount, nodesPerFlow: nodesPerFlow)
            let diagram = try AgentFlowReading.diagram(source)
            let layout = try AgentFlowLayoutEngine.layout(diagram, typography: typography)
            assertSound(layout, diagram: diagram, source: source)
            PlaneMapPictures.write(DiagramScene(layout: layout), named: "agentflow-generated-\(flowCount)")
        }
    }

    /// Edges to a node's own flow, loops, styles, connectors and flows running across, each laid out soundly.
    func testFeatureSamplesAreLaidOutSoundly() throws {
        let samples = [
            ("held", "agentflow-beta TB\n  flow f[\"Pipeline\"]\n    a[\"Plan\"] --> b[\"Act\"]\n    a --> f\n    f --> b\n  end\n  b --> b"),
            ("styled", "agentflow-beta LR\n  classDef hot fill:#e45756,color:#ffffff\n  flow f[\"Styled\"]\n    a[\"Hot\"]:::hot -- yes --> b[\"Plain\"]\n  end\n"
                + "  style f fill:#eeeeff,stroke:#3333aa\n  b --x c[\"Fail\"]\n  connector api[\"API\"]\n  c -.- api\n  linkStyle 0 stroke:#3333aa,stroke-width:3px"),
            ("across", "agentflow-beta LR\n  flow one[\"One\"]\n    direction TB\n    a --> b\n  end\n  flow two[\"Two\"]\n    c --> d\n  end\n  one --> two"),
        ]
        for (name, source) in samples {
            let diagram = try AgentFlowReading.diagram(source)
            let layout = try AgentFlowLayoutEngine.layout(diagram, typography: typography)
            assertSound(layout, diagram: diagram, source: source)
            PlaneMapPictures.write(DiagramScene(layout: layout), named: "agentflow-\(name)")
        }
    }

    /// Every node and flow on the page; nodes apart from each other; each node and flow inside the flow holding it.
    private func assertSound(_ layout: AgentFlowLayout, diagram: AgentFlowDiagram, source: String, file: StaticString = #filePath, line: UInt = #line) {
        let page = CGRect(origin: .zero, size: layout.size).insetBy(dx: -0.5, dy: -0.5)
        var frames: [String: CGRect] = [:]
        for node in layout.nodes { frames[node.identifier] = node.frame }
        for flow in layout.flows { frames[flow.identifier] = flow.frame }
        for frame in frames.values { XCTAssertTrue(page.contains(frame), "\(frame) off \(layout.size): \(source)", file: file, line: line) }
        for (first, second) in zip(layout.nodes.indices, layout.nodes.indices.dropFirst()) {
            for other in layout.nodes.indices where other > first {
                let overlap = layout.nodes[first].frame.insetBy(dx: 1, dy: 1).intersects(layout.nodes[other].frame.insetBy(dx: 1, dy: 1))
                XCTAssertFalse(overlap, "\(layout.nodes[first].identifier) over \(layout.nodes[other].identifier): \(source)", file: file, line: line)
            }
            _ = second
        }
        for node in diagram.graph.nodes {
            guard let parent = node.parentIdentifier, let parentFrame = frames[parent], let frame = frames[node.identifier] else { continue }
            XCTAssertTrue(parentFrame.insetBy(dx: -0.5, dy: -0.5).contains(frame), "\(node.identifier) outside \(parent): \(source)", file: file, line: line)
        }
        XCTAssertEqual(layout.edges.count, diagram.graph.edges.count, source, file: file, line: line)
    }
}
