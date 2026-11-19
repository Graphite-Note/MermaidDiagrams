/**
 * File: BlockParserTests.swift
 * ----------------------------
 * Layer: Tests
 * Description: The inputs of Mermaid 12.1.0's block specs (block.spec.ts, blockColorIndex.spec.ts and blockDB.spec.ts,
 *              as Pele ports them in tests/compat/block), Pele's own reading rules, the errors with their lines and the
 *              limits.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 19/11/2026
 */

import XCTest
@testable import MermaidDiagrams

final class BlockParserTests: XCTestCase {
    private func top(_ source: String) throws -> [BlockDiagramBlock] {
        BlockReading.topBlocks(try BlockReading.block(source))
    }

    func testANodeTakesItsIdentifierAsItsText() throws {
        let blocks = try top("block-beta\n          id\n      ")
        XCTAssertEqual(blocks.map(\.identifier), ["id"])
        XCTAssertEqual(blocks[0].label, "id")
        XCTAssertEqual(blocks[0].kind, .unshaped)
    }

    func testANodeWithASquareShapeAndALabel() throws {
        let blocks = try top("block\n          id[\"A label\"]\n          id2")
        XCTAssertEqual(blocks.map(\.identifier), ["id", "id2"])
        XCTAssertEqual(blocks[0].label, "A label")
        XCTAssertEqual(blocks[0].kind, .shape(.rectangle))
        XCTAssertEqual(blocks[1].kind, .unshaped)
        XCTAssertEqual(try top("block\n  id1\n  id2\n  id3").map(\.label), ["id1", "id2", "id3"])
    }

    func testEdgesKeepTheirEndsMarksAndText() throws {
        let diagram = try BlockReading.block("block\n          id1[\"first\"]  -->   id2[\"second\"]\n      ")
        XCTAssertEqual(BlockReading.topBlocks(diagram).count, 2)
        XCTAssertEqual(diagram.edges.count, 1)
        XCTAssertEqual(diagram.edges[0].sourceIdentifier, "id1")
        XCTAssertEqual(diagram.edges[0].targetIdentifier, "id2")
        XCTAssertEqual(diagram.edges[0].targetArrowhead, .arrow)
        XCTAssertEqual(diagram.edges[0].identifier, "1-id1-id2")
        let labelled = try BlockReading.block("block\n          id1[\"first\"]  -- \"a label\" -->   id2[\"second\"]\n      ")
        XCTAssertEqual(labelled.edges[0].label, "a label")
        XCTAssertEqual(labelled.edges[0].targetArrowhead, .arrow)
    }

    func testColumnStatements() throws {
        XCTAssertEqual(BlockReading.rootColumns(try BlockReading.block("block\n  columns 2\n  block1[\"Block 1\"]")), 2)
        XCTAssertEqual(BlockReading.rootColumns(try BlockReading.block("block\n  block1[\"Block 1\"]")), -1)
        XCTAssertEqual(BlockReading.rootColumns(try BlockReading.block("block\n  columns auto\n  block1[\"Block 1\"]")), -1)
        XCTAssertEqual(try top("block\n  columns 1\n  block1[\"Block 1\"]\n  block2[\"Block 2\"]").count, 2)
    }

    func testCompositesNestAndKeepTheirTitles() throws {
        let diagram = try BlockReading.block("block\n  block\n    aBlock[\"ABlock\"]\n    block\n      bBlock[\"BBlock\"]\n    end\n  end")
        let outer = BlockReading.topBlocks(diagram)[0]
        XCTAssertEqual(outer.kind, .composite)
        XCTAssertEqual(outer.label, "")
        let children = BlockReading.children(of: outer, in: diagram)
        XCTAssertEqual(children.map(\.label), ["ABlock", ""])
        XCTAssertEqual(children[1].kind, .composite)
        XCTAssertEqual(BlockReading.children(of: children[1], in: diagram).map(\.label), ["BBlock"])
        let titled = try BlockReading.block("block\n  block:compoundBlock[\"Compound block\"]\n    columns 1\n    block2[\"Block 2\"]\n  end")
        let compound = BlockReading.topBlocks(titled)[0]
        XCTAssertEqual(compound.identifier, "compoundBlock")
        XCTAssertEqual(compound.label, "Compound block")
        XCTAssertEqual(compound.columns, 1)
        XCTAssertEqual(BlockReading.children(of: compound, in: titled).map(\.identifier), ["block2"])
        let mixed = try top("block\n  columns 1\n  block1[\"Block 1\"]\n\n  block\n    columns 2\n    block2[\"Block 2\"]\n    block3[\"Block 3\"]\n  end")
        XCTAssertEqual(mixed.count, 2)
    }

