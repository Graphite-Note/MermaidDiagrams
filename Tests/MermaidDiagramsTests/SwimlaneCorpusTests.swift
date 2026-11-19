/**
 * File: SwimlaneCorpusTests.swift
 * -------------------------------
 * Layer: Tests
 * Description: Mermaid's swimlane documentation examples and generated processes read, laid out with every node inside
 *              its lane and apart from the others, and prepared with a narrow scene where they are wider than a column.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 19/11/2026
 */

import XCTest
@testable import MermaidDiagrams
@testable import MermaidDiagramsBenchmark

final class SwimlaneCorpusTests: XCTestCase {
    private let typography = DiagramTypography(font: DiagramFont(postScriptName: nil, size: 16))

    static func read(_ source: String) throws -> FlowchartDiagram {
        guard case .swimlane(let diagram) = try MermaidDiagramReader.read(source, limits: .standard) else { throw MermaidDiagramReadError.noDiagram }
        return diagram
    }

    func testEveryDocumentationExampleIsReadAndLaidOutInItsLanes() throws {
        let examples = try SwimlaneCorpus.documentationExamples()
        XCTAssertEqual(examples.count, 13)
        for (index, example) in examples.enumerated() {
            let diagram = try Self.read(example)
            let layout = SwimlaneLayoutEngine.layout(diagram, typography: typography)
            XCTAssertEqual(layout.lanes.count, diagram.subgraphs.count, example)
            Self.assertNodesInLanesAndApart(layout)
            PlaneMapPictures.write(DiagramScene(layout: layout), named: "swimlane-documentation-\(index)")
        }
    }

    func testGeneratedProcessesInEveryDirectionAreLaidOutInTheirLanes() throws {
        for direction in ["LR", "TB", "RL", "BT"] {
            let diagram = try Self.read(SwimlaneCorpus.process(laneCount: 4, stepCount: 16, direction: direction))
            let layout = SwimlaneLayoutEngine.layout(diagram, typography: typography)
            XCTAssertEqual(layout.lanes.count, 5, "the four lanes and the lane of the loose start")
            Self.assertNodesInLanesAndApart(layout)
            PlaneMapPictures.write(DiagramScene(layout: layout), named: "swimlane-generated-\(direction)")
        }
    }

    func testAnExampleWiderThanTheColumnIsPreparedWithANarrowerScene() throws {
        var narrowCount = 0
        for (index, example) in try SwimlaneCorpus.documentationExamples().enumerated() {
            let prepared = try MermaidDiagramPreparation.prepare(source: example, typography: typography)
            XCTAssertEqual(prepared.kind, .swimlane)
            guard let narrow = prepared.narrowScene else { continue }
            XCTAssertLessThan(narrow.size.width, prepared.scene.size.width)
            narrowCount += 1
            PlaneMapPictures.write(narrow, named: "swimlane-documentation-\(index)-narrow")
        }
        XCTAssertGreaterThan(narrowCount, 6)
    }

    /// Every node is inside one lane's frame, past its title band, and no two nodes overlap.
    static func assertNodesInLanesAndApart(_ layout: SwimlaneLayout, file: StaticString = #filePath, line: UInt = #line) {
        let nodes = layout.flowchart.nodes.map(\.frame)
        for node in nodes {
            let lanes = layout.lanes.filter { lane in lane.frame.insetBy(dx: -0.01, dy: -0.01).contains(node) }
            XCTAssertEqual(lanes.count, 1, "\(node) in one lane", file: file, line: line)
            if let lane = lanes.first { XCTAssertFalse(lane.titleBand.insetBy(dx: 0.01, dy: 0.01).intersects(node), "\(node) past its title", file: file, line: line) }
        }
        for (index, node) in nodes.enumerated() {
            for other in nodes[(index + 1)...] {
                XCTAssertFalse(node.insetBy(dx: 0.5, dy: 0.5).intersects(other.insetBy(dx: 0.5, dy: 0.5)), "\(node) and \(other)", file: file, line: line)
            }
        }
        let page = CGRect(origin: .zero, size: layout.size).insetBy(dx: -0.01, dy: -0.01)
        for lane in layout.lanes { XCTAssertTrue(page.contains(lane.frame), "\(lane.frame) on \(layout.size)", file: file, line: line) }
    }
}
