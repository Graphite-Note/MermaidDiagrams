/**
 * File: UseCaseCorpusTests.swift
 * ------------------------------
 * Layer: Tests
 * Description: Mermaid's use case documentation examples and generated diagrams are read, laid out with every node
 *              apart and on the page, and turned to run down for a narrow column.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 19/11/2026
 */

import XCTest
@testable import MermaidDiagrams
@testable import MermaidDiagramsBenchmark

final class UseCaseCorpusTests: XCTestCase {
    private let typography = DiagramTypography(font: DiagramFont(postScriptName: nil, size: 16))

    func testEveryDocumentationExampleIsDrawnWithItsNodesApartAndOnThePage() throws {
        let examples = try UseCaseCorpus.documentationExamples()
        XCTAssertEqual(examples.count, 24)
        for (index, example) in examples.enumerated() {
            let diagram = try UseCaseReading.diagram(example)
            for turned in [false, true] {
                guard let drawn = turned ? diagram.turnedToRunDown : diagram else { continue }
                let layout = try UseCaseLayoutEngine.layout(drawn, typography: typography)
                PlaneMapPictures.write(DiagramScene(layout: layout), named: "usecase-documentation-\(index)\(turned ? "-down" : "")")
                let page = CGRect(origin: .zero, size: layout.size)
                for (first, node) in layout.nodes.enumerated() {
                    XCTAssertTrue(page.contains(node.frame), "example \(index): \(node.identifier)")
                    for second in layout.nodes.indices where second > first {
                        XCTAssertFalse(node.frame.intersects(layout.nodes[second].frame), "example \(index): \(node.identifier) and \(layout.nodes[second].identifier)")
                    }
                }
                for boundary in layout.boundaries { XCTAssertTrue(page.contains(boundary.frame), "example \(index): \(boundary.identifier)") }
                XCTAssertEqual(layout.edges.count, diagram.relationships.count + diagram.notes.count, "example \(index)")
            }
        }
    }

    func testTheGeneratedDiagramsAreLaidOutWithTheirMembersInsideTheirBoundaries() throws {
        for (actors, useCases, boundaries, relationships) in [(1, 1, 0, 1), (5, 20, 3, 30), (20, 200, 10, 300)] {
            let diagram = try UseCaseReading.diagram(UseCaseCorpus.generated(actorCount: actors, useCaseCount: useCases, boundaryCount: boundaries,
                                                                            relationshipCount: relationships))
            XCTAssertEqual(diagram.actors.count, actors)
            XCTAssertEqual(diagram.useCases.count, useCases)
            XCTAssertEqual(diagram.systemBoundaries.count, boundaries)
            let layout = try UseCaseLayoutEngine.layout(diagram, typography: typography)
            XCTAssertEqual(layout.edges.count, relationships)
            for boundary in layout.boundaries {
                for member in diagram.boundary(boundary.identifier)?.members ?? [] {
                    XCTAssertTrue(boundary.frame.contains(layout.node(member)?.frame ?? .null), "\(member) in \(boundary.identifier)")
                }
            }
            if useCases == 20 { PlaneMapPictures.write(DiagramScene(layout: layout), named: "usecase-generated-20") }
        }
    }
}
