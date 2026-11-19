/**
 * File: BlockLayoutEngineTests.swift
 * ----------------------------------
 * Layer: Tests
 * Description: Block diagrams laid out as Pele lays them out, the relations of its render tests (tests/render/
 *              block.test.ts) and numbers worked out by hand from layout.ts and render.ts with text half its size wide.
 *
 * Authors: Bahey Shalash
 * Version: 0.2
 * Date: 19/11/2026
 */

import XCTest
@testable import MermaidDiagrams

final class BlockLayoutEngineTests: XCTestCase {
    private func frames(_ source: String) throws -> [String: CGRect] {
        BlockReading.frames(try BlockReading.uniformLayout(source))
    }

    /// `a`: its text 8 by 24, a rectangle 48 by 48 (36 points across its text, at least 48; 24 down), the page 8 points
    /// round it.
    func testOneBlockIsARectangleOnItsPage() throws {
        let layout = try BlockReading.uniformLayout("block\n a")
        XCTAssertEqual(layout.size, CGSize(width: 64, height: 64))
        XCTAssertEqual(layout.nodes.first?.frame, CGRect(x: 8, y: 8, width: 48, height: 48))
        XCTAssertEqual(layout.nodes.first?.text?.center, CGPoint(x: 32, y: 32))
    }

    func testBlocksGoOnOneRowWithoutAColumnCountAndWrapAfterIt() throws {
        let row = try frames("block\n  a b c")
        XCTAssertEqual(row["a"]?.midY, row["c"]?.midY)
        XCTAssertEqual(row["b"]!.midX - row["a"]!.midX, row["c"]!.midX - row["b"]!.midX)
        XCTAssertEqual(row["b"]!.midX - row["a"]!.midX, 48 + 12)
        let wrapped = try frames("block\n  columns 3\n  a b c d")
        XCTAssertEqual(wrapped["d"]?.midX, wrapped["a"]?.midX)
        XCTAssertGreaterThan(wrapped["d"]!.midY, wrapped["a"]!.midY)
    }

    func testEveryColumnIsAsWideAsTheWidestAndEveryRowAsTallAsTheTallest() throws {
        let grid = try frames("block\n  columns 2\n  a[\"A much longer label\"] b\n  c[\"two<br>lines\"] d")
        for name in ["b", "c", "d"] { XCTAssertEqual(grid[name]?.size, grid["a"]?.size, name) }
        XCTAssertEqual(grid["a"]?.width, 19 * 8 + 36)
        // Two lines broken by `<br>` are set 1.3 times the size apart (21 points), as Pele sets every text of several
        // lines: the rows are 66 points high in Pele's drawing of this diagram, not 72.
        XCTAssertEqual(grid["a"]?.height, 2 * 21 + 24)
    }

    /// An edge's text of two lines is 2 times 18 points high (1.3 times its 14 points), so the edges between `a` and `b`,
    /// spread apart by their texts, stand where Pele draws them: 26 and 49 points down a page 75 points high.
    func testEdgeTextsOfSeveralLinesAreSetCloser() throws {
        let layout = try BlockReading.uniformLayout("block\n  a[\"Left layer\"] space:3 b[\"Right layer\"]\n"
            + "  a -- \"12 production<br>conforming\" --> b\n  b -- \"12 production<br>deviation\" --> a")
        XCTAssertEqual(layout.size, CGSize(width: 684, height: 75))
        XCTAssertEqual(layout.edges.map { edge in edge.path.start.y }, [26, 49])
        XCTAssertEqual(layout.edges.compactMap { edge in edge.text?.frame.height }, [36, 36])
    }

    func testSpansTakeTheGapsBetweenTheirColumnsAndStopAtTheLastColumn() throws {
        let spans = try frames("block\n  columns 3\n  a[\"A label\"] b:2 c:2 d")
        let a = spans["a"]!
        XCTAssertEqual(spans["b"]?.width, 2 * a.width + 12)
        XCTAssertEqual(spans["c"]!.midX, a.midX + (a.width + 12) / 2, accuracy: 0.01)
        XCTAssertEqual(spans["d"]!.midX, a.midX + 2 * (a.width + 12), accuracy: 0.01)
        XCTAssertEqual(spans["d"]?.midY, spans["c"]?.midY)
        let stopped = try frames("block\n  columns 3\n  a b:3 c")
        XCTAssertEqual(stopped["b"]?.width, 2 * stopped["a"]!.width + 12)
        XCTAssertEqual(stopped["c"]?.midX, stopped["a"]?.midX)
        let none = try frames("block\n  a:0 b")
        XCTAssertEqual(none["a"]?.width, none["b"]?.width)
    }

