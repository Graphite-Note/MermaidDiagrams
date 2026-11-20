/**
 * File: AgentFlowLayoutEngineTests.swift
 * --------------------------------------
 * Layer: Tests
 * Description: An agent flow laid out with Pele's numbers, worked out by hand from agentflow/render.ts with text eight
 *              points a character: node sizes, wrapping, collapsed flows, options, the edges between a node and the
 *              flow around it, palette slots and the turned layout; and its scene in Pele's order and paints.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 19/11/2026
 */

import XCTest
@testable import MermaidDiagrams

final class AgentFlowLayoutEngineTests: XCTestCase {
    private func layout(_ source: String, isTurned: Bool = false) throws -> AgentFlowLayout {
        try AgentFlowLayoutEngine.layout(try AgentFlowReading.diagram(source), nodeText: UniformWidthTextMeasurer(),
                                         edgeText: UniformWidthTextMeasurer(characterWidth: 7, fontSize: 14, lineHeight: 21),
                                         font: UniformWidthLayout.font, limits: .standard, isTurnedToRunDown: isTurned)
    }

    private func node(_ identifier: String, in layout: AgentFlowLayout) throws -> AgentFlowLayoutNode {
        try XCTUnwrap(layout.nodes.first { node in node.identifier == identifier })
    }

    func testShapesAreSizedForTextAtLeast120WideButADiamondAndWrapAt120() throws {
        let laidOut = try layout("agentflow-beta TB\n  a[\"abc\"]\n  d{\"abc\"}\n  w[\"abcd abcd abcd abcd\"]\n  t[\"abc\"]@{ shape: tool }")
        // A rounded box: the text at least 120 wide and 18 points either side; 12 above and below a 24-point line.
        XCTAssertEqual(try node("a", in: laidOut).frame.size, CGSize(width: 156, height: 48))
        // A diamond keeps its text's 24 points: 24 + 16 across and 24 + 8 down, then 40 + 1.6 × 32 by 40 / 1.6 + 32.
        let diamond = try node("d", in: laidOut).frame.size
        XCTAssertEqual(diamond.width, 91.2, accuracy: 0.001)
        XCTAssertEqual(diamond.height, 57, accuracy: 0.001)
        // Wrapped at 120: "abcd abcd abcd" (112 points), then "abcd".
        XCTAssertEqual(try node("w", in: laidOut).text.lines, ["abcd abcd abcd", "abcd"])
        XCTAssertEqual(try node("w", in: laidOut).frame.size, CGSize(width: 156, height: 72))
        // A tool's subroutine is 16 points wider than a box.
        XCTAssertEqual(try node("t", in: laidOut).frame.width, 172)
    }

    func testACollapsedFlowIsABoxWithRoomForItsDotsBelowItsText() throws {
        let laidOut = try layout("agentflow-beta TB\n  flow p[\"Proc\"]\n    a --> b\n  end\n  p@{ view: collapsed }\n  x --> p")
        let collapsed = try node("p", in: laidOut)
        XCTAssertTrue(collapsed.isCollapsedFlow)
        XCTAssertEqual(collapsed.frame.size, CGSize(width: 156, height: 62))
        XCTAssertEqual(collapsed.text.center.y, collapsed.frame.midY - 7, accuracy: 0.001)
        XCTAssertEqual(collapsed.paletteSlot, 7)
        XCTAssertEqual(laidOut.nodes.map(\.identifier), ["p", "x"])
        XCTAssertTrue(laidOut.flows.isEmpty)
    }

    func testTheOptionsSetTheGapsAndTheWrapping() throws {
        let regular = try layout("agentflow-beta TB\n  a --> b")
        let spaced = try layout("---\nconfig:\n  agentflow:\n    rankSpacing: 70\n    minNodeWidth: 40\n---\nagentflow-beta TB\n  a --> b")
        func gap(_ laidOut: AgentFlowLayout) throws -> CGFloat { try node("b", in: laidOut).frame.minY - node("a", in: laidOut).frame.maxY }
        XCTAssertEqual(try gap(spaced) - gap(regular), 22, accuracy: 0.001)
        XCTAssertEqual(try node("a", in: spaced).frame.width, 76)
        let narrow = try layout("---\nconfig:\n  agentflow:\n    wrappingWidth: 40\n---\nagentflow-beta TB\n  w[\"abcd abcd abcd\"]")
        XCTAssertEqual(try node("w", in: narrow).text.lines, ["abcd", "abcd", "abcd"])
    }

    func testAnEdgeBetweenANodeAndItsFlowRunsStraightToTheFlowsBorder() throws {
        let out = try layout("agentflow-beta TB\n  flow f[\"F\"]\n    a\n    a --> f\n  end")
        let flow = try XCTUnwrap(out.flows.first).frame
        let task = try node("a", in: out).frame
        let edge = try XCTUnwrap(out.edges.first)
        // Out of the node's bottom, down along the flow, to the flow's bottom border, the arrow's tip on it.
        XCTAssertEqual(edge.path.start, CGPoint(x: task.midX, y: task.maxY))
        XCTAssertEqual(edge.targetMark?.tip, CGPoint(x: task.midX, y: flow.maxY))
        XCTAssertEqual(edge.targetMark?.direction, CGVector(dx: 0, dy: 1))
        let into = try layout("agentflow-beta LR\n  flow f[\"F\"]\n    a\n    f --> a\n  end")
        let intoTask = try node("a", in: into).frame
        let intoEdge = try XCTUnwrap(into.edges.first)
        // From the flow's left border, against its direction, into the node's left side.
        XCTAssertEqual(intoEdge.path.start, CGPoint(x: try XCTUnwrap(into.flows.first).frame.minX, y: intoTask.midY))
        XCTAssertEqual(intoEdge.targetMark?.tip, CGPoint(x: intoTask.minX, y: intoTask.midY))
    }

