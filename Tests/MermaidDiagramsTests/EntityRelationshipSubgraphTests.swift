/**
 * File: EntityRelationshipSubgraphTests.swift
 * -------------------------------------------
 * Layer: Tests
 * Description: Entity relationship groups read as Mermaid's database keeps them and drawn as Pele's nested boxes.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 19/11/2026
 */

import XCTest
@testable import MermaidDiagrams

final class EntityRelationshipSubgraphTests: XCTestCase {
    private let accuracy: CGFloat = 0.01

    private func layout(_ source: String) throws -> EntityRelationshipLayout {
        try EntityRelationshipUniformLayout.layout(source, limits: .standard)
    }

    /// Mermaid's documentation example of nested groups, as the benchmark's corpus holds it.
    private let nested = "erDiagram\n    subgraph title1\n        CUSTOMER\n        CUSTOMER {\n            string name\n        }\n    end\n"
        + "    subgraph title2\n        CAR ||--o{ NAMED-DRIVER : allows\n        subgraph title3\n            PERSON\n        end\n    end\n"

    func testAGroupHoldsTheNamesItsStatementsWriteAndTheGroupsEndingInsideIt() throws {
        let diagram = try EntityRelationshipReading.diagram(nested)
        // Groups in the order they end: title1, title3, title2.
        XCTAssertEqual(diagram.subgraphs.map(\.identifier), ["title1", "title3", "title2"])
        let names = diagram.entities.map(\.identifier)
        XCTAssertEqual(diagram.subgraphs[0].entityIndices.map { names[$0] }, ["CUSTOMER"])
        XCTAssertEqual(diagram.subgraphs[1].entityIndices.map { names[$0] }, ["PERSON"])
        XCTAssertEqual(diagram.subgraphs[2].entityIndices.map { names[$0] }, ["CAR", "NAMED-DRIVER"])
        XCTAssertEqual(diagram.subgraphs[2].childSubgraphIndices, [1])
        XCTAssertEqual(diagram.subgraphCount, 3)
    }

    func testATitleIsTheWordsBetweenBracketsAndADirectionIsTheGroups() throws {
        let diagram = try EntityRelationshipReading.diagram("erDiagram\ndirection LR\nsubgraph id1 [title 1]\ndirection BT\nCUSTOMER\nend\nsubgraph \"Customer Domain\"\nA\nend")
        XCTAssertEqual(diagram.subgraphs.map(\.title), [DiagramLabel("title 1"), DiagramLabel("Customer Domain")])
        XCTAssertEqual(diagram.subgraphs.map(\.direction), [.bottomToTop, nil])
        XCTAssertEqual(diagram.direction, .leftToRight)
    }

    func testANameHeldByTwoGroupsIsInTheFirstToEnd() throws {
        let diagram = try EntityRelationshipReading.diagram("erDiagram\nsubgraph outer\nA\nsubgraph inner\nA\nB\nend\nend")
        XCTAssertEqual(diagram.subgraphs.map(\.identifier), ["inner", "outer"])
        XCTAssertEqual(diagram.subgraphs[0].entityIndices, [0, 1])
        XCTAssertEqual(diagram.subgraphs[1].entityIndices, [])
        XCTAssertEqual(diagram.subgraphs[1].childSubgraphIndices, [0])
    }

    func testEachEntityIsInsideItsGroupsBoxAndNestedBoxesNest() throws {
        let laidOut = try layout(nested)
        XCTAssertEqual(laidOut.subgraphs.count, 3)
        let boxes = laidOut.subgraphs.map(\.frame)
        // CUSTOMER, CAR, NAMED-DRIVER, PERSON.
        XCTAssertTrue(boxes[0].contains(laidOut.entities[0].frame))
        XCTAssertTrue(boxes[2].contains(laidOut.entities[1].frame))
        XCTAssertTrue(boxes[2].contains(laidOut.entities[2].frame))
        XCTAssertTrue(boxes[1].contains(laidOut.entities[3].frame))
        XCTAssertTrue(boxes[2].contains(boxes[1]))
        XCTAssertFalse(boxes[0].intersects(boxes[2]))
        XCTAssertEqual(laidOut.subgraphs.map(\.depth), [0, 1, 0])
    }

    func testABoxHasPelesRoomAroundWhatItHolds() throws {
        let laidOut = try layout("erDiagram\nsubgraph group\nA\nend")
        let box = try XCTUnwrap(laidOut.subgraphs.first)
        let entity = laidOut.entities[0].frame
        let title = try XCTUnwrap(box.title)
        XCTAssertEqual(entity.minX - box.frame.minX, 20, accuracy: accuracy)
        XCTAssertEqual(box.frame.maxY - entity.maxY, 20, accuracy: accuracy)
        XCTAssertEqual(entity.minY - box.frame.minY, title.size.height + 16, accuracy: accuracy)
        XCTAssertEqual(title.center.y, box.frame.minY + 8 + title.size.height / 2, accuracy: accuracy)
    }

    func testARelationshipToAGroupsNameMeetsItsBox() throws {
        let laidOut = try layout("erDiagram\nsubgraph group\nA\nend\nB ||--|| group : holds")
        XCTAssertEqual(laidOut.entities.count, 2, "The entity named like the group is its box, not an entity")
        let box = laidOut.subgraphs[0].frame
        let tip = try XCTUnwrap(laidOut.relationships.first?.secondEntityMark.tip)
        XCTAssertTrue(abs(tip.y - box.minY) < accuracy || abs(tip.y - box.maxY) < accuracy || abs(tip.x - box.minX) < accuracy
                      || abs(tip.x - box.maxX) < accuracy, "\(tip) on \(box)")
    }

    func testAGroupRunsInItsOwnDirection() throws {
        let laidOut = try layout("erDiagram\nsubgraph row\ndirection LR\nA ||--|| B : next\nend")
        XCTAssertEqual(laidOut.entities[0].frame.midY, laidOut.entities[1].frame.midY, accuracy: accuracy)
        XCTAssertLessThan(laidOut.entities[0].frame.maxX, laidOut.entities[1].frame.minX)
    }

    func testTheSceneDrawsTheBoxesFirst() throws {
        let scene = DiagramScene(layout: try layout(nested))
        guard case .shape(let first) = try XCTUnwrap(scene.items.first) else { return XCTFail("A shape first") }
        XCTAssertEqual(first.part, .cluster)
        XCTAssertEqual(scene.texts.filter { text in text.part == .clusterLabel }.count, 3)
    }
}
