/**
 * File: MindmapOutlineTests.swift
 * -------------------------------
 * Layer: Tests
 * Description: A mindmap turned to an outline running down for a column too narrow for it, as Pele turns it.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 19/11/2026
 */

import XCTest
@testable import MermaidDiagrams

/// Pele's mindmap outline, with text 8 points a character and 24 points a line.
final class MindmapOutlineTests: XCTestCase {
    private let accuracy: CGFloat = 0.01
    private let font = DiagramFont(postScriptName: nil, size: 16)
    private let tree = "mindmap\n Root\n  Alpha\n   one1\n   two2\n  Beta\n   tre3\n  Gama"
    private let wide = "mindmap\n Root[Root]\n  Alpha\n   alpha one is long\n   alpha two is long\n  Beta\n   beta one is long\n  Gamma\n   gamma one is long\n  Delta\n   delta one is long"

    private func layout(_ source: String, availableWidth: CGFloat?, title: String? = nil, autoDirectionBreakpoint: CGFloat? = nil) throws -> MindmapLayout {
        var diagram = try MindmapReading.mindmap(source)
        diagram.title = title
        return MindmapLayoutEngine.layout(diagram, measurer: UniformWidthTextMeasurer(), font: font, availableWidth: availableWidth)
    }

    func testAMapThatFitsOrAColumnOverTheBreakpointStaysSpreadToBothSides() throws {
        let map = try layout(tree, availableWidth: nil)
        XCTAssertEqual(try layout(tree, availableWidth: 640), map, "At the breakpoint across stays, whatever its width")
        XCTAssertEqual(try layout(tree, availableWidth: 2_000), map)
        XCTAssertEqual(try layout(tree, availableWidth: map.size.width), map, "It fits")
        XCTAssertEqual(try layout(tree, availableWidth: map.size.width + 1), map)
        XCTAssertLessThan(try layout(wide, availableWidth: 639).size.width, try layout(wide, availableWidth: nil).size.width, "Under 640 and too wide: an outline")
        XCTAssertEqual(try layout(wide, availableWidth: 640), try layout(wide, availableWidth: nil))
    }

    func testRowsFollowTheOrderOfTheNodesEachLevelSetInTwentyEightPointsMore() throws {
        let outline = try layout(tree, availableWidth: 200)
        let frames = outline.nodes.map(\.frame)
        XCTAssertEqual(outline.nodes.map(\.outline), [.stadium, .pill, .text, .text, .pill, .text, .text])
        for (index, depth) in [0, 1, 2, 2, 1, 2, 1].enumerated() {
            XCTAssertEqual(frames[index].minX - frames[0].minX, CGFloat(depth) * 28, accuracy: accuracy, "node \(index)")
        }
        XCTAssertEqual(frames[1].minY - frames[0].maxY, 20, accuracy: accuracy, "A row gap and the gap before a first-level branch")
        XCTAssertEqual(frames[2].minY - frames[1].maxY, 10, accuracy: accuracy)
        XCTAssertEqual(frames[3].minY - frames[2].maxY, 10, accuracy: accuracy)
        XCTAssertEqual(frames[4].minY - frames[3].maxY, 20, accuracy: accuracy)
        XCTAssertEqual(frames[6].minY - frames[5].maxY, 20, accuracy: accuracy)
        XCTAssertEqual(outline.size.height, (frames[6].maxY - frames[0].minY + 16).rounded(.up))
        for (a, b) in zip(frames, frames.dropFirst()) { XCTAssertLessThan(a.minY, b.minY) }
    }

