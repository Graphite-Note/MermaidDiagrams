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
        try AgentFlowLayoutEngine.layout(try AgentFlowReading.diagram(source), measurers: BlockReading.measurers, font: UniformWidthLayout.font,
                                         limits: .standard, isTurnedToRunDown: isTurned)
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
        // Wrapped at 120: "abcd abcd abcd" (112 points), then "abcd", the lines 1.3 sizes apart (21 points), as Pele sets
        // text of more than one line, and 12 above and below them.
        XCTAssertEqual(try node("w", in: laidOut).text.lines, ["abcd abcd abcd", "abcd"])
        XCTAssertEqual(try node("w", in: laidOut).text.lineHeight, 21)
        XCTAssertEqual(try node("w", in: laidOut).frame.size, CGSize(width: 156, height: 66))
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

    func testTextOfSeveralLinesIsSetCloserAsPeleSetsIt() throws {
        let laidOut = try layout("agentflow-beta TB\n  a[\"one<br>two\"] -->|abcd abcd abcd abcd abcd| b\n  flow f[\"F\"]\n    c --> f\n  end\n  f@{ view: collapsed }")
        // Broken by `<br>`: 21 points apart; an edge's 14-point text wrapped at 120: 18 points apart; one line: 1.5 sizes.
        XCTAssertEqual(try node("a", in: laidOut).text.lineHeight, 21)
        XCTAssertEqual(try node("a", in: laidOut).frame.height, 66)
        let edgeText = try XCTUnwrap(laidOut.edges.first?.text)
        XCTAssertEqual(edgeText.lines.count, 2)
        XCTAssertEqual(edgeText.lineHeight, 18)
        XCTAssertEqual(try node("b", in: laidOut).text.lineHeight, 24)
        XCTAssertEqual(try node("f", in: laidOut).text.lineHeight, 24)
    }

    func testTheEdgesOnASideOfANodeMeetInItsMiddle() throws {
        // Pele's agent flow gives its nodes no span, so its edges are not spread along a side as a flowchart's are.
        for source in ["agentflow-beta TB\n  a --> b\n  a -.- c", "agentflow-beta TB\n  flow f\n    a --> b\n    a --> c\n  end"] {
            let laidOut = try layout(source)
            let task = try node("a", in: laidOut).frame
            XCTAssertEqual(laidOut.edges.map(\.path.start), [CGPoint(x: task.midX, y: task.maxY), CGPoint(x: task.midX, y: task.maxY)], source)
        }
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

    /// Pele's `overFills` and `edgeCasing`: `a --> b` inside the dark flow is drawn in white, its arrow too, and `b --x c`,
    /// which leaves it, runs over a casing 5 points wide of the page's color, painted between the flows and the edges.
    func testAnEdgeOnADarkFlowIsWhiteAndOneLeavingItIsCased() throws {
        let scene = DiagramScene(layout: try layout("agentflow-beta TB\n  flow f\n    a --> b\n  end\n  b --x c\n  style f fill:#222"))
        let casing = DiagramStroke.rounded(lineWidth: 5)
        XCTAssertEqual(scene.shapes.filter { shape in shape.part == .casing }.map(\.painting).first, .stroke(.background, casing))
        let edgePaints = scene.shapes.filter { shape in shape.part == .edge || shape.part == .marker }.map { shape -> DiagramPaint? in
            switch shape.painting {
            case .stroke(let paint, _), .fill(let paint): paint
            case .fillAndStroke(let paint, _, _): paint
            case .gradientFill: nil
            }
        }
        XCTAssertEqual(edgePaints.first, .color(SequenceTextInk.onDark))
        XCTAssertEqual(edgePaints[1], .color(SequenceTextInk.onDark))
        XCTAssertEqual(edgePaints.last, .line)
        let parts = scene.shapes.map(\.part)
        XCTAssertLessThan(try XCTUnwrap(parts.lastIndex(of: .cluster)), try XCTUnwrap(parts.firstIndex(of: .casing)))
        XCTAssertLessThan(try XCTUnwrap(parts.lastIndex(of: .casing)), try XCTUnwrap(parts.firstIndex(of: .edge)))
        let plain = DiagramScene(layout: try layout("agentflow-beta TB\n  flow f\n    a --> b\n  end\n  b --x c"))
        XCTAssertFalse(plain.shapes.contains { shape in shape.part == .casing })
    }

    /// Pele's `resolveStyle` gives a node's text its size, weight and slant, measured so and drawn so.
    func testAStyleSetsTheSizeTheWeightAndTheSlantOfANodesText() throws {
        let laidOut = try layout("agentflow-beta TB\n  a[\"abc\"]\n  b[\"abc\"]\n  style a font-size:20px,font-weight:bold,font-style:italic\n"
            + "  classDef big font-size:30px\n  class b big")
        let styled = try node("a", in: laidOut)
        XCTAssertEqual(styled.text.fontSize, 20)
        XCTAssertEqual(styled.text.lineHeight, 30)
        XCTAssertEqual(styled.text.size.width, 30)
        XCTAssertEqual(styled.frame.height, 54)
        XCTAssertTrue(styled.isBold)
        XCTAssertTrue(styled.isItalic)
        XCTAssertEqual(try node("b", in: laidOut).text.fontSize, 30)
        XCTAssertFalse(try node("b", in: laidOut).isBold)
        let text = try XCTUnwrap(DiagramScene(layout: laidOut).texts.first { text in text.part == .label })
        XCTAssertTrue(text.isBold)
        XCTAssertTrue(text.isItalic)
    }
}