    func testArrowBlocksKeepTheirDirections() throws {
        let blocks = try top("block\n  columns 3\n  block1[\"Block 1\"]\n  blockArrow<[\"&nbsp;&nbsp;&nbsp;\"]>(right)\n  block2[\"Block 2\"]")
        XCTAssertEqual(blocks[1].kind, .arrow)
        XCTAssertEqual(blocks[1].directions, ["right"])
        let both = try top("block\n  columns 1\n  A\n  blockArrow<[\"&nbsp;&nbsp;&nbsp;\"]>(up, down)\n  block\n    columns 3\n    B\n    C\n    D\n  end")
        XCTAssertEqual(both.count, 3)
        XCTAssertEqual(BlockArrowDirections(written: both[1].directions), [.up, .down])
    }

    func testWidthsAndSpaces() throws {
        XCTAssertEqual(try top("block\n  columns 3\n  one[\"One Slot\"]\n  two[\"Two slots\"]:2").map(\.widthInColumns), [1, 2])
        let spaced = try top("block\n  columns 3\n  space\n  middle[\"In the middle\"]\n  space")
        XCTAssertEqual(spaced.map(\.kind), [.space, .shape(.rectangle), .space])
        XCTAssertEqual(try top("block\na space:5 b").count, 7)
    }

    func testClassesAndStylesApplyToTheirBlocks() throws {
        let diagram = try BlockReading.block("block\n  classDef black color:#ffffff, fill:#000000;\n\n  mc[\"Memcache\"]\n  class mc black")
        XCTAssertEqual(BlockReading.topBlocks(diagram)[0].classNames, ["black"])
        XCTAssertEqual(diagram.classes["black"]?.styles.first, "color:#ffffff")
        let styled = try top("block\ncolumns 1\n    B[\"A wide one in the middle\"]\n  style B fill:#f9F,stroke:#333,stroke-width:4px")
        XCTAssertTrue(styled[0].styles?.contains("fill:#f9F") == true)
        // A class or style for a block declared later waits for it.
        let early = try top("block\n  class A hot\n  style A fill:#f96\n  A")
        XCTAssertEqual(early.map(\.identifier), ["A"])
        XCTAssertEqual(early[0].classNames, ["hot"])
        XCTAssertEqual(early[0].styles, ["fill:#f96"])
    }

    func testPrototypeNamesAreOrdinaryNames() throws {
        for name in ["__proto__", "constructor"] {
            XCTAssertNoThrow(try BlockReading.block("block\n\(name)"))
            XCTAssertNoThrow(try BlockReading.block("block\nA; classDef \(name) color:#ffffff,fill:#000000; class A \(name)"))
        }
    }

    /// blockColorIndex.spec.ts: composites numbered in the order declared, an outer one before those inside it, one
    /// counter for the whole diagram, and plain blocks given none.
    func testCompositesAreNumberedInTheOrderTheyAreDeclared() throws {
        func index(_ identifier: String, _ source: String) throws -> Int? {
            BlockReading.named(identifier, in: try BlockReading.block(source))?.colorIndex
        }
        let three = "block-beta\n  block:first\n    a\n  end\n  block:second\n    b\n  end\n  block:third\n    c\n  end"
        XCTAssertEqual(try ["first", "second", "third"].map { name in try index(name, three) }, [0, 1, 2])
        let plain = "block-beta\n  a\n  b\n  block:group\n    c\n  end"
        XCTAssertNil(try index("a", plain))
        XCTAssertNil(try index("c", plain))
        XCTAssertEqual(try index("group", plain), 0)
        let nested = "block-beta\n  block:outer\n    block:inner\n      a\n    end\n  end\n  block:sibling\n    b\n  end"
        XCTAssertEqual(try ["outer", "inner", "sibling"].map { name in try index(name, nested) }, [0, 1, 2])
        let cousins = "block-beta\n  block:a1\n    block:a2\n      x\n    end\n  end\n  block:b1\n    block:b2\n      y\n    end\n  end"
        XCTAssertEqual(try ["a1", "a2", "b1", "b2"].map { name in try index(name, cousins) }, [0, 1, 2, 3])
    }

