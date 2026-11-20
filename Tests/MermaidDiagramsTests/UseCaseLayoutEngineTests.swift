/**
 * File: UseCaseLayoutEngineTests.swift
 * ------------------------------------
 * Layer: Tests
 * Description: Use case diagrams laid out in Pele's numbers, worked out by hand from its render.ts with text of fixed
 *              widths (half the size a character): node sizes, ranks, ends on outlines, loops, boundaries, labels.
 *
 * Authors: Bahey Shalash
 * Version: 0.2
 * Date: 19/11/2026
 */

import XCTest
@testable import MermaidDiagrams

final class UseCaseLayoutEngineTests: XCTestCase {
    private func layout(_ lines: String...) throws -> UseCaseLayout {
        try UseCaseReading.uniformLayout((["usecase-beta"] + lines).joined(separator: "\n"))
    }

    /// An actor is its 40 by 60 figure, a 6 point gap and its label; an oval 88 by 48 at least, its text and 20 on each
    /// side and 4 more; ranks 72 apart; the page padded by 8 and rounded up.
    func testAnActorAndAnOvalAreSizedAndRankedInPelesNumbers() throws {
        let layout = try layout("actor A", "A --> B")
        let actor = try XCTUnwrap(layout.node("A"))
        let oval = try XCTUnwrap(layout.node("B"))
        XCTAssertEqual(actor.size, CGSize(width: 40, height: 90))
        XCTAssertEqual(oval.size, CGSize(width: 88, height: 52))
        XCTAssertEqual(layout.size, CGSize(width: 216, height: 106))
        XCTAssertEqual(actor.center, CGPoint(x: 28, y: 53))
        XCTAssertEqual(oval.center, CGPoint(x: 164, y: 53))
        // The line leaves the actor's figure 23 points right of its middle, 15 above the node's middle, and meets the
        // oval at its left end, 7 points short for the arrowhead.
        let edge = try XCTUnwrap(layout.edge("edge-0"))
        XCTAssertEqual(edge.path.start, CGPoint(x: 51, y: 38))
        XCTAssertEqual(edge.path.segments, [.curve(to: CGPoint(x: 113, y: 53), control1: CGPoint(x: 82, y: 38), control2: CGPoint(x: 82, y: 53))])
        XCTAssertEqual(edge.endMark, UseCaseLayoutMark(marker: .point, tip: CGPoint(x: 120, y: 53), direction: CGVector(dx: 1, dy: 0)))
        XCTAssertNil(edge.startMark)
        XCTAssertEqual(actor.label.center, CGPoint(x: 28, y: 86))
    }

    func testBoxesNotesStereotypesAndBusinessOvalsAreSizedAroundTheirText() throws {
        let layout = try layout("direction TB", "R[Report] <<Record>>", "B(Quote)@{ business: true }", "N", "note for N Hello")
        // A box: the wider of «Record» (8 characters at 13 points) and Report, 10 on each side and 12 more; its height
        // the two texts and 24, at least 44.
        XCTAssertEqual(layout.node("R")?.size, CGSize(width: max(8 * 6.5, 6 * 8) + 32, height: 24 + 20 + 24))
        XCTAssertEqual(layout.node("B")?.size, CGSize(width: 5 * 8 + 40 + 16, height: 52))
        // A note: its text at 14 points, 10 on each side and 6 more, 18 more than its height.
        XCTAssertEqual(layout.node("note-0")?.size, CGSize(width: 5 * 7 + 26, height: 21 + 18))
        let report = try XCTUnwrap(layout.node("R"))
        XCTAssertEqual(report.stereotype.center.y, report.center.y - 12)
        XCTAssertEqual(report.label.center.y, report.center.y + 10)
        XCTAssertEqual(layout.edges.last?.dashLengths, [2, 3])
    }

