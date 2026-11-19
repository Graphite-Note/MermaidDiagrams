/**
 * File: C4LayoutEngineTests.swift
 * -------------------------------
 * Layer: Tests
 * Description: C4 diagrams laid out as Pele's layout.ts, route.ts and render.ts lay them out: the grid and its row
 *              counts, the shapes' forms and sizes, straight lines, detours and loops, labels, headings, styles and
 *              casings, numbers worked out by hand from Pele's code, and the cases of Pele's render tests.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 19/11/2026
 */

import XCTest
@testable import MermaidDiagrams

final class C4LayoutEngineTests: XCTestCase {
    private let typography = DiagramTypography(font: DiagramFont(postScriptName: nil, size: 16))

    /// Two systems side by side, worked out by hand from layout.ts and render.ts with characters half the size wide: each
    /// box 216 by 66 (its kind 18 high, its name 24, 12 of padding above and below), the second 120 points to the right,
    /// the line from the first's right side to 7 points short of the second's left, the label "x" 6.5 wide plus 8 on the
    /// line's middle, everything 8 points in from the page.
    func testTwoNeighboursInPelesNumbers() throws {
        let layout = try C4Reading.uniformLayout("C4Context\nSystem(a, \"A\")\nSystem(b, \"B\")\nRel(a, b, \"x\")")
        XCTAssertEqual(layout.size, CGSize(width: 568, height: 82))
        XCTAssertEqual(layout.shape("a")?.frame, CGRect(x: 8, y: 8, width: 216, height: 66))
        XCTAssertEqual(layout.shape("b")?.frame, CGRect(x: 344, y: 8, width: 216, height: 66))
        let relation = try XCTUnwrap(layout.relation("a", "b"))
        XCTAssertEqual(relation.path.start, CGPoint(x: 224, y: 41))
        XCTAssertEqual(relation.path.segments, [.line(to: CGPoint(x: 337, y: 41))])
        XCTAssertEqual(relation.endMark?.tip, CGPoint(x: 344, y: 41))
        XCTAssertNil(relation.startMark)
        XCTAssertEqual(relation.labelFrame, CGRect(x: 276.75, y: 31, width: 14.5, height: 20))
        XCTAssertEqual(layout.shape("a")?.type?.lines, ["«system»"])
        XCTAssertEqual(layout.shape("a")?.name?.center, CGPoint(x: 116, y: 41 - 21 + 18 + 12))
    }

    func testEachKindAndStyleGivesItsForm() throws {
        let layout = try C4Reading.uniformLayout("""
            C4Container
            Person(p, "P")
            Person_Ext(pe, "PE")
            System(s, "S")
            SystemDb(sd, "SD")
            SystemQueue(sq, "SQ")
            ContainerDb_Ext(cde, "CDE")
            ComponentQueue_Ext(cqe, "CQE")
            System(a, "A", $tags="v1, cylinder")
            System(b, "B", $sprite="queue")
            System(c, "C")
            UpdateElementStyle(c, $shape="Person")
            System(d, "D", $tags="constructor")
            """)
        let forms: [(String, C4ShapeForm)] = [("p", .person), ("pe", .person), ("s", .rectangle), ("sd", .cylinder), ("sq", .horizontalCylinder),
                                              ("cde", .cylinder), ("cqe", .horizontalCylinder), ("a", .cylinder), ("b", .horizontalCylinder),
                                              ("c", .person), ("d", .rectangle)]
        for (alias, form) in forms { XCTAssertEqual(layout.shape(alias)?.form, form, alias) }
        XCTAssertEqual(layout.shape("pe")?.isExternal, true)
        XCTAssertEqual(layout.shape("pe")?.type?.lines, ["«external person»"])
        // A person adds its head, a database its caps: 42 of text, 24 of padding, 26 and 24.
        XCTAssertEqual(layout.shape("p")?.frame.height, 92)
        XCTAssertEqual(layout.shape("sd")?.frame.height, 92)
    }

    func testLongTextWrapsInTheShapesWidthAndAWordThatCannotWrapWidensIt() throws {
        let wrapped = try C4Reading.uniformLayout("C4Context\nSystem(a, \"A\", \"\(String(repeating: "word ", count: 40))\")")
        XCTAssertEqual(wrapped.shape("a")?.frame.width, 216)
        XCTAssertGreaterThan(wrapped.shape("a")?.frame.height ?? 0, 150)
        let wide = try C4Reading.uniformLayout("C4Context\nSystem(a, \"\(String(repeating: "W", count: 40))\")")
        XCTAssertEqual(wide.shape("a")?.frame.width, 40 * 8 + 28)
    }

