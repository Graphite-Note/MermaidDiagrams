/**
 * File: UseCaseFigureGeometryTests.swift
 * --------------------------------------
 * Layer: Tests
 * Description: The figures, marks, dashes and placements of a use case diagram in the numbers Pele's render.ts writes:
 *              the hollow and filled actors' outlines, the business slashes, a note's fold, the dashes of each kind of
 *              line, a loop's label, a boundary's title kept clear of the lines entering its top, the least sizes of a
 *              box, an oval and a JSON table, and the room of a table's values.
 *
 * Authors: Bahey Shalash
 * Version: 0.2
 * Date: 25/11/2026
 */

import CoreGraphics
import XCTest
@testable import MermaidDiagrams

final class UseCaseFigureGeometryTests: XCTestCase {
    /// The points a path moves and draws lines to, in order.
    private func corners(of path: CGPath) -> [CGPoint] {
        var points: [CGPoint] = []
        path.applyWithBlock { element in
            switch element.pointee.type {
            case .moveToPoint, .addLineToPoint: points.append(element.pointee.points[0])
            default: break
            }
        }
        return points
    }

    /// The shape a figure function records into a lane, as a Core Graphics path.
    private func path(_ make: (DiagramSceneWorkspace) -> DiagramPathLane) -> CGPath {
        DiagramSceneWorkspace.withRecording { workspace in make(workspace).makePath() }
    }

    private func layout(_ lines: String...) throws -> UseCaseLayout {
        try UseCaseReading.uniformLayout((["usecase-beta"] + lines).joined(separator: "\n"))
    }

    /// `M-20,-9H20V0H5.5L20,15.5L12,25.5L0,12L-12,25.5L-20,15.5L-5.5,0H-20Z` and the filled figure's head and body.
    func testTheActorFiguresAreThoseOfPele() {
        let hollow = [(-20, -9), (20, -9), (20, 0), (5.5, 0), (20, 15.5), (12, 25.5), (0, 12), (-12, 25.5), (-20, 15.5), (-5.5, 0), (-20, 0)]
        XCTAssertEqual(corners(of: path { workspace in UseCaseFigureShapes.hollowBody(at: .zero, workspace: workspace) }),
                       hollow.map { x, y in CGPoint(x: x, y: y) })
        let head = path { workspace in UseCaseFigureShapes.awesomeFigure(at: .zero, workspace: workspace) }
        XCTAssertEqual(head.boundingBoxOfPath, CGRect(x: -20, y: -30, width: 40, height: 60))
        XCTAssertTrue(head.contains(CGPoint(x: 0, y: -29.5)) && !head.contains(CGPoint(x: 0, y: -7.5)), "a head of radius 11 at -19 over a neck")
        XCTAssertEqual(path { workspace in UseCaseFigureShapes.head(radius: 9, at: .zero, workspace: workspace) }.boundingBoxOfPath,
                       CGRect(x: -9, y: -30, width: 18, height: 18))
    }

    /// A business actor's chord from (0.12 r, y + 0.99 r) to (0.92 r, y - 0.39 r); a business oval's slash from 15 to 5
    /// before its right end, each end on the outline.
    func testTheBusinessSlashesAreThoseOfPele() throws {
        let slash = corners(of: path { workspace in UseCaseFigureShapes.actorSlash(headY: -21, radius: 9, at: .zero, workspace: workspace) })
        XCTAssertEqual(slash[0].x, 1.08, accuracy: 0.0001)
        XCTAssertEqual(slash[0].y, -21 + 8.91, accuracy: 0.0001)
        XCTAssertEqual(slash[1].x, 8.28, accuracy: 0.0001)
        XCTAssertEqual(slash[1].y, -21 - 3.51, accuracy: 0.0001)
        let frame = CGRect(x: 0, y: 0, width: 100, height: 50)
        let cut = corners(of: path { workspace in UseCaseFigureShapes.ellipseSlash(in: frame, workspace: workspace) })
        XCTAssertEqual(cut[0].x, 85)
        XCTAssertEqual(cut[0].y, 25 + 25 * (1 - 0.49).squareRoot(), accuracy: 0.0001)
        XCTAssertEqual(cut[1].x, 95)
        XCTAssertEqual(cut[1].y, 25 - 25 * (1 - 0.81).squareRoot(), accuracy: 0.0001)
    }