    /// A JSON table: its name in bold over rows at 14 points, at least 21 high and 8 more each; keys in a column 20
    /// wider than the widest; the table at least 72 wide.
    func testAJSONTableIsSizedByItsRows() throws {
        let table = try XCTUnwrap(try layout("json T@{\"ab\": \"xyz\", \"c\": [1, 2]}").node("T"))
        XCTAssertEqual(table.headHeight, 24 + 8)
        XCTAssertEqual(table.keyColumnWidth, 2 * 7 + 20)
        XCTAssertEqual(table.size, CGSize(width: max(1 * 8 + 20, 34 + 3 * 7 + 20, 72), height: 32 + 3 * 29))
        XCTAssertEqual(table.rows.map { row in row.key.lines }, [["ab"], ["c"], []])
        XCTAssertEqual(table.rows[0].valueLines.first?.center.x, table.frame.minX + 34 + 10 + 3 * 7 / 2)
    }

    func testABoundaryPadsWhatItHoldsAndAPackageHoldsItsTitleInATab() throws {
        let plain = try layout("systemBoundary S[Shop]", "A", "end")
        let box = try XCTUnwrap(plain.boundaries.first)
        let inside = try XCTUnwrap(plain.node("A"))
        XCTAssertEqual(box.frame.width, 88 + 40)
        XCTAssertEqual(box.frame.height, 24 + 16 + 52 + 20)
        XCTAssertEqual(inside.frame.minY - box.frame.minY, 40)
        XCTAssertEqual(box.title.center, CGPoint(x: box.frame.midX, y: box.frame.minY + 8 + 12))
        let package = try XCTUnwrap(try layout("systemBoundary S[Shop]@{ type: package }", "A", "end").boundaries.first)
        XCTAssertEqual(package.frame.height, 24 + 12 + 16 + 52 + 20)
        XCTAssertEqual(package.tabFrame, CGRect(x: package.frame.minX, y: package.frame.minY, width: 32 + 20, height: 36))
        XCTAssertEqual(package.title.center, CGPoint(x: package.frame.minX + 26, y: package.frame.minY + 18))
    }

    /// Ends on one side of a node spread 14 points apart in the order they fan out.
    func testEndsOnOneSideSpreadAlongIt() throws {
        let layout = try layout("direction TB", "A --> B", "A --> C")
        let starts = layout.edges.map(\.path.start.x)
        XCTAssertEqual(abs(starts[1] - starts[0]), 14)
        XCTAssertEqual((starts[0] + starts[1]) / 2, layout.node("A")?.center.x)
        // Six ends share an oval's 88 wide bottom: spread over six tenths of it, each on the outline.
        let fanned = try self.layout("direction TB", "A --> B", "A --> C", "A --> D", "A --> E", "A --> F", "A --> G")
        let oval = try XCTUnwrap(fanned.node("A"))
        let fannedStarts = fanned.edges.map(\.path.start).sorted { first, second in first.x < second.x }
        XCTAssertEqual(fannedStarts[1].x - fannedStarts[0].x, 88 * 0.6 / 5, accuracy: 0.0001)
        let along = fannedStarts[0].x - oval.center.x
        XCTAssertEqual(oval.size.width, 88)
        let halfHeight = oval.size.height / 2
        XCTAssertEqual(fannedStarts[0].y, oval.center.y + halfHeight * (1 - (along / 44) * (along / 44)).squareRoot(), accuracy: 0.0001)
        // An actor's ends above and below it sit 2 beyond its node.
        let actor = try self.layout("direction TB", "actor P", "U --> P", "P --> V")
        let person = try XCTUnwrap(actor.node("P"))
        XCTAssertEqual(actor.edges[0].endMark?.tip.y, person.frame.minY - 2)
        XCTAssertEqual(actor.edges[1].path.start.y, person.frame.maxY + 2)
    }

