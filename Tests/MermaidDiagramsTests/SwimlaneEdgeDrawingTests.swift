/**
 * File: SwimlaneEdgeDrawingTests.swift
 * ------------------------------------
 * Layer: Tests
 * Description: A swimlane diagram's edges in the numbers Pele's flowchart renderer draws them with, taken from Pele itself
 *              with text of uniform widths: ends that turn as far from a node as the marks beside them need, loops beside
 *              their steps, and a diagram that runs right to left turned to run down from the top.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 19/11/2026
 */

import XCTest
@testable import MermaidDiagrams

final class SwimlaneEdgeDrawingTests: XCTestCase {
    private static func layout(_ diagram: FlowchartDiagram, isTight: Bool = false) -> SwimlaneLayout {
        let measurer = UniformWidthTextMeasurer()
        return SwimlaneLayoutEngine.layout(diagram, nodeText: measurer, edgeText: UniformWidthTextMeasurer(characterWidth: 7, fontSize: 14, lineHeight: 21),
                                           titleText: measurer, font: DiagramFont(postScriptName: nil, size: 16), isTight: isTight, columnWidth: isTight ? 300 : nil)
    }

    private static func assertPoint(_ point: CGPoint, _ expected: CGPoint, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(point.x, expected.x, accuracy: 0.01, file: file, line: line)
        XCTAssertEqual(point.y, expected.y, accuracy: 0.01, file: file, line: line)
    }

    /// Pele's `sideReach`: `b --- c` has no mark at c, but `a --> c` has an arrow on the same side of c, so `b --- c` runs
    /// straight into c for the arrow's 7 points and the lead's 6 before it, as Pele draws it: `M56,216C56,233.5 72,233.5
    /// 72,251L72,264`.
    func testAnEndBesideAMarkOnItsSideTurnsAsFarFromItsNodeAsTheMarkNeeds() throws {
        let layout = Self.layout(try SwimlaneCorpusTests.read("swimlane-beta TD\n subgraph L\n a\n b\n c\n end\n a --- b\n a --> c\n b --- c\n"))
        let edge = layout.flowchart.edges[2]
        Self.assertPoint(edge.path.start, CGPoint(x: 56, y: 216))
        guard edge.path.segments.count == 2, case .curve(let turnEnd, let first, let second) = edge.path.segments[0],
              case .line(let end) = edge.path.segments[1] else { return XCTFail("an S, then a straight run: \(edge.path)") }
        Self.assertPoint(first, CGPoint(x: 56, y: 233.5))
        Self.assertPoint(second, CGPoint(x: 72, y: 233.5))
        Self.assertPoint(turnEnd, CGPoint(x: 72, y: 251))
        Self.assertPoint(end, CGPoint(x: 72, y: 264))
        XCTAssertNil(edge.targetMark)
    }

    /// Pele's `loopPath` beside a step in a flow that runs across: out of its bottom 8 points left of its middle, back 8
    /// points right of it with the arrow's trim, the controls 26 points out and twice as wide; the step's place grows by the
    /// loop's 26 points and its text's 21 and 8 on both sides, the text below the loop: `M88,135C80,161 112,161 106.06,141.69`.
    func testALoopInAFlowThatRunsAcrossIsDrawnAsPeleDrawsIt() throws {
        let layout = Self.layout(try SwimlaneCorpusTests.read("swimlane-beta LR\n subgraph L0\n n0[a]\n end\n n0 -->|yes| n0\n"))
        XCTAssertEqual(layout.size, CGSize(width: 152, height: 222))
        let loop = try XCTUnwrap(layout.flowchart.edges.first)
        Self.assertPoint(loop.path.start, CGPoint(x: 88, y: 135))
        guard case .curve(let end, let first, let second) = loop.path.segments.first else { return XCTFail("a curve") }
        Self.assertPoint(first, CGPoint(x: 80, y: 161))
        Self.assertPoint(second, CGPoint(x: 112, y: 161))
        Self.assertPoint(end, CGPoint(x: 106.06, y: 141.69))
        Self.assertPoint(try XCTUnwrap(loop.targetMark?.tip), CGPoint(x: 104, y: 135))
        Self.assertPoint(try XCTUnwrap(loop.text?.center), CGPoint(x: 96, y: 177.5))
    }