    func testShapesInRowsOfFourAndBoundariesInRowsOfTwo() throws {
        let shapes = (1...5).map { index in "System(s\(index), \"S\(index)\")" }.joined(separator: "\n")
        let boundaries = (1...3).map { index in "Boundary(b\(index), \"B\(index)\") {\n System(i\(index), \"I\(index)\")\n}" }.joined(separator: "\n")
        let layout = try C4Reading.uniformLayout("C4Context\n\(shapes)\n\(boundaries)")
        let systems = (1...5).compactMap { index in layout.shape("s\(index)")?.frame }
        XCTAssertEqual(Set(systems.prefix(4).map(\.minY)).count, 1)
        XCTAssertEqual(systems[1].minX, systems[0].maxX + 120)
        XCTAssertEqual(systems[4].minX, systems[0].minX)
        XCTAssertEqual(systems[4].minY, systems[0].maxY + 88)
        let boxes = (1...3).compactMap { index in layout.boundary("b\(index)")?.frame }
        XCTAssertEqual(boxes[0].minY, systems[4].maxY + 48)
        XCTAssertEqual(boxes[1].minY, boxes[0].minY)
        XCTAssertEqual(boxes[1].minX, boxes[0].maxX + 48)
        XCTAssertEqual(boxes[2].minX, boxes[0].minX)
        XCTAssertEqual(boxes[2].minY, boxes[0].maxY + 48)
        // A boundary's padding is a lane and 8; its heading 24 + 20 high, 10 above it, 6 and a lane under it.
        XCTAssertEqual(layout.shape("i1")?.frame.minX, boxes[0].minX + 28)
        XCTAssertEqual(layout.shape("i1")?.frame.minY, boxes[0].minY + 24 + 20 + 10 + 6 + 20)
    }

    func testUpdateLayoutConfig() throws {
        let source = { (configuration: String) in
            "C4Context\nSystem(a, \"A\")\nSystem(b, \"B\")\nSystem(c, \"C\")\nBoundary(x, \"X\") {\n System(d, \"D\")\n}\nBoundary(y, \"Y\") {\n System(e, \"E\")\n}\n" + configuration
        }
        let stacked = try C4Reading.uniformLayout(source("UpdateLayoutConfig($c4ShapeInRow=\"1\", $c4BoundaryInRow=\"1\")"))
        XCTAssertEqual(stacked.shape("b")?.frame.minX, stacked.shape("a")?.frame.minX)
        XCTAssertGreaterThan(stacked.shape("b")?.frame.minY ?? 0, stacked.shape("a")?.frame.minY ?? 0)
        XCTAssertEqual(stacked.boundary("y")?.frame.minX, stacked.boundary("x")?.frame.minX)
        let positional = try C4Reading.uniformLayout(source("UpdateLayoutConfig(\"2\", \"2\")"))
        XCTAssertEqual(positional.shape("b")?.frame.minY, positional.shape("a")?.frame.minY)
        XCTAssertGreaterThan(positional.shape("c")?.frame.minY ?? 0, positional.shape("a")?.frame.minY ?? 0)
        XCTAssertEqual(positional.boundary("y")?.frame.minY, positional.boundary("x")?.frame.minY)
    }

    func testBoundariesNestAndAreSizedAroundWhatTheyHold() throws {
        let layout = try C4Reading.uniformLayout("""
            C4Deployment
            Deployment_Node(outer, "Outer", "Linux", "A machine") {
              Node(inner, "Inner") {
                Container(app, "App")
              }
              Node_L(left, "Left") {
                Container(other, "Other")
              }
            }
            Boundary(dashed, "Dashed") {
              System(s, "S")
            }
            """)
        let outer = try XCTUnwrap(layout.boundary("outer")?.frame)
        let inner = try XCTUnwrap(layout.boundary("inner")?.frame)
        XCTAssertTrue(outer.insetBy(dx: 1, dy: 1).contains(inner))
        XCTAssertTrue(inner.insetBy(dx: 1, dy: 1).contains(try XCTUnwrap(layout.shape("app")?.frame)))
        XCTAssertTrue(outer.insetBy(dx: 1, dy: 1).contains(try XCTUnwrap(layout.boundary("left")?.frame)))
        XCTAssertEqual(layout.boundary("outer")?.type.map(\.lines), [["[Linux]"]])
        XCTAssertEqual(layout.boundary("outer")?.description.map(\.lines), [["A machine"]])
        XCTAssertEqual(layout.boundary("inner")?.type.map(\.lines), [["[node]"]])
        XCTAssertEqual(layout.boundary("outer")?.isDeploymentNode, true)
        XCTAssertEqual(layout.boundary("dashed")?.isDeploymentNode, false)
    }

