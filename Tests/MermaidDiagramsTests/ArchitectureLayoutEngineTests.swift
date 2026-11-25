/**
 * File: ArchitectureLayoutEngineTests.swift
 * -----------------------------------------
 * Layer: Tests
 * Description: Architecture diagrams placed and laid out as Pele does, the relations of its render tests
 *              (tests/render/architecture.test.ts) and numbers worked out by hand from layout.ts and render.ts.
 *
 * Authors: Bahey Shalash
 * Version: 0.2
 * Date: 24/11/2026
 */

import XCTest
@testable import MermaidDiagrams

final class ArchitectureLayoutEngineTests: XCTestCase {
    /// One service without a title: its 48-point square, the page 8 points round it.
    func testOneServiceIsItsSquareOnItsPage() throws {
        let layout = try ArchitectureReading.uniformLayout("architecture-beta\n  service a")
        XCTAssertEqual(layout.size, CGSize(width: 64, height: 64))
        XCTAssertEqual(ArchitectureReading.squares(layout)["a"], CGRect(x: 8, y: 8, width: 48, height: 48))
    }

    func testANodeGoesOnTheSideItsEdgeNames() throws {
        let cells = try ArchitectureReading.cells("architecture-beta\n  service a\n  service b\n  service c\n  a:R -- L:b\n  a:B -- T:c")
        XCTAssertEqual(cells["b"]!.column, cells["a"]!.column + 1)
        XCTAssertEqual(cells["b"]!.row, cells["a"]!.row)
        XCTAssertEqual(cells["c"]!.row, cells["a"]!.row + 1)
        XCTAssertEqual(cells["c"]!.column, cells["a"]!.column)
    }

    func testPerpendicularSidesPlaceANodeDiagonally() throws {
        let cells = try ArchitectureReading.cells("architecture-beta\n  service a\n  service b\n  a:R -- T:b")
        XCTAssertEqual(cells["b"]!.column, cells["a"]!.column + 1)
        XCTAssertEqual(cells["b"]!.row, cells["a"]!.row + 1)
    }

    func testEveryNodeHasACellOfItsOwnAndPartsStayApart() throws {
        let cells = try ArchitectureReading.cells("architecture-beta\n  service a\n  service b\n  service c\n  a:R -- L:b\n  a:R -- L:c\n  service d\n  service e")
        let taken = Set(cells.values.map { cell in "\(cell.column),\(cell.row)" })
        XCTAssertEqual(taken.count, 5)
    }

    func testAGroupIsDrawnRoundItsMembersAndNothingElse() throws {
        let layout = try ArchitectureReading.uniformLayout("architecture-beta\n  group g[G]\n  service a in g\n  service b in g\n  service c\n  a:R -- L:b\n  b:R -- L:c")
        let squares = ArchitectureReading.squares(layout)
        let group = layout.groups[0].frame
        XCTAssertTrue(group.contains(squares["a"]!) && group.contains(squares["b"]!))
        XCTAssertFalse(group.intersects(squares["c"]!))
    }

    func testAlignmentsAreFollowedAheadOfEdges() throws {
        let cells = try ArchitectureReading.cells("architecture-beta\n  service a\n  service b\n  service c\n  a:R -- L:b\n  align column a c\n  c:R -- L:b")
        XCTAssertEqual(cells["c"]!.column, cells["a"]!.column)
        XCTAssertEqual(cells["c"]!.row, cells["a"]!.row + 1)
    }

    func testArrowsOnlyWhereTheEdgeHasThem() throws {
        let layout = try ArchitectureReading.uniformLayout("architecture-beta\n  service a\n  service b\n  service c\n  a:R --> L:b\n  b:R <-- L:c")
        XCTAssertNil(layout.edges[0].sourceArrow)
        XCTAssertNotNil(layout.edges[0].targetArrow)
        XCTAssertNotNil(layout.edges[1].sourceArrow)
        XCTAssertNil(layout.edges[1].targetArrow)
        let squares = ArchitectureReading.squares(layout)
        XCTAssertEqual(layout.edges[0].targetArrow!.tip, CGPoint(x: squares["b"]!.minX, y: squares["b"]!.midY))
        XCTAssertEqual(layout.edges[0].path.start, CGPoint(x: squares["a"]!.maxX, y: squares["a"]!.midY))
    }

    /// Facing sides in one row: a straight line between the squares, the gap 36 points (40 at least).
    func testFacingSidesInOneRowAreJoinedStraight() throws {
        let layout = try ArchitectureReading.uniformLayout("architecture-beta\n  service a\n  service b\n  a:R -- L:b")
        let squares = ArchitectureReading.squares(layout)
        XCTAssertEqual(squares["b"]!.minX - squares["a"]!.maxX, 40)
        XCTAssertEqual(layout.edges[0].path.segments, [.line(to: CGPoint(x: squares["b"]!.minX, y: squares["b"]!.midY))])
    }