    /// A loop goes out of the bottom of a node whose flow runs across, its box in the layout 52 higher, and out of the
    /// right of one whose flow runs down; each further loop reaches 8 further.
    func testLoopsGoOutAcrossTheFlowAndGrowTheirNodesBox() throws {
        let across = try layout("A --> A", "A --> A")
        let node = try XCTUnwrap(across.node("A"))
        XCTAssertEqual(across.size.height, (52 + 2 * 2 * 26 + 16).rounded(.up))
        let first = try XCTUnwrap(across.edges.first)
        // The ends are 8 either side of the oval's bottom middle, on its outline; the second loop's 14.
        let reach = 26 * (1 - (8.0 / 44) * (8.0 / 44)).squareRoot()
        XCTAssertEqual(first.path.start.x, node.center.x - 8)
        XCTAssertEqual(first.path.start.y, node.center.y + reach, accuracy: 0.0001)
        XCTAssertEqual(first.endMark?.tip.x, node.center.x + 8)
        guard case .curve(_, let control1, _) = first.path.segments.first, case .curve(_, let further, _) = across.edges[1].path.segments.first else {
            return XCTFail("not a curve")
        }
        XCTAssertEqual(control1.x, node.center.x - 16)
        XCTAssertEqual(control1.y, node.center.y + reach + 26, accuracy: 0.0001)
        XCTAssertEqual(further.y, node.center.y + 26 * (1 - (14.0 / 44) * (14.0 / 44)).squareRoot() + 34, accuracy: 0.0001)
        let down = try layout("direction TB", "A -- loop --> A")
        let loop = try XCTUnwrap(down.edges.first)
        let oval = try XCTUnwrap(down.node("A"))
        XCTAssertEqual(loop.endMark?.tip.x ?? 0, oval.center.x + 44 * (1 - (8.0 / 26) * (8.0 / 26)).squareRoot(), accuracy: 0.0001)
        XCTAssertEqual(loop.label?.center.y, oval.center.y)
        XCTAssertEqual(down.size.width, (88 + 2 * (26 + 28 + 12) + 16).rounded(.up))
    }

    func testEdgeLabelsSitOnPatchesAndIncludeIsWrittenInGuillemets() throws {
        let layout = try layout("A ..> : include B", "A -- \"uses it\" --> C")
        let include = try XCTUnwrap(layout.edges.first)
        XCTAssertEqual(include.label?.lines, ["«include»"])
        XCTAssertEqual(include.dashLengths, [5, 4])
        XCTAssertTrue(include.isSemantic)
        let label = try XCTUnwrap(layout.edges[1].label)
        XCTAssertEqual(layout.edges[1].labelPatch, CGRect(x: label.center.x - (7 * 7 + 8) / 2, y: label.center.y - 10.5, width: 7 * 7 + 8, height: 21))
    }

    func testATitleSitsAboveAndTheSpacingOptionsWiden() throws {
        let titled = try UseCaseReading.uniformLayout("---\ntitle: Shop\n---\nusecase-beta\nactor A\nA --> B")
        XCTAssertEqual(titled.size.height, 106 + 24 + 12)
        XCTAssertEqual(titled.title?.center, CGPoint(x: titled.size.width / 2, y: 8 + 12))
        let spaced = try UseCaseReading.uniformLayout("---\nconfig:\n  usecase:\n    rankSpacing: 100\n---\nusecase-beta\nactor A\nA --> B")
        XCTAssertEqual(spaced.size.width, 216 + 28)
    }

    /// A diagram that runs across is turned to run down for a container narrower than it and than 640 points.
    func testADiagramThatRunsAcrossTurnsDownToFitANarrowContainer() throws {
        let typography = DiagramTypography(font: DiagramFont(postScriptName: nil, size: 16))
        let diagram = try UseCaseReading.lines("actor A", "A --> B", "B --> C", "C --> D")
        let across = try UseCaseLayoutEngine.layout(diagram, typography: typography)
        let fitted = try UseCaseLayoutEngine.layout(diagram, typography: typography, fittingWidth: 300)
        XCTAssertLessThan(fitted.size.width, across.size.width)
        XCTAssertEqual(try UseCaseLayoutEngine.layout(diagram, typography: typography, fittingWidth: 700).size, across.size)
        XCTAssertNil(try UseCaseReading.lines("direction TB", "A").turnedToRunDown)
    }
}