    func testTheRootIsAStadiumUnlessItIsABox() throws {
        func root(_ written: String, availableWidth: CGFloat?) throws -> MindmapNodeOutline {
            try layout("mindmap\n \(written)\n  a long branch that is wider than the column\n   and another one that is as wide as that", availableWidth: availableWidth).nodes[0].outline
        }
        XCTAssertEqual(try root("root((Root))", availableWidth: 200), .stadium, "A circle or a cloud would stand wide of the trunk")
        XCTAssertEqual(try root("root[Root]", availableWidth: 200), .rectangle)
        XCTAssertEqual(try root("root(Root)", availableWidth: 200), .roundedRectangle)
        XCTAssertEqual(try root("root))Root((", availableWidth: 200), .stadium)
        XCTAssertEqual(try root("root)Root(", availableWidth: 200), .stadium)
        XCTAssertEqual(try root("root{{Root}}", availableWidth: 200), .stadium)
        XCTAssertEqual(try root("root((Root))", availableWidth: nil), .circle, "Spread to both sides it stays a circle")
    }

    func testLinksDropFromUnderTheirParentsLeftEndAndShareATrunk() throws {
        let outline = try layout(tree, availableWidth: 200)
        let frames = outline.nodes.map(\.frame)
        XCTAssertEqual(outline.edges.count, 6)
        let rootStem = min(max(12, frames[0].height / 2), 28 - 8)
        let first = outline.edges[0].path
        XCTAssertEqual(first.start.x, frames[0].minX + min(rootStem, frames[0].width / 2), accuracy: accuracy)
        XCTAssertEqual(first.start.y, frames[0].maxY, accuracy: accuracy)
        guard case .line(let toBend) = first.segments[0], case .curve(let turnEnd, _, _) = first.segments[1], case .line(let toNode) = first.segments[2] else {
            return XCTFail("A drop, a turn and a run in")
        }
        XCTAssertEqual(toBend, CGPoint(x: first.start.x, y: frames[1].midY - 8))
        XCTAssertEqual(turnEnd, CGPoint(x: first.start.x + 8, y: frames[1].midY))
        XCTAssertEqual(toNode, CGPoint(x: frames[1].minX, y: frames[1].midY), "A pill has no inset")
        // The link to Beta carries on down the trunk from where the one to Alpha turned in.
        XCTAssertEqual(outline.edges[3].path.start, CGPoint(x: first.start.x, y: frames[1].midY - 8))
        // A node's children hang from under its own left end, 12 points in, from its bottom.
        let toOne = outline.edges[1].path
        XCTAssertEqual(toOne.start.x, frames[1].minX + 12, accuracy: accuracy)
        XCTAssertEqual(toOne.start.y, frames[1].maxY, accuracy: accuracy)
        XCTAssertEqual(outline.edges[2].path.start.y, frames[2].midY - 8, accuracy: accuracy)
        XCTAssertEqual(outline.edges.map(\.branchIndex), [0, 0, 0, 1, 1, 2])
    }

    func testTheTurnShrinksWhereThereIsNoRoomForIt() throws {
        // The link to a child 28 points in, from a stem 12 in: 16 points across and at most 8 down.
        let outline = try layout("mindmap\n Root\n  A\n   b", availableWidth: 200)
        guard case .curve(let turnEnd, _, _) = outline.edges[1].path.segments[1] else { return XCTFail("A turn") }
        XCTAssertEqual(turnEnd.x - outline.edges[1].path.start.x, 8, accuracy: accuracy)
    }

    func testATextWrapsSoonerTheDeeperItIsAndNotUnderSeventyTwoPoints() throws {
        let source = "mindmap\n Root\n  Alpha\n   aaa bbb ccc ddd eee fff ggg hhh iii jjj kkk lll mmm"
        let outline = try layout(source, availableWidth: 300)
        // Room 300 - 16 = 284; a node two levels down has 284 - 56 - 12 = 216, but the map's own 200 is less.
        XCTAssertLessThanOrEqual(outline.nodes[2].text.size.width, 200)
        let narrower = try layout(source, availableWidth: 200)
        // Room 184; two levels down: 184 - 56 - 12 = 116.
        XCTAssertLessThanOrEqual(narrower.nodes[2].text.size.width, 116)
        XCTAssertGreaterThan(narrower.nodes[2].text.lines.count, outline.nodes[2].text.lines.count)
        let tiny = try layout(source, availableWidth: 100)
        XCTAssertLessThanOrEqual(tiny.nodes[2].text.size.width, 72, "Not under 72 points")
        XCTAssertGreaterThan(tiny.nodes[2].text.size.width, 40)
    }

