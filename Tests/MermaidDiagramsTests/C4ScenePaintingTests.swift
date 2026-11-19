/**
 * File: C4ScenePaintingTests.swift
 * --------------------------------
 * Layer: Tests
 * Description: A C4 diagram's scene in Pele's order and paints (render.ts): each text of a boundary, a shape and a
 *              relation's label in its color, frames and outlines dashed as Pele dashes them; and labels placed as Pele
 *              places them, kept off the labels placed before and slid toward their start first.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 20/11/2026
 */

import XCTest
@testable import MermaidDiagrams

final class C4ScenePaintingTests: XCTestCase {
    private let source = """
        C4Context
        title The title
        Boundary(b, "Boundary", "Kind", $descr="about b") {
          Container(c, "Container", "Tech", "about c")
        }
        System_Ext(e, "External")
        Deployment_Node(n, "Node") {
          System(s, "System")
        }
        Rel(c, e, "uses", "HTTPS")
        """

    /// render.ts: a shape's kind and technology in the muted color, its name in bold and its description in the text
    /// color; a boundary's name in bold, its type and description muted; a label in the text color, its technology muted
    /// and in italic.
    func testEachTextIsPaintedInPelesColor() throws {
        let scene = DiagramScene(layout: try C4Reading.uniformLayout(source))
        func paints(_ part: DiagramScenePart) -> [String] {
            scene.texts.filter { text in text.part == part }.map { text in
                "\(text.block.lines.joined(separator: " ")): \(text.paint == .foreground ? "foreground" : text.paint == .muted ? "muted" : "other")\(text.isBold ? " bold" : "")\(text.isItalic ? " italic" : "")"
            }
        }
        XCTAssertEqual(paints(.title), ["The title: foreground bold"])
        XCTAssertEqual(paints(.clusterLabel), ["Boundary: foreground bold", "Node: foreground bold"])
        XCTAssertEqual(paints(.c4Type), ["[Kind]: muted", "[node]: muted", "«external system»: muted", "«container»: muted", "«system»: muted"])
        XCTAssertEqual(paints(.c4Description), ["about b: muted", "about c: foreground"])
        XCTAssertEqual(paints(.label), ["External: foreground bold", "Container: foreground bold", "System: foreground bold"])
        XCTAssertEqual(paints(.c4Technology), ["[Tech]: muted", "[HTTPS]: muted italic"])
        XCTAssertEqual(paints(.edgeLabel), ["uses: foreground"])
    }

    /// A boundary's frame dashed 6 4 and a deployment node's solid; a shape filled in the surface color, an external one
    /// (drawn first, as it is in the top level) in the page's color and dashed 4 3.
    func testFramesAndOutlinesAreFilledAndDashedAsPeleDrawsThem() throws {
        let scene = DiagramScene(layout: try C4Reading.uniformLayout(source))
        let frames = scene.shapes.filter { shape in shape.part == .cluster }.map(\.painting)
        XCTAssertEqual(frames, [.stroke(.border, DiagramStroke(lineWidth: 1, dashLengths: [6, 4])), .stroke(.border, DiagramStroke(lineWidth: 1))])
        let outlines = scene.shapes.filter { shape in shape.part == .node }.map(\.painting)
        XCTAssertEqual(outlines, [.fillAndStroke(.background, .border, DiagramStroke(lineWidth: 1, dashLengths: [4, 3])),
                                  .fillAndStroke(.surface, .border, DiagramStroke(lineWidth: 1)),
                                  .fillAndStroke(.surface, .border, DiagramStroke(lineWidth: 1))])
    }

    /// Pele's SVG from back to front: the title, the boundaries with their headings, the lines and arrowheads, the shapes
    /// with their texts (boundary by boundary from the top level, so the external system first), then the labels on
    /// their patches.
    func testTheSceneIsInPelesOrder() throws {
        let parts = DiagramScene(layout: try C4Reading.uniformLayout(source)).items.map { item in
            switch item {
            case .shape(let shape): shape.part
            case .text(let text): text.part
            }
        }
        var layers: [DiagramScenePart] = []
        for part in parts where layers.last != part { layers.append(part) }
        XCTAssertEqual(layers, [.title, .cluster, .clusterLabel, .c4Type, .c4Description, .cluster, .clusterLabel, .c4Type, .edge, .marker,
                                .node, .c4Type, .label, .node, .c4Type, .label, .c4Technology, .c4Description, .node, .c4Type, .label,
                                .labelBackground, .edgeLabel, .c4Technology])
    }

    /// Two lines that cross at their middles: the second label keeps off the first, and of the places as near the middle
    /// as each other it takes the one toward its start (Pele's slide: 0.5, 0.4, 0.6, …).
    func testALabelKeepsOffTheLabelsBeforeItAndSlidesTowardItsStartFirst() throws {
        let layout = try C4Reading.uniformLayout("""
            C4Context
            UpdateLayoutConfig("2")
            System(a, "A")
            System(b, "B")
            System(c, "C")
            System(d, "D")
            Rel(a, d, "first")
            Rel(b, c, "second")
            """)
        let first = try XCTUnwrap(layout.relation("a", "d"))
        let second = try XCTUnwrap(layout.relation("b", "c"))
        let firstFrame = try XCTUnwrap(first.labelFrame)
        let secondFrame = try XCTUnwrap(second.labelFrame)
        XCTAssertFalse(firstFrame.intersects(secondFrame))
        func distance(_ point: CGPoint, _ other: CGPoint) -> CGFloat { hypot(point.x - other.x, point.y - other.y) }
        let start = try XCTUnwrap(second.corners.first)
        let end = try XCTUnwrap(second.corners.last)
        let center = CGPoint(x: secondFrame.midX, y: secondFrame.midY)
        XCTAssertLessThan(distance(center, start), distance(center, end))
    }
}