    /// Two loops on one step in a flow that runs down, as Pele draws them: the second 6 points wider and 8 farther out, the
    /// step's place 26 and its text's 21 and 12 wider on each side for the first, 26 for the second.
    func testASecondLoopReachesFartherThanTheFirst() throws {
        let layout = Self.layout(try SwimlaneCorpusTests.read("swimlane-beta TB\n subgraph L0\n n0[a]\n end\n n0 -->|yes| n0\n n0 --> n0\n"))
        XCTAssertEqual(layout.size, CGSize(width: 282, height: 152))
        let first = layout.flowchart.edges[0]
        let second = layout.flowchart.edges[1]
        Self.assertPoint(first.path.start, CGPoint(x: 165, y: 88))
        Self.assertPoint(second.path.start, CGPoint(x: 165, y: 82))
        guard case .curve(let end, let control, _) = second.path.segments.first else { return XCTFail("a curve") }
        Self.assertPoint(control, CGPoint(x: 199, y: 68))
        Self.assertPoint(end, CGPoint(x: 171.47, y: 112.67))
        Self.assertPoint(try XCTUnwrap(first.text?.center), CGPoint(x: 211.5, y: 96))
    }

    /// An invisible loop is not drawn and is not counted: the loop after it is drawn as a step's first, as Pele draws it
    /// (`M132,88C158,80 158,112 138.69,106.06`), though both widen the step's place.
    func testAnInvisibleLoopDoesNotCountAmongTheLoopsDrawn() throws {
        let layout = Self.layout(try SwimlaneCorpusTests.read("swimlane-beta TB\n subgraph L0\n n0[a]\n end\n n0 ~~~ n0\n n0 --> n0\n"))
        XCTAssertEqual(layout.size, CGSize(width: 216, height: 152))
        let loop = try XCTUnwrap(layout.flowchart.edges.last)
        Self.assertPoint(loop.path.start, CGPoint(x: 132, y: 88))
        guard case .curve(let end, let first, _) = loop.path.segments.first else { return XCTFail("a curve") }
        Self.assertPoint(first, CGPoint(x: 158, y: 80))
        Self.assertPoint(end, CGPoint(x: 138.69, y: 106.06))
    }

    /// An empty group with a loop of its own is as wide as the loop's room on both sides, as Pele grows the group's node:
    /// 52 points, the loop from the group's middle.
    func testAnEmptyGroupsLoopWidensIt() throws {
        let layout = Self.layout(try SwimlaneCorpusTests.read("swimlane-beta TB\n subgraph A\n subgraph G\n end\n x\n end\n G --> G\n x --> G\n"))
        XCTAssertEqual(layout.size, CGSize(width: 116, height: 200))
        XCTAssertEqual(layout.flowchart.clusters.first?.frame, CGRect(x: 32, y: 168, width: 52, height: 0))
        Self.assertPoint(try XCTUnwrap(layout.flowchart.edges.first?.path.start), CGPoint(x: 58, y: 172))
    }

    /// Pele turns a flowchart variant that runs across to run down from the top (`rootDir` "TB"), right to left as well as
    /// left to right: a, written first, above b.
    func testARightToLeftDiagramTurnsToRunDownFromTheTop() throws {
        let diagram = try SwimlaneCorpusTests.read("swimlane-beta RL\n subgraph A\n a\n end\n subgraph B\n b\n end\n a --> b\n")
        let turned = try XCTUnwrap(diagram.swimlaneTurnedToRunDown)
        XCTAssertEqual(turned.direction, .topToBottom)
        XCTAssertNil(try SwimlaneCorpusTests.read("swimlane-beta BT\n a --> b\n").swimlaneTurnedToRunDown)
        let layout = Self.layout(turned, isTight: true)
        XCTAssertEqual(layout.size, CGSize(width: 160, height: 188))
        Self.assertPoint(CGPoint(x: layout.flowchart.nodes[0].frame.midX, y: layout.flowchart.nodes[0].frame.midY), CGPoint(x: 44, y: 84))
        Self.assertPoint(CGPoint(x: layout.flowchart.nodes[1].frame.midX, y: layout.flowchart.nodes[1].frame.midY), CGPoint(x: 116, y: 144))
    }
}
