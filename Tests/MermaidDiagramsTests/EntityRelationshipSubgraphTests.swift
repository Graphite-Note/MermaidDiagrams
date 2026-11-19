/**
 * File: EntityRelationshipSubgraphTests.swift
 * -------------------------------------------
 * Layer: Tests
 * Description: Entity relationship groups read as Mermaid's database keeps them and drawn as Pele's nested boxes.
 *
 * Authors: Bahey Shalash
 * Version: 0.2
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

    /// Pele's database keeps a group's title as Markdown even when it is the identifier.
    func testATitleWithoutBracketsIsReadAsMarkdown() throws {
        let diagram = try EntityRelationshipReading.diagram("erDiagram\nsubgraph __core__\nA\nend")
        XCTAssertEqual(diagram.subgraphs[0].title, DiagramLabelDecoder.label(from: "__core__", form: .markdown))
        XCTAssertNotEqual(diagram.subgraphs[0].title, DiagramLabelDecoder.label(from: "__core__", form: .plain))
    }

    /// A relationship from a group to itself loops off the right of the group's box, centered on its side, and the
    /// drawing is widened by the loop's reach as Pele's renderer widens it: a mark, three quarters of the turn, 10 points
    /// and the widest label.
    func testAGroupRelatedToItselfLoopsOffItsBoxsRightSide() throws {
        let laidOut = try layout("erDiagram\nsubgraph group\nA\nend\ngroup ||--|| group : itself")
        let box = try XCTUnwrap(laidOut.subgraphs.first).frame
        let loop = try XCTUnwrap(laidOut.relationships.first)
        XCTAssertEqual(loop.firstEntityMark.tip.x, box.maxX, accuracy: accuracy)
        XCTAssertEqual(loop.secondEntityMark.tip.x, box.maxX, accuracy: accuracy)
        XCTAssertEqual((loop.firstEntityMark.tip.y + loop.secondEntityMark.tip.y) / 2, box.midY, accuracy: accuracy)
        let label = try XCTUnwrap(loop.label)
        let reach = EntityRelationshipCardinalityMark.length + EntityRelationshipSelfLoops.turnReach * 0.75 + 10 + label.size.width
        XCTAssertEqual(laidOut.size.width, (box.maxX + reach + EntityRelationshipLayoutEngine.padding).rounded(.up), accuracy: accuracy)
    }

    /// A relationship between a group and an entity inside it runs from one center to the other, straight down or up
    /// for a mark's length at each end before it curves, as Pele stubs it.
    func testARelationshipFromInsideAGroupToItRunsStraightAtItsEnds() throws {
        let laidOut = try layout("erDiagram\nsubgraph outer\nA ||--o{ B : has\nC\nend\nC ||--|| outer : inside")
        let box = try XCTUnwrap(laidOut.subgraphs.first).frame
        let relationship = laidOut.relationships[1]
        XCTAssertEqual(relationship.secondEntityMark.tip.x, box.midX, accuracy: accuracy)
        XCTAssertEqual(relationship.secondEntityMark.tip.y, box.midY, accuracy: accuracy)
        let start = relationship.path.start
        guard case .line(let afterStart) = try XCTUnwrap(relationship.path.segments.first) else { return XCTFail("A straight run first") }
        XCTAssertEqual(afterStart.x, start.x, accuracy: accuracy)
        XCTAssertEqual(abs(afterStart.y - start.y), EntityRelationshipCardinalityMark.length, accuracy: accuracy)
        guard case .line(let end) = try XCTUnwrap(relationship.path.segments.last) else { return XCTFail("A straight run last") }
        XCTAssertEqual(end, relationship.secondEntityMark.tip)
    }
}