    func testAnArrowheadForEachEndARelationPointsAt() throws {
        let base = "C4Context\nSystem(a, \"A\")\nSystem(b, \"B\")\n"
        for macro in ["Rel", "Rel_U", "Rel_Up", "Rel_D", "Rel_Down", "Rel_L", "Rel_Left", "Rel_R", "Rel_Right"] {
            let relation = try XCTUnwrap(try C4Reading.uniformLayout(base + "\(macro)(a, b, \"x\")").relations.first)
            XCTAssertTrue(relation.startMark == nil && relation.endMark != nil, macro)
        }
        let both = try XCTUnwrap(try C4Reading.uniformLayout(base + "BiRel(a, b, \"x\")").relations.first)
        XCTAssertTrue(both.startMark != nil && both.endMark != nil)
        let back = try C4Reading.uniformLayout(base + "Rel_Back(a, b, \"x\")")
        XCTAssertNil(back.relations[0].endMark)
        XCTAssertEqual(back.relations[0].startMark?.tip.x, back.shape("a")?.frame.maxX)
    }

    func testADynamicDiagramNumbersItsRelations() throws {
        let source = "System(a, \"A\")\nSystem(b, \"B\")\nSystem(c, \"C\")\nRel(a, b, \"first\")\nRel(b, c, \"second\")"
        XCTAssertEqual(try C4Reading.uniformLayout("C4Dynamic\n" + source).relations.compactMap(\.label?.lines.first), ["1: first", "2: second"])
        XCTAssertEqual(try C4Reading.uniformLayout("C4Context\n" + source).relations.compactMap(\.label?.lines.first), ["first", "second"])
    }

    func testTheLabelOfALineBetweenNeighboursFitsTheGap() throws {
        for arguments in ["\"Sends a fairly long description of the relationship\"", "\"Makes API calls to\", \"JSON/HTTPS\""] {
            let layout = try C4LayoutEngine.layout(try C4Reading.c4("C4Context\nSystem(a, \"A\")\nSystem(b, \"B\")\nRel(a, b, \(arguments))"), typography: typography)
            let first = try XCTUnwrap(layout.shape("a")?.frame)
            let second = try XCTUnwrap(layout.shape("b")?.frame)
            let label = try XCTUnwrap(layout.relations[0].labelFrame)
            XCTAssertGreaterThanOrEqual(label.minX, first.maxX, arguments)
            XCTAssertLessThanOrEqual(label.maxX, second.minX, arguments)
        }
    }

    func testALineEndsOnTheOutlineOfAPersonADatabaseAndAQueue() throws {
        let layout = try C4Reading.uniformLayout("C4Context\nUpdateLayoutConfig(\"1\", \"1\")\nPerson(p, \"P\")\nSystemDb(d, \"D\")\nSystemQueue(q, \"Q\")\nRel(p, d, \"x\")\nRel(d, q, \"y\")")
        let toDatabase = try XCTUnwrap(layout.relation("p", "d"))
        XCTAssertEqual(toDatabase.path.start.y, layout.shape("p")?.frame.maxY)
        // The top of a cylinder is the crown of its lid.
        XCTAssertEqual(toDatabase.endMark?.tip.y ?? 0, layout.shape("d")?.frame.minY ?? 0, accuracy: 1e-9)
        let toQueue = try XCTUnwrap(layout.relation("d", "q"))
        XCTAssertEqual(toQueue.corners.first?.x, toQueue.corners.last?.x)
        XCTAssertGreaterThan(toQueue.corners.last?.y ?? 0, (toQueue.corners.first?.y ?? 0) + 50)
    }

    func testALineGoesAroundTheShapesBetweenTwoInARowOrAColumn() throws {
        let row = try C4Reading.uniformLayout("C4Context\nSystem(a, \"A\")\nSystem(b, \"B\")\nSystem(c, \"C\")\nRel(a, c, \"over\")\nRel(c, a, \"under\")")
        let first = try XCTUnwrap(row.shape("a")?.frame)
        let over = try XCTUnwrap(row.relation("a", "c")).corners
        XCTAssertEqual(over.count, 4)
        XCTAssertEqual(over[0].y, first.minY)
        XCTAssertLessThan(over[1].y, first.minY)
        let under = try XCTUnwrap(row.relation("c", "a")).corners
        XCTAssertGreaterThan(under[1].y, first.maxY)
        let column = try C4Reading.uniformLayout("C4Context\nUpdateLayoutConfig(\"1\", \"1\")\nSystem(a, \"A\")\nSystem(b, \"B\")\nSystem(c, \"C\")\nRel(a, c, \"x\")")
        let around = try XCTUnwrap(column.relation("a", "c")).corners
        XCTAssertEqual(around.count, 4)
        XCTAssertEqual(around[0].y, around[1].y)
        XCTAssertGreaterThan(around[1].x, column.shape("b")?.frame.maxX ?? 0)
    }