    func testAnEdgeToItsFlowTakesAnotherSideWhenANodeIsInTheWay() throws {
        let laidOut = try layout("agentflow-beta TB\n  flow f[\"F\"]\n    a --> b\n    a --> f\n  end")
        let task = try node("a", in: laidOut).frame
        let below = try node("b", in: laidOut).frame
        let held = try XCTUnwrap(laidOut.edges.last)
        XCTAssertTrue(below.minY > task.maxY)
        // b lies below a, so the edge takes the next side clockwise from the bottom: out of a's left side to the flow's left border.
        XCTAssertEqual(held.path.start, CGPoint(x: task.minX, y: task.midY))
        XCTAssertEqual(held.targetMark?.tip.x, try XCTUnwrap(laidOut.flows.first).frame.minX)
    }

    func testNodesTakeTheirKindsSlotsAndFlowsTheSlotsAboveTheKinds() throws {
        let laidOut = try layout("agentflow-beta TB\n  flow f\n    t@{ shape: tool }\n    k@{ shape: task }\n    d@{ shape: decision }\n    i@{ shape: input }\n"
            + "    r@{ shape: refdoc }\n    x@{ shape: action }\n  end\n  connector c[\"C\"]")
        XCTAssertEqual(try ["t", "k", "d", "i", "r", "c", "x"].map { identifier in try node(identifier, in: laidOut).paletteSlot }, [0, 1, 2, 3, 4, 5, 6])
        XCTAssertEqual(laidOut.flows.map(\.paletteSlot), [7])
        XCTAssertEqual(AgentFlowDiagramBuilder.containerSlot(3, paletteLength: 12), 10)
        XCTAssertEqual(AgentFlowDiagramBuilder.containerSlot(6, paletteLength: 12), 8)
        XCTAssertEqual(AgentFlowDiagramBuilder.containerSlot(2, paletteLength: 3), 1)
    }

    func testADiagramRunningAcrossIsTurnedToRunDown() throws {
        let across = try layout("agentflow-beta LR\n  a --> b --> c")
        let down = try layout("agentflow-beta LR\n  a --> b --> c", isTurned: true)
        XCTAssertGreaterThan(try node("b", in: across).frame.minX, try node("a", in: across).frame.maxX)
        XCTAssertGreaterThan(try node("b", in: down).frame.minY, try node("a", in: down).frame.maxY)
        XCTAssertLessThan(down.size.width, across.size.width)
    }

    func testTheSceneIsPaintedInPelesOrderAndPaints() throws {
        let laidOut = try layout("---\ntitle: Review\n---\nagentflow-beta TB\n  flow f[\"Flow\"]\n    a@{ shape: tool } -- uses --> b\n  end\n"
            + "  b -.- c\n  style c fill:#000000,color:#ff0000\n  style a fill:#ffffff")
        let scene = DiagramScene(layout: laidOut)
        let parts = scene.items.map { item -> DiagramScenePart in
            switch item {
            case .shape(let shape): shape.part
            case .text(let text): text.part
            }
        }
        var order: [DiagramScenePart] = []
        for part in parts where order.last != part { order.append(part) }
        XCTAssertEqual(order, [.title, .cluster, .clusterLabel, .edge, .marker, .edge, .labelBackground, .edgeLabel, .node, .label, .node, .label,
                               .node, .label])
        let shapes = scene.shapes.filter { shape in shape.part == .cluster || shape.part == .node }
        let paints = shapes.map(\.painting)
        XCTAssertEqual(paints[0], .fillAndStroke(DiagramPaint.series(7).atOpacity(0.06), .series(7), .rounded(lineWidth: 1)))
        // A style's fill replaces the wash and stays opaque; the outline keeps its kind's color.
        XCTAssertEqual(paints[1], .fillAndStroke(.color(try XCTUnwrap(DiagramColor(cssText: "#ffffff"))), .series(0), .rounded(lineWidth: 1)))
        XCTAssertEqual(paints[3], .fillAndStroke(DiagramPaint.series(1).atOpacity(0.14), .series(1), .rounded(lineWidth: 1)))
        let edgeStrokes = scene.shapes.filter { shape in shape.part == .edge }.map(\.painting)
        XCTAssertEqual(edgeStrokes.last, .stroke(.line, .rounded(lineWidth: 1, dashLengths: [3, 4])))
        let texts = scene.texts
        XCTAssertEqual(texts.first?.isBold, true)
        XCTAssertEqual(texts.first { text in text.part == .clusterLabel }?.paint, .muted)
        XCTAssertEqual(texts.last?.paint, .color(try XCTUnwrap(DiagramColor(cssText: "#ff0000"))))
        // Pele's dark ink on a white fill.
        XCTAssertEqual(texts.first { text in text.part == .label }?.paint, .color(try XCTUnwrap(SequenceTextInk.ink(onColor: try XCTUnwrap(DiagramColor(cssText: "#ffffff"))))))
    }
}
