/**
 * File: BlockEdgeInkTests.swift
 * -----------------------------
 * Layer: Tests
 * Description: Block diagram edges over composites a style fills, as Pele draws them: in the fill's ink when one holds
 *              them, on a page-colored casing where they cross a filled composite's border, plain elsewhere.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 19/11/2026
 */

import XCTest
@testable import MermaidDiagrams

final class BlockEdgeInkTests: XCTestCase {
    private func scene(_ source: String) throws -> DiagramScene {
        DiagramScene(layout: try BlockReading.uniformLayout(source))
    }

    /// The paint of each shape of `part`, in the order painted.
    private func paints(of part: DiagramScenePart, in scene: DiagramScene) -> [DiagramShapePainting] {
        scene.shapes.filter { shape in shape.part == part }.map(\.painting)
    }

    /// Pele draws `a --> b` inside the dark composite in white, and `b --o c`, which leaves it, over a casing 5 points
    /// wide of the page's color, its circle filled and outlined in that color, between the composite and the edges.
    func testAnEdgeOnADarkCompositeIsWhiteAndOneLeavingItIsCased() throws {
        let source = "block\n  columns 3\n  block:g:2\n    a b\n  end\n  c\n  a --> b\n  b --o c\n  style g fill:#222"
        let layout = try BlockReading.uniformLayout(source)
        XCTAssertEqual(BlockEdgeInk.inks(of: layout.edges, over: layout.composites), [.inked(SequenceTextInk.onDark), .cased])
        let scene = DiagramScene(layout: layout)
        let casing = DiagramStroke.rounded(lineWidth: 5)
        XCTAssertEqual(paints(of: .casing, in: scene), [.stroke(.background, casing), .fillAndStroke(.background, .background, casing)])
        XCTAssertEqual(paints(of: .edge, in: scene).map { painting -> DiagramPaint? in
            guard case .stroke(let paint, _) = painting else { return nil }
            return paint
        }, [.color(SequenceTextInk.onDark), .line])
        let parts = scene.shapes.map(\.part)
        XCTAssertLessThan(parts.lastIndex(of: .cluster)!, parts.firstIndex(of: .casing)!)
        XCTAssertLessThan(parts.lastIndex(of: .casing)!, parts.firstIndex(of: .edge)!)
    }

    /// A light fill gives the dark ink; an edge between two filled composites crosses both borders and is cased; a fill
    /// under half opacity, whose ink Pele cannot pick, casings an edge it holds; a thick edge's casing is 6.5 wide.
    func testInksFollowTheFillUnderTheEdge() throws {
        func inks(_ source: String) throws -> [BlockEdgeInk] {
            let layout = try BlockReading.uniformLayout(source)
            return BlockEdgeInk.inks(of: layout.edges, over: layout.composites)
        }
        XCTAssertEqual(try inks("block\n  block:g\n    a b\n  end\n  a --> b\n  style g fill:#eeeeee"), [.inked(SequenceTextInk.onLight)])
        XCTAssertEqual(try inks("block\n  columns 2\n  block:g\n    a\n  end\n  block:h\n    b\n  end\n  a --x b\n  style g fill:#eee\n  style h fill:#ffffff40"),
                       [.cased])
        XCTAssertEqual(try inks("block\n  block:g\n    a b\n  end\n  a --> b\n  style g fill:#00000040"), [.cased])
        XCTAssertEqual(try inks("block\n  block:g\n    a b\n  end\n  c\n  a --> b\n  b --> c"), [.plain, .plain])
        XCTAssertEqual(try inks("block\n  block:g\n    a\n  end\n  c d\n  c --> d\n  style g fill:#222"), [.plain])
        let thick = try scene("block\n  block:g\n    a\n  end\n  c\n  a ==> c\n  style g fill:#222")
        XCTAssertEqual(paints(of: .casing, in: thick).first, .stroke(.background, .rounded(lineWidth: 6.5)))
    }

    /// The innermost filled composite holding the edge gives its ink.
    func testTheInnermostFillHoldingTheEdgeGivesItsInk() throws {
        let layout = try BlockReading.uniformLayout("block\n  block:outer\n    block:inner\n      a b\n    end\n  end\n  a --> b\n  style outer fill:#222\n  style inner fill:#eee")
        XCTAssertEqual(BlockEdgeInk.inks(of: layout.edges, over: layout.composites), [.inked(SequenceTextInk.onLight)])
    }
}