    func testTwoRelationsTheOppositeWayAreSeparatedWithTheirLabelsOnEitherSide() throws {
        let layout = try C4Reading.uniformLayout("C4Context\nSystem(a, \"A\")\nSystem(b, \"B\")\nRel(a, b, \"there\")\nRel(b, a, \"back\")")
        let there = try XCTUnwrap(layout.relation("a", "b"))
        let back = try XCTUnwrap(layout.relation("b", "a"))
        XCTAssertEqual(abs(there.path.start.y - back.path.start.y), 14)
        XCTAssertGreaterThan(there.labelFrame?.minY ?? 0, there.path.start.y)
        XCTAssertLessThan((back.labelFrame?.minY ?? 0) + 20, back.path.start.y)
    }

    func testARelationToItselfIsALoopWithItsLabelBeside() throws {
        let layout = try C4Reading.uniformLayout("C4Context\nSystem(a, \"A\")\nRel(a, a, \"again\")")
        let loop = try XCTUnwrap(layout.relation("a", "a"))
        guard case .curve = loop.path.segments.first else { return XCTFail("a loop is a curve") }
        XCTAssertGreaterThan(loop.labelFrame?.minX ?? 0, layout.shape("a")?.frame.maxX ?? 0)
        XCTAssertTrue(loop.corners.isEmpty)
    }

    func testABoundaryIsARelationsEnd() throws {
        let layout = try C4Reading.uniformLayout("C4Context\nSystem(out, \"Out\")\nBoundary(b, \"B\") {\n  System(in, \"In\")\n}\nRel(out, b, \"to boundary\")\nRel(b, in, \"into\")")
        let boundary = try XCTUnwrap(layout.boundary("b")?.frame)
        XCTAssertEqual(layout.relation("out", "b")?.endMark?.tip.y, boundary.minY)
        XCTAssertEqual(layout.relation("b", "in")?.path.start.x, boundary.minX)
    }

    func testARelationToSomethingNotDrawnIsRefused() throws {
        let missing = try C4Reading.c4("C4Context\nSystem(a, \"A\")\nRel(a, missing, \"x\")")
        XCTAssertThrowsError(try C4LayoutEngine.layout(missing, typography: typography)) { error in
            XCTAssertEqual(error as? C4LayoutError, .relationToUnknownElement(from: "a", to: "missing"))
        }
        let named = try C4Reading.c4("C4Context\nSystem(a, \"A\")\nRel($x=\"y\", a, \"x\")")
        XCTAssertThrowsError(try C4LayoutEngine.layout(named, typography: typography))
        XCTAssertThrowsError(try MermaidDiagramPreparation.prepare(source: "C4Context\nSystem(a, \"A\")\nRel(a, missing, \"x\")", typography: typography)) { error in
            XCTAssertEqual((error as? MermaidDiagramPreparationFailure)?.category, .refusedContent)
        }
    }

    func testABoundaryNamedGlobalIsDrawnAndOneInsideItselfIsLeftOut() throws {
        let global = try C4Reading.uniformLayout("C4Context\nBoundary(global, \"Everything\") {\n System(a, \"A\")\n}")
        XCTAssertNotNil(global.boundary("global"))
        XCTAssertNotNil(global.shape("a"))
        let cycle = try C4Reading.uniformLayout("""
            C4Context
            System(ok, "OK")
            Boundary(a, "A") {
              Boundary(b, "B") {
                Boundary(a, "A again") {
                  System(lost, "Lost")
                }
              }
            }
            """)
        XCTAssertNotNil(cycle.shape("ok"))
        XCTAssertNil(cycle.shape("lost"))
        XCTAssertNil(cycle.boundary("b"))
    }

    func testTheTitleIsCenteredAboveAndScalesWithTheFont() throws {
        let layout = try C4Reading.uniformLayout("C4Context\ntitle \(String(repeating: "A long title ", count: 8))\nSystem(a, \"A\")")
        let title = try XCTUnwrap(layout.title)
        XCTAssertEqual(title.center.x, layout.size.width / 2)
        XCTAssertGreaterThan(layout.size.width, 600)
        XCTAssertEqual(layout.shape("a")?.frame.minY, 8 + 24 + 12)
        let source = try C4Reading.c4("C4Context\nSystem(a, \"A\", \"Some description text that wraps over lines\")")
        let larger = try C4LayoutEngine.layout(source, typography: DiagramTypography(font: DiagramFont(postScriptName: nil, size: 24)))
        XCTAssertGreaterThan(larger.size.height, try C4LayoutEngine.layout(source, typography: typography).size.height)
    }
}