    func testSpacesKeepTheirCells() throws {
        let spaced = try frames("block\n  columns 3\n  a space b\n  c d e")
        XCTAssertEqual(spaced["b"]?.midX, spaced["e"]?.midX)
        XCTAssertEqual(spaced["d"]?.midX, (spaced["a"]!.midX + spaced["b"]!.midX) / 2)
        let wide = try frames("block\n  ida space:3 idb idc")
        let step = wide["idc"]!.midX - wide["idb"]!.midX
        XCTAssertEqual(wide["idb"]!.midX - wide["ida"]!.midX, 4 * step, accuracy: 0.1)
        XCTAssertEqual(try BlockReading.uniformLayout("block\n  a space b").nodes.count, 2)
    }

    func testACompositeHoldsItsChildrenInsideItsGapAndUsesItsOwnColumns() throws {
        let laidOut = try frames("block\n  columns 1\n  top\n  block:group\n    columns 2\n    a b c d\n  end")
        let group = laidOut["group"]!
        for name in ["a", "b", "c", "d"] { XCTAssertTrue(group.insetBy(dx: 12, dy: 12).contains(laidOut[name]!), name) }
        XCTAssertEqual(laidOut["c"]?.midX, laidOut["a"]?.midX)
        XCTAssertEqual(laidOut["top"]?.width, group.width)
    }

    /// Rows with a plain block are as tall as the tallest block; rows of composites as tall as they need.
    func testRowsOfCompositesAreAsTallAsTheyNeed() throws {
        let laidOut = try frames("block\n  columns 3\n  a:3\n  block:group1:2\n    columns 2\n    h i j k\n  end\n  g\n  block:group2:3\n    l m n o p q r\n  end")
        let plain = try frames("block\n  l")["l"]!.height
        XCTAssertEqual(laidOut["group1"]?.height, 2 * plain + 3 * 12)
        XCTAssertEqual(laidOut["a"]?.height, laidOut["group1"]?.height)
        XCTAssertEqual(laidOut["g"]?.height, laidOut["group1"]?.height)
        XCTAssertEqual(laidOut["group2"]?.height, plain + 2 * 12)
        XCTAssertEqual(laidOut["l"]?.height, plain)
        XCTAssertEqual(laidOut["group2"]?.width, laidOut["a"]?.width)
    }

    func testACompositeTitleIsDrawnAboveItsChildren() throws {
        let layout = try BlockReading.uniformLayout("block\n  block:g[\"Group title\"]\n    a b\n  end")
        let composite = layout.composites[0]
        let a = BlockReading.frames(layout)["a"]!
        XCTAssertLessThan(composite.title!.center.y, a.minY)
        // The title's band (24 + 4) and the gap: its center (28 + 12) / 2 + 2 below the box's top.
        XCTAssertEqual(composite.title!.center.y - composite.frame.minY, 22)
        XCTAssertGreaterThan(composite.frame.height, try frames("block\n  block:g\n    a b\n  end")["g"]!.height)
    }

    func testPaddingSetsTheGap() throws {
        let tight = try BlockReading.uniformLayout("---\nconfig:\n  block:\n    padding: 2\n---\nblock\n  a b c")
        let loose = try BlockReading.uniformLayout("---\nconfig:\n  block:\n    padding: 40\n---\nblock\n  a b c")
        XCTAssertEqual(loose.size.width - tight.size.width, 2 * 38)
    }

    func testCirclesAndDiamondsKeepTheirOwnSizeInALargerCell() throws {
        let laidOut = try frames("block\n  columns 1\n  a((\"x\"))\n  b[\"A much wider block than the circle\"]")
        XCTAssertLessThan(laidOut["a"]!.width, laidOut["b"]!.width / 2)
        XCTAssertEqual(laidOut["a"]!.width, laidOut["a"]!.height)
    }

