/**
 * File: FlowchartNodeAssetTests.swift
 * -----------------------------------
 * Layer: Tests
 * Description: Flowchart nodes written as icons and pictures read, sized, placed and framed as Pele's flowchart reads,
 *              sizes, places and frames them.
 *
 * Authors: Bahey Shalash
 * Version: 0.2
 * Date: 23/11/2026
 */

import CoreGraphics
import XCTest
@testable import MermaidDiagrams

/// Text is 8 points a character here (`UniformWidthLayout`), lines 24 points high; Pele's numbers follow from its
/// flowchart/render.ts with those widths.
final class FlowchartNodeAssetTests: XCTestCase {
    func testAnIconsAttributesAreReadAndItsIdentifierIsNotItsLabel() throws {
        let diagram = try FlowchartReading.flowchart("flowchart TD\n  A@{ icon: \"fa:user\", form: \"square\", label: \"User Icon\", pos: \"t\", h: 60 }\n  B@{ icon: fa:bell }")
        let user = try XCTUnwrap(diagram.nodes[0].asset)
        XCTAssertEqual(user.kind, .icon(name: "fa:user"))
        XCTAssertEqual(user.form, .square)
        XCTAssertTrue(user.isLabelAbove)
        XCTAssertEqual(user.writtenHeight, 60)
        XCTAssertNil(user.writtenWidth)
        XCTAssertEqual(diagram.nodes[0].label.lines, ["User Icon"])
        XCTAssertEqual(diagram.nodes[1].label.lines, [""], "An icon without a label of its own shows no identifier, as in Pele")
        XCTAssertEqual(diagram.nodes[1].asset?.form, FlowchartNodeAsset.Form.none)
    }

    func testAPictureWinsOverAnIconAndLaterAttributesAddToEarlierOnes() throws {
        let diagram = try FlowchartReading.flowchart("flowchart TD\n  A[Shown]@{ icon: \"fa:x\" }\n  A@{ form: circle, h: 4001, w: wide }\n  B@{ img: \"pic.png\", icon: \"fa:y\", constraint: on }")
        let icon = try XCTUnwrap(diagram.nodes[0].asset)
        XCTAssertEqual(icon.form, .circle)
        XCTAssertNil(icon.writtenHeight, "Past 4,000 points a side is not taken, as Pele's assetSize")
        XCTAssertNil(icon.writtenWidth, "Words are no number")
        XCTAssertEqual(diagram.nodes[0].label.lines, ["Shown"], "A label written in brackets stays")
        XCTAssertEqual(diagram.nodes[1].asset?.kind, .image(address: "pic.png"))
        XCTAssertEqual(diagram.nodes[1].asset?.keepsProportions, true)
    }

    /// Pele's database keeps an attribute whose YAML value is truthy (`if (doc.w)`), under its key as written.
    func testAFalsyValueLeavesTheAttributeBeforeItAndKeysAreReadAsWritten() throws {
        let diagram = try FlowchartReading.flowchart(
            "flowchart TD\n  A@{ icon: \"fa:x\", w: 100, h: 70 }\n  A@{ w: 0, h: \"0\", form: null }\n  B@{ Icon: \"fa:y\" }\n  C@{ icon: \"fa:z\", form: circle }\n  C@{ form: false }")
        let icon = try XCTUnwrap(diagram.nodes[0].asset)
        XCTAssertEqual(icon.writtenWidth, 100, "An unquoted zero is false: the width written before stays")
        XCTAssertNil(icon.writtenHeight, "A quoted zero is a text, true: it replaces the height, and is no side")
        XCTAssertNil(diagram.nodes[1].asset, "`Icon` is not Pele's `icon`")
        XCTAssertEqual(diagram.nodes[2].asset?.form, .circle)
    }

