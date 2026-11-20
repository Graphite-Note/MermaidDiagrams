/**
 * File: UseCaseStylePaintingTests.swift
 * -------------------------------------
 * Layer: Tests
 * Description: A use case diagram's styles paint as Pele's SVG applies them: opacities on fills, outlines and lines,
 *              no casing under a line whose stroke is none, a stereotype and a JSON key drawn plain while a label
 *              takes its style's weight and slant, an edge's label too.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 19/11/2026
 */

import XCTest
@testable import MermaidDiagrams

final class UseCaseStylePaintingTests: XCTestCase {
    private func scene(_ lines: String...) throws -> DiagramScene {
        DiagramScene(layout: try UseCaseReading.uniformLayout((["usecase-beta"] + lines).joined(separator: "\n")))
    }

    private func shapes(_ scene: DiagramScene, _ part: DiagramScenePart) -> [DiagramSceneShape] {
        scene.shapes.filter { shape in shape.part == part }
    }

    /// `fill-opacity`, `stroke-opacity` and `opacity` are in the shape's style, which Pele writes on the shape.
    func testANodesOpacitiesApplyToItsFillAndOutline() throws {
        let scene = try scene("U(Use)", "style U fill:#ff0000,fill-opacity:0.5,stroke:#0000ff,stroke-opacity:0.4,opacity:0.5")
        let oval = try XCTUnwrap(shapes(scene, .node).first)
        XCTAssertEqual(oval.painting, .fillAndStroke(DiagramPaint.color(DiagramColor(red: 1, green: 0, blue: 0)).atOpacity(0.25),
                                                     DiagramPaint.color(DiagramColor(red: 0, green: 0, blue: 1)).atOpacity(0.2), DiagramStroke(lineWidth: 1)))
        let actor = try XCTUnwrap(shapes(try self.scene("actor A", "style A opacity:0.5"), .actorFigure).first)
        XCTAssertEqual(actor.painting, .fillAndStroke(DiagramPaint.surface.atOpacity(0.5), DiagramPaint.border.atOpacity(0.5), DiagramStroke(lineWidth: 1)))
    }

    /// A boundary's own `fill-opacity` takes the place of the half it otherwise shows of the alternate surface.
    func testABoundarysFillOpacityReplacesItsUsualHalf() throws {
        let boundary = try XCTUnwrap(shapes(try scene("systemBoundary S", "U", "end", "style S fill-opacity:0.2"), .cluster).first)
        XCTAssertEqual(boundary.painting, .fillAndStroke(DiagramPaint.alternateSurface.atOpacity(0.2), .border, DiagramStroke(lineWidth: 1)))
    }

    /// A line's style sets the opacity of the whole line, its stroke's opacity that of the line and its stroked marks.
    func testALinesOpacitiesApplyToTheLineAndItsMarks() throws {
        let scene = try scene("A e@--> B", "style e stroke:#00ff00,stroke-opacity:0.5,opacity:0.8")
        let green = DiagramPaint.color(DiagramColor(red: 0, green: 1, blue: 0))
        XCTAssertEqual(shapes(scene, .edge).first?.painting, .stroke(green.atOpacity(0.4), DiagramStroke(lineWidth: 1, lineCap: .round)))
        XCTAssertEqual(shapes(scene, .marker).first?.painting, .fill(green.atOpacity(0.8)))
    }

    /// Pele cases a line over a filled boundary's border as faint as the line, and not at all when its stroke is none.
    func testALineWithoutAStrokeHasNoCasing() throws {
        let filled = ["systemBoundary S", "U", "end", "style S fill:#eeeeee", "A e@--> U"]
        XCTAssertEqual(shapes(try scene(filled.joined(separator: "\n")), .casing).count, 2)
        XCTAssertEqual(shapes(try scene((filled + ["style e stroke:none"]).joined(separator: "\n")), .casing).count, 0)
        XCTAssertEqual(shapes(try scene((filled + ["style e stroke:transparent"]).joined(separator: "\n")), .casing).count, 0)
        let faint = shapes(try scene((filled + ["style e stroke-opacity:0.5"]).joined(separator: "\n")), .casing)
        XCTAssertEqual(faint.first?.painting, .stroke(DiagramPaint.background.atOpacity(0.5), DiagramStroke.rounded(lineWidth: 5)))
    }

    /// Pele measures a stereotype and a JSON key in their node's weight but writes its style only on the label.
    func testAStereotypeAndAKeyAreDrawnPlainWhileTheLabelIsBold() throws {
        let scene = try scene("actor A <<Role>>", "U(Use) <<Core>>", "json J@{\"k\": 1}", "classDef b font-weight:bold,font-style:italic", "class A,U,J b")
        for text in scene.texts {
            switch text.part {
            case .stereotype, .jsonKey: XCTAssertFalse(text.isBold || text.isItalic, "\(text.part)")
            case .label, .jsonValue: XCTAssertTrue(text.isBold && text.isItalic, "\(text.part)")
            default: break
            }
        }
        XCTAssertEqual(Set(scene.texts.map(\.part)), [.stereotype, .label, .jsonKey, .jsonValue])
    }

    /// An edge's style's weight and slant reach its label, as Pele writes the style on the label's text.
    func testAnEdgesLabelTakesItsStylesWeightAndSlant() throws {
        let scene = try scene("A e@-- go --> B", "style e font-weight:bold,font-style:italic")
        let label = try XCTUnwrap(scene.texts.first { text in text.part == .edgeLabel })
        XCTAssertTrue(label.isBold && label.isItalic)
    }
}