    /// A note's top right corner folds 9 points.
    func testANotesCornerFoldsNinePoints() {
        let frame = CGRect(x: 0, y: 0, width: 100, height: 40)
        XCTAssertEqual(corners(of: path { workspace in UseCaseFigureShapes.noteOutline(in: frame, workspace: workspace) }),
                       [CGPoint(x: 0, y: 0), CGPoint(x: 91, y: 0), CGPoint(x: 100, y: 9), CGPoint(x: 100, y: 40), CGPoint(x: 0, y: 40)])
        XCTAssertEqual(corners(of: path { workspace in UseCaseFigureShapes.noteFold(in: frame, workspace: workspace) }),
                       [CGPoint(x: 91, y: 0), CGPoint(x: 91, y: 9), CGPoint(x: 100, y: 9)])
    }

    /// A note's connector is dashed 2 3, an include 5 4, an animated relationship 9 5, a plain one not at all.
    func testEachKindOfLineHasPelesDashes() throws {
        let layout = try layout("A --> B", "A ..> : include C", "A fast@--> D", "fast@{ animation: fast }", "note for A \"n\"")
        XCTAssertEqual(layout.edges.map(\.dashLengths), [[], [5, 4], [9, 5], [2, 3]])
    }

    /// A loop's label sits beyond it: 0.75 of its reach and 8 to the right when the flow runs down, 6 below when across.
    func testALoopsLabelSitsBeyondIt() throws {
        let down = try layout("direction TB", "U -- hi --> U")
        let loop = try XCTUnwrap(down.edges.first)
        let label = try XCTUnwrap(loop.label)
        XCTAssertEqual(label.center.x, loop.path.start.x + 26 * 0.75 + 8 + label.size.width / 2, accuracy: 0.0001)
        let across = try layout("U -- hi --> U")
        let sideways = try XCTUnwrap(across.edges.first)
        let below = try XCTUnwrap(sideways.label)
        XCTAssertEqual(below.center.y, sideways.path.start.y + 26 * 0.75 + 6 + below.size.height / 2, accuracy: 0.0001)
    }

    /// A boundary's title moves into the stretch of its top between entering lines nearest the middle, keeping 6 from
    /// them and from the box's ends, or into the middle of the widest stretch when none has room.
    func testABoundarysTitleKeepsClearOfEnteringLines() {
        let frame = CGRect(x: 0, y: 10, width: 200, height: 100)
        XCTAssertEqual(UseCaseBoundaryTitles.titleX(frame: frame, width: 40, crossings: [10: [100]]), 74)
        XCTAssertEqual(UseCaseBoundaryTitles.titleX(frame: frame, width: 40, crossings: [11: [100]]), 100, "no line enters this top")
        XCTAssertEqual(UseCaseBoundaryTitles.titleX(frame: frame, width: 300, crossings: [10: [100]]), 53)
    }

    /// A box is at least 80 by 44 and an oval 88 by 48, as an empty label shows.
    func testABoxAndAnOvalKeepTheirLeastSizes() throws {
        XCTAssertEqual(try layout("A[\"\"]", "A --> B").node("A")?.size, CGSize(width: 80, height: 44))
        XCTAssertEqual(try layout("A(\"\")", "A --> B").node("A")?.size, CGSize(width: 88, height: 48))
    }

    /// A JSON table is at least 72 wide, and a value wraps at 260.
    func testAJSONTableIsAtLeast72WideAndItsValuesWrapAt260() throws {
        XCTAssertEqual(try layout("json J@{}").node("J")?.size.width, 72)
        // A value 252 wide (36 characters 7 wide) stays on one line.
        let value = String(repeating: "a", count: 30) + " aaaaa"
        let table = try XCTUnwrap(try layout("json J@{\"k\": \"\(value)\"}").node("J"))
        XCTAssertEqual(table.rows.first?.valueLines.count, 1)
        XCTAssertEqual(table.size.width, 7 + 20 + 252 + 20)
    }
}