    func testTheLinesOfATextDrawnAloneStartAtItsLeftAndTheOthersAreCentered() throws {
        let outline = try layout("mindmap\n Root\n  Alpha\n   aaa bbb ccc ddd eee fff\n   x[Boxed text of many words for a box]", availableWidth: 200)
        let leaf = outline.nodes[2]
        XCTAssertEqual(leaf.outline, .text)
        XCTAssertTrue(leaf.isTextLeftAligned)
        XCTAssertGreaterThan(leaf.text.lines.count, 1)
        let parts = MindmapDrawingParts(layout: outline)
        let leafLines = parts.nodeTexts.filter { block in leaf.text.lines.contains(block.lines[0]) && block.lines.count == 1 }
        XCTAssertEqual(leafLines.count, leaf.text.lines.count)
        for line in leafLines { XCTAssertEqual(line.center.x - line.size.width / 2, leaf.text.center.x - leaf.text.size.width / 2, accuracy: accuracy) }
        let boxed = outline.nodes[3]
        XCTAssertFalse(boxed.isTextLeftAligned)
        XCTAssertTrue(parts.nodeTexts.contains { block in block.lines == boxed.text.lines }, "A box keeps its lines centered")
        XCTAssertEqual(try layout(tree, availableWidth: nil).nodes.filter(\.isTextLeftAligned).count, 0)
    }

    func testTheTitleWrapsToTheColumnAndTheOutlineIsAsWideAsItsWidestRowOrTheTitle() throws {
        let titled = try layout(tree, availableWidth: 200, title: "A title that is far too long for a column of two hundred points")
        XCTAssertGreaterThan(titled.title?.lines.count ?? 0, 1)
        XCTAssertLessThanOrEqual(titled.title?.size.width ?? 0, 200 - 16 + accuracy)
        let plain = try layout(tree, availableWidth: 200)
        let widest = plain.nodes.map(\.frame.maxX).max()! - plain.nodes.map(\.frame.minX).min()!
        XCTAssertEqual(plain.size.width, (widest + 16).rounded(.up))
        XCTAssertEqual(try layout(tree, availableWidth: nil, title: "A title that is far too long for a column of two hundred points").title?.lines.count, 1,
                       "Without a column the title does not wrap")
    }

    func testAnOutlineHoldsEveryNodeInsideItsPageAndOverlapsNoOtherNode() throws {
        for width in [120, 200, 300, 500] as [CGFloat] {
            let outline = try layout(wide, availableWidth: width)
            let page = CGRect(origin: .zero, size: outline.size)
            for (index, node) in outline.nodes.enumerated() {
                XCTAssertTrue(page.contains(node.frame), "node \(index) in \(width)")
                for other in outline.nodes[(index + 1)...] { XCTAssertFalse(node.frame.intersects(other.frame), "\(index) and another in \(width)") }
            }
        }
    }

    func testAMindmapPreparedForTheNarrowestColumnHasAnOutlineScene() throws {
        let typography = DiagramTypography(font: font)
        let prepared = try MermaidDiagramPreparation.prepare(source: wide, typography: typography)
        let narrow = try XCTUnwrap(prepared.narrowScene)
        XCTAssertLessThan(narrow.size.width, prepared.scene.size.width)
        XCTAssertGreaterThan(narrow.size.height, prepared.scene.size.height, "As tall as it needs to be")
        XCTAssertTrue(prepared.showsNarrowScene(inColumnWidth: 350))
        XCTAssertNil(try MermaidDiagramPreparation.prepare(source: "mindmap\n Root\n  A", typography: typography).narrowScene, "No wider than the narrowest column")
    }
}