    func testAGroupEdgeStartsAtTheGroupsBorder() throws {
        let layout = try ArchitectureReading.uniformLayout("architecture-beta\n  group g\n  service a in g\n  service b\n  a{group}:R -- L:b")
        XCTAssertEqual(layout.edges[0].path.start.x, layout.groups[0].frame.maxX, accuracy: 0.01)
    }

    func testAnEdgeTextWidensItsGapAndSitsOnItsRun() throws {
        let layout = try ArchitectureReading.uniformLayout("architecture-beta\n  service a\n  service b\n  a:R -[a long edge title]- L:b")
        let squares = ArchitectureReading.squares(layout)
        let text = layout.edgeTexts[0]
        // 17 characters at 7 points, and 28 points.
        XCTAssertEqual(squares["b"]!.minX - squares["a"]!.maxX, 17 * 7 + 28)
        XCTAssertEqual(text.center.y, squares["a"]!.midY)
        XCTAssertGreaterThan(text.frame.minX, squares["a"]!.maxX)
    }

    func testJunctionsAreDotsAndIconsAreDrawnForTheNamesPeleKnows() throws {
        let layout = try ArchitectureReading.uniformLayout("architecture-beta\n  service a(server)[A]\n  service b(logos:aws-ec2)[B]\n  junction j\n  a:R -- L:j\n  j:R -- L:b")
        guard case .junction(_, let radius) = layout.nodes[2].form else { return XCTFail("a junction") }
        XCTAssertEqual(radius, 3)
        let iconParts = DiagramScene(layout: layout).shapes.filter { shape in shape.part == .icon }
        XCTAssertEqual(iconParts.count, 1)
        XCTAssertNotNil(ArchitectureIcons.glyph(named: "cloud")?.path(in: CGRect(x: 0, y: 0, width: 24, height: 24)))
        XCTAssertNil(ArchitectureIcons.glyph(named: "logos:aws-ec2"))
    }

    func testAServicesTextIsCutToItsSquare() throws {
        let layout = try ArchitectureReading.uniformLayout("architecture-beta\n  service a \"" + String(repeating: "w", count: 40) + "\"")
        guard case .service(let square, _, let iconText?, _) = layout.nodes[0].form else { return XCTFail("a service with text") }
        XCTAssertLessThanOrEqual(iconText.size.width, square.width - 8)
        XCTAssertTrue(iconText.lines[0].hasSuffix("…"))
    }

    func testOptionsSetTheSquareTheSizeAndThePadding() throws {
        let large = try ArchitectureReading.uniformLayout("---\nconfig:\n  architecture:\n    iconSize: 80\n---\narchitecture-beta\n  service a")
        XCTAssertEqual(large.size, CGSize(width: 96, height: 96))
        let padded = try ArchitectureReading.uniformLayout("---\nconfig:\n  architecture:\n    padding: 40\n---\narchitecture-beta\n  group g\n  service a in g")
        XCTAssertEqual(padded.groups[0].frame.width, 48 + 80)
    }

    func testAnEmptyDiagramAndAnEmptyGroup() throws {
        XCTAssertTrue(try MermaidDiagramReader.read("architecture-beta", limits: .standard).hasNothingToDraw)
        let layout = try ArchitectureReading.uniformLayout("architecture-beta\n  group g[Empty]")
        XCTAssertEqual(layout.groups.count, 1)
        XCTAssertGreaterThan(layout.groups[0].frame.width, 0)
    }

    func testATightLayoutIsNoWider() throws {
        let source = "architecture-beta\n" + (0..<6).map { index in "  service s\(index)[A service with a long title \(index)]\n" }.joined()
            + (1..<6).map { index in "  s\(index - 1):R -- L:s\(index)\n" }.joined()
        XCTAssertLessThan(try ArchitectureReading.uniformLayout(source, availableWidth: 300, isTight: true).size.width,
                          try ArchitectureReading.uniformLayout(source).size.width)
    }

    func testTheSceneHoldsPelesParts() throws {
        let layout = try ArchitectureReading.uniformLayout("architecture-beta\n  title T\n  group g(cloud)[G]\n  service a(server)[A] in g\n  service b\n  a:R -[x]-> L:b")
        var seen: [DiagramScenePart] = []
        for item in DiagramScene(layout: layout).items {
            let part = switch item {
            case .shape(let shape): shape.part
            case .text(let text): text.part
            }
            if seen.last != part { seen.append(part) }
        }
        XCTAssertEqual(seen, [.title, .cluster, .icon, .clusterLabel, .edge, .marker, .labelBackground, .edgeLabel, .node, .icon, .label, .node])
    }
}