    /// blockDB.spec.ts: a link's thickness, pattern and marks.
    func testLinksGiveTheirThicknessPatternAndMarks() {
        XCTAssertFalse(BlockSyntaxValues.isThick(link: "-->"))
        XCTAssertFalse(BlockSyntaxValues.isThick(link: "-.->"))
        XCTAssertTrue(BlockSyntaxValues.isThick(link: "==>"))
        XCTAssertFalse(BlockSyntaxValues.isDotted(link: "==>"))
        XCTAssertTrue(BlockSyntaxValues.isDotted(link: "-.->"))
        for link in ["<-->", "<==>"] {
            XCTAssertEqual(BlockSyntaxValues.sourceArrowhead(link: link), .arrow)
            XCTAssertEqual(BlockSyntaxValues.targetArrowhead(link: link), .arrow)
        }
        XCTAssertEqual(BlockSyntaxValues.sourceArrowhead(link: "-->"), .none)
        XCTAssertEqual(BlockSyntaxValues.targetArrowhead(link: "--x"), .cross)
        XCTAssertEqual(BlockSyntaxValues.targetArrowhead(link: "--o"), .circle)
    }

    /// Every link of a statement with several counts, each edge counted by its ends.
    func testEveryLinkOfAStatementIsKept() throws {
        let diagram = try BlockReading.block("block\n A --> B --> C\n A --> B")
        XCTAssertEqual(diagram.edges.map(\.identifier), ["1-A-B", "1-B-C", "2-A-B"])
        XCTAssertEqual(BlockReading.topBlocks(diagram).map(\.identifier), ["A", "B", "C"])
    }

    func testErrorsSayWhatWasExpectedOnTheirLine() {
        XCTAssertEqual(BlockReading.readError("block\n"), .invalidSyntax(line: 2, problem: .block(.expectedStatement)))
        XCTAssertEqual(BlockReading.readError("block\n  block\n    a\n"), .invalidSyntax(line: 4, problem: .block(.unclosedComposite)))
        XCTAssertEqual(BlockReading.readError("block\n  a\n  end"), .invalidSyntax(line: 3, problem: .block(.expectedStatement)))
        XCTAssertEqual(BlockReading.readError("block\n  a[\"x\" ]"), .invalidSyntax(line: 2, problem: .unexpectedText(" ]")))
        XCTAssertEqual(BlockReading.readError("block\n  a --> "), .invalidSyntax(line: 2, problem: .block(.expectedBlockIdentifier)))
        XCTAssertEqual(BlockReading.readError("block\n  a<[\"x\"]>()"), .invalidSyntax(line: 2, problem: .block(.expectedArrowDirection)))
        XCTAssertEqual(BlockReading.readError("block\n  a[\"`md`\"]"), .invalidSyntax(line: 2, problem: .block(.expectedQuotedText)))
        XCTAssertEqual(BlockReading.readError("block\n  accTitle: x"), .invalidSyntax(line: 2, problem: .block(.expectedStatement)))
    }

    /// A comment line is left out, a `%%` alone is a block's name, as Pele's preprocessing leaves it.
    func testCommentLinesAreLeftOut() throws {
        XCTAssertEqual(try top("block\n  %% a comment\n  a\n  %%").map(\.identifier), ["a", "%%"])
    }

    /// Blocks, space cells and links are counted against the limits before they are made.
    func testCountsAreBoundedByTheLimits() {
        let limits = MermaidDiagramLimits(maximumSourceBytes: 50_000, maximumNodeCount: 10, maximumEdgeCount: 3, maximumLayoutPointCount: 50_000)
        XCTAssertEqual(BlockReading.readError("block\na space:100001 b"), .tooManyNodes(limit: 5_000))
        XCTAssertEqual(BlockReading.readError("block\na space:" + String(repeating: "9", count: 400) + " b"), .tooManyNodes(limit: 5_000))
        XCTAssertEqual(BlockReading.readError("block\n" + (0..<11).map { index in "b\(index) " }.joined(), limits: limits), .tooManyNodes(limit: 10))
        XCTAssertEqual(BlockReading.readError("block\na --> b --> c --> d --> e", limits: limits), .tooManyEdges(limit: 3))
    }

    /// Mermaid's ids are random; these are counted, so the same text always gives the same diagram.
    func testGeneratedIdentifiersAreCounted() throws {
        let diagram = try BlockReading.block("block\n  space\n  block\n    a\n  end\n  space:2")
        XCTAssertEqual(BlockReading.topBlocks(diagram).map(\.identifier), ["id-1-0", "id-2", "id-3-0", "id-3-1"])
        XCTAssertEqual(try BlockReading.block("block\n  space\n  block\n    a\n  end\n  space:2"), diagram)
    }
}