    /// Pele's point counts of each arrow's polygon.
    func testBlockArrowsHaveTheirPointsInEveryDirection() throws {
        func corners(_ directions: String) throws -> Int {
            guard case .arrow(let corners) = try BlockReading.uniformLayout("block\n  a<[\"Label\"]>(\(directions))").nodes[0].form else { return 0 }
            return corners.count
        }
        for direction in ["right", "left", "up", "down"] { XCTAssertEqual(try corners(direction), 7, direction) }
        XCTAssertEqual(try corners("x"), 10)
        XCTAssertEqual(try corners("y"), 10)
        XCTAssertEqual(try corners("x, down"), 13)
        XCTAssertEqual(try corners("x, y"), 16)
        XCTAssertEqual(try corners("up, up"), 7)
        XCTAssertEqual(try corners(" up "), 7)
        let labelled = try BlockReading.uniformLayout("block\n  a<[\"Label\"]>(right)")
        let blank = try BlockReading.uniformLayout("block\n  a<[\"&nbsp;&nbsp;&nbsp;\"]>(right)")
        XCTAssertLessThan(blank.size.height, labelled.size.height)
    }

    /// A right arrow round `Label` (40 by 24): 52 + 20 wide, 32 + 14 tall, its text 10 points left of its center.
    func testARightArrowIsSizedRoundItsText() throws {
        let node = try BlockReading.uniformLayout("block\n  a<[\"Label\"]>(right)").nodes[0]
        XCTAssertEqual(node.frame.size, CGSize(width: 72, height: 46))
        XCTAssertEqual(node.text!.center.x - node.frame.midX, -10)
    }

    func testEdgesInARowOrAColumnRunStraightBetweenTheBorders() throws {
        let layout = try BlockReading.uniformLayout("block\n  a space b\n  a --> b")
        let laidOut = BlockReading.frames(layout)
        let edge = layout.edges[0]
        XCTAssertEqual(edge.path.start, CGPoint(x: laidOut["a"]!.maxX, y: laidOut["a"]!.midY))
        guard case .line(let end) = edge.path.segments.last else { return XCTFail("a line") }
        XCTAssertEqual(end, CGPoint(x: laidOut["b"]!.minX - 7, y: laidOut["b"]!.midY))
        XCTAssertEqual(edge.targetMark?.tip, CGPoint(x: laidOut["b"]!.minX, y: laidOut["b"]!.midY))
        XCTAssertNil(edge.sourceMark)
    }

    func testEdgesBetweenBlocksThatShareNeitherBendOnce() throws {
        let layout = try BlockReading.uniformLayout("block\n  columns 2\n  a space\n  space b\n  a --> b")
        XCTAssertEqual(layout.edges[0].path.segments.count, 3)
    }

    func testASelfLoopIsAnArcRoundTheTopRightCorner() throws {
        let layout = try BlockReading.uniformLayout("block\n  a\n  a --> a")
        let frame = BlockReading.frames(layout)["a"]!
        XCTAssertFalse(layout.edges[0].path.segments.isEmpty)
        XCTAssertEqual(layout.edges[0].targetMark!.tip.x, frame.maxX, accuracy: 0.01)
    }

    /// Labels of edges between the same two blocks are stacked apart, and the gap widened when they do not fit.
    func testLabelsOfParallelEdgesAreSeparated() throws {
        let layout = try BlockReading.uniformLayout("block\n  A space B\n  A -- \"one\" --> B\n  A -- \"two\" --> B")
        let texts = layout.edges.compactMap(\.text)
        XCTAssertEqual(texts.count, 2)
        XCTAssertFalse(texts[0].frame.insetBy(dx: -4, dy: 0).intersects(texts[1].frame.insetBy(dx: -4, dy: 0)))
    }

    func testAZeroColumnCountIsRefused() {
        XCTAssertThrowsError(try BlockReading.uniformLayout("block\n  columns 0\n  a")) { error in
            XCTAssertEqual(error as? BlockLayoutError, .columnsNotAnInteger)
        }
    }

    func testAWiderCellWrapsASpanningBlocksTextLess() throws {
        let text = "Something long long long long long long"
        let layout = try BlockReading.uniformLayout("block\n  1[\"Something\"]\n  2[\"\(text)\"]:2\n  3[\"\(text)\"]:5\n  4[\"\(text)\"]:2\n  5[\"Something\"]")
        let texts = Dictionary(uniqueKeysWithValues: layout.nodes.map { node in (node.identifier, node.text!) })
        XCTAssertEqual(texts["3"]?.lines, [text])
        XCTAssertEqual(texts["2"]?.lines.count, 2)
    }