    func testAnIconNodeStacksItsBoxAndItsLabelAsPeleDoes() throws {
        let layout = try UniformWidthLayout.layout("flowchart TD\n  A@{ icon: \"fa:user\", form: \"square\", label: \"User Icon\", pos: \"t\", h: 60 }")
        let node = try XCTUnwrap(layout.nodes.first)
        // As wide as the label (9 characters) and 4 points each side, past the 48-point box; the box, 6 points and the label.
        XCTAssertEqual(node.frame.size, CGSize(width: 9 * 8 + 8, height: 60 + 6 + 24))
        XCTAssertEqual(node.text.center.y - node.frame.midY, -30, "The label above: half the box above the node's middle")
        let asset = try XCTUnwrap(node.asset)
        let box = asset.box(in: node.frame, hasLabel: true)
        XCTAssertEqual(box, CGRect(x: node.frame.midX - 30, y: node.frame.maxY - 60, width: 60, height: 60))
        XCTAssertEqual(FlowchartNodeAssetDrawing.frame(of: asset, in: node)?.boundingBoxOfPath, box)
    }

    func testAPictureNodeIsEightyPointsWideAndIsDrawnWithNoOutline() throws {
        let layout = try UniformWidthLayout.layout("flowchart TD\n  A@{ img: \"pic.png\", label: \"Hi\", h: 60 }")
        let node = try XCTUnwrap(layout.nodes.first)
        XCTAssertEqual(node.frame.size, CGSize(width: 80, height: 60 + 6 + 24))
        XCTAssertEqual(node.text.center.y - node.frame.midY, 30, "The label below")
        XCTAssertNil(FlowchartNodeAssetDrawing.frame(of: try XCTUnwrap(node.asset), in: node))
    }

    func testAnIconWithoutALabelIsItsBoxAlone() throws {
        let layout = try UniformWidthLayout.layout("flowchart TD\n  A@{ icon: \"fa:bell\", form: circle }")
        let node = try XCTUnwrap(layout.nodes.first)
        XCTAssertEqual(node.frame.size, CGSize(width: 48, height: 48))
        XCTAssertTrue(node.text.lines.isEmpty)
        let frame = try XCTUnwrap(FlowchartNodeAssetDrawing.frame(of: try XCTUnwrap(node.asset), in: node))
        XCTAssertEqual(frame.boundingBoxOfPath, node.frame)
        XCTAssertFalse(frame.contains(CGPoint(x: node.frame.minX + 2, y: node.frame.minY + 2)), "A circle, not a square")
    }

    func testEdgesMeetAnIconAtTheMiddleOfItsSide() throws {
        let layout = try UniformWidthLayout.layout("flowchart TD\n  A --> I\n  B --> I\n  C --> I\n  I@{ icon: \"fa:x\", form: square }")
        let icon = try XCTUnwrap(layout.nodes.first { node in node.asset != nil })
        let ends = layout.edges.map { edge in edge.path.allPoints.last ?? .zero }
        XCTAssertEqual(ends.count, 3)
        for end in ends { XCTAssertEqual(end.x, icon.frame.midX, accuracy: 0.01, "Pele gives an icon no span: every end at the side's middle") }
    }

    func testTheSceneDrawsTheFrameAndTheLabelOnly() throws {
        let prepared = try MermaidDiagramPreparation.prepare(source: "flowchart TD\n  A@{ icon: \"fa:user\", form: rounded, label: \"User\" }",
                                                            typography: DiagramTypography(font: DiagramFont(postScriptName: "ArialMT", size: 16)),
                                                            narrowestColumnWidth: nil)
        XCTAssertEqual(prepared.scene.texts.map(\.block.lines), [["User"]])
        let nodeShapes = prepared.scene.items.compactMap { item -> DiagramSceneShape? in
            guard case .shape(let shape) = item, shape.part == .node else { return nil }
            return shape
        }
        XCTAssertFalse(nodeShapes.isEmpty)
        XCTAssertEqual(nodeShapes[0].path.boundingBoxOfPath.size, CGSize(width: 48, height: 48))
    }
}