    func testStylesSetColorsAndTheTextColorContrastsWithAFill() throws {
        let layout = try BlockReading.uniformLayout("block\n  a b\n  style a fill:#000\n  classDef light fill:#fff,stroke:#f00\n  class b light")
        let appearances = Dictionary(uniqueKeysWithValues: layout.nodes.map { node in (node.identifier, node.appearance) })
        XCTAssertEqual(appearances["a"]?.textColor, SequenceTextInk.onDark)
        XCTAssertEqual(appearances["b"]?.textColor, SequenceTextInk.onLight)
        XCTAssertEqual(appearances["b"]?.style.stroke, DiagramColor(red: 1, green: 0, blue: 0))
        let bold = try BlockReading.uniformLayout("block\n  a\n  style a font-weight:bold,font-size:20px")
        XCTAssertEqual(bold.nodes[0].appearance.isBold, true)
        XCTAssertEqual(bold.nodes[0].text?.fontSize, 20)
    }

    func testATightLayoutIsNarrower() throws {
        let source = "block\n  a[\"A label of some length here\"] b[\"Another label of some length\"] c[\"And a third label\"]"
        let loose = try BlockReading.uniformLayout(source)
        let tight = try BlockReading.uniformLayout(source, availableWidth: 300, isTight: true)
        XCTAssertLessThan(tight.size.width, loose.size.width)
    }

    func testTheSceneHoldsPelesParts() throws {
        let layout = try BlockReading.uniformLayout("---\ntitle: Blocks\n---\nblock\n  block:g[\"G\"]\n    a\n  end\n  b\n  a -- \"x\" --> b")
        let parts = DiagramScene(layout: layout).items.map { item -> DiagramScenePart in
            switch item {
            case .shape(let shape): shape.part
            case .text(let text): text.part
            }
        }
        var seen: [DiagramScenePart] = []
        for part in parts where seen.last != part { seen.append(part) }
        XCTAssertEqual(seen, [.title, .cluster, .clusterLabel, .edge, .marker, .node, .label, .node, .label, .labelBackground, .edgeLabel])
    }

    /// Pele writes only the last declaration of a property and the browser drops it when its value is not CSS, so a
    /// later `fill:bad` leaves the block in the surface color, not in the earlier red; a later `style` replaces an
    /// earlier one, as Pele draws them.
    func testALaterValueThatIsNotReadLeavesThePropertyUnset() throws {
        func appearance(_ source: String) throws -> BlockAppearance? {
            try BlockReading.uniformLayout(source).nodes.first?.appearance
        }
        let dropped = try appearance("block\n  a\n  style a fill:#f00,stroke:#00f,fill:bad")
        XCTAssertNil(dropped?.style.fill)
        XCTAssertEqual(dropped?.style.stroke, DiagramColor(red: 0, green: 0, blue: 1))
        XCTAssertNil(try appearance("block\n  classDef hot fill:#f00\n  a\n  class a hot\n  style a fill:notacolor")?.style.fill)
        XCTAssertNil(try appearance("block\n  a\n  style a stroke-width:4px;stroke-width:wide")?.style.strokeWidth)
        let replaced = try appearance("block\n  a\n  style a fill:#f00\n  style a stroke:#00f")
        XCTAssertNil(replaced?.style.fill)
        XCTAssertEqual(replaced?.style.stroke, DiagramColor(red: 0, green: 0, blue: 1))
    }

    /// Pele's `tighten` for a column of 1 point: laid out within it, the widened gap between the arrow and `n2` is given
    /// back, and the drawing (178 points, as wide as its widest text) is no wider than the tight one, so Pele keeps it:
    /// the blocks stand 80 points apart, not the tight drawing's 74.
    func testANarrowColumnKeepsTheFittedLayoutWhenTightIsNoNarrower() throws {
        let source = "block-beta\n  columns 5\n  ar1<[\"go\"]>(x, right)\n  n2\n"
            + "  ar1 -- \"sit amet consectetur adipiscing elit sed do eiusmod\" --> n2\n  ar1 ==> n2\n  ar1 -- \"A\" ==> n2\n  ar1 --o n2"
        XCTAssertEqual(try BlockReading.uniformLayout(source).size.width, 349)
        let narrow = try BlockLayoutEngine.narrowLayout(try BlockReading.block(source), measurers: BlockReading.measurers,
                                                        font: DiagramFont(postScriptName: nil, size: 16), width: 1)
        let frames = BlockReading.frames(narrow)
        XCTAssertEqual(narrow.size, CGSize(width: 178, height: 84))
        XCTAssertEqual(frames["n2"]!.midX - frames["ar1"]!.midX, 80)
        let tight = try BlockReading.uniformLayout(source, availableWidth: 1, isTight: true)
        XCTAssertEqual(BlockReading.frames(tight)["n2"]!.midX - BlockReading.frames(tight)["ar1"]!.midX, 74)
    }
}
