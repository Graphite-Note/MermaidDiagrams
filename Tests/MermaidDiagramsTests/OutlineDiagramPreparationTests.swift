/**
 * File: OutlineDiagramPreparationTests.swift
 * ------------------------------------------
 * Layer: Tests
 * Description: Kanban boards, tree views and Ishikawa diagrams are prepared through the one entry point, with their
 *              narrow layouts and what a screen reader hears, and Pele's worst cases for them are read and laid out
 *              within bounds and time, or refused with a typed error.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 19/11/2026
 */

import XCTest
@testable import MermaidDiagrams
@testable import MermaidDiagramsBenchmark

final class OutlineDiagramPreparationTests: XCTestCase {
    private let typography = DiagramTypography(font: DiagramFont(postScriptName: nil, size: 16))

    private func prepared(_ source: String) throws -> PreparedMermaidDiagram {
        try MermaidDiagramPreparation.prepare(source: source, typography: typography)
    }

    func testEachTypeIsPreparedWithItsKindAndWhatAScreenReaderHears() throws {
        let board = try prepared("kanban\n  todo[Todo]\n    a[Write the docs]\n    b[Fix the bug]\n  done[Done]")
        XCTAssertEqual(board.kind, .kanban)
        XCTAssertEqual(board.accessibility.label, "Kanban board")
        XCTAssertEqual(board.accessibility.value, "Todo: Write the docs, Fix the bug; Done")
        let tree = try prepared("treeView-beta\n  accTitle: Sources\n  src/\n    main.swift")
        XCTAssertEqual(tree.kind, .treeView)
        XCTAssertEqual(tree.accessibility.label, "Sources")
        XCTAssertEqual(tree.accessibility.value, "src/, main.swift")
        let fishbone = try prepared("ishikawa-beta\n  Blurry photo\n    Process\n      Out of focus\n        Too fast\n    User")
        XCTAssertEqual(fishbone.kind, .ishikawa)
        XCTAssertEqual(fishbone.accessibility.label, "Ishikawa diagram")
        XCTAssertEqual(fishbone.accessibility.value, "Blurry photo; Process: Out of focus, Too fast; User")
        XCTAssertEqual(MermaidDiagramKind.ishikawa.peleName, "ishikawa")
        XCTAssertEqual(MermaidDiagramKind.treeView.peleName, "treeView")
        let svg = try XCTUnwrap(board.svgDocument(colors: .peleVariables, identifierPrefix: "pele"))
        XCTAssertTrue(svg.contains("pele-kanban"))
        XCTAssertTrue(svg.contains("class=\"pele-count\""))
    }

    func testAWideDiagramHasANarrowSceneForAColumn() throws {
        let board = try prepared(KanbanCorpus.board(columnCount: 4, cardsPerColumn: 2))
        let foldedBoard = try XCTUnwrap(board.narrowScene)
        XCTAssertLessThanOrEqual(foldedBoard.size.width, PreparedMermaidDiagram.standardNarrowestColumnWidth)
        let fishbone = try prepared(IshikawaCorpus.fishbone(categoryCount: 4, causesPerCategory: 2))
        XCTAssertLessThanOrEqual(try XCTUnwrap(fishbone.narrowScene).size.width, PreparedMermaidDiagram.standardNarrowestColumnWidth)
        let tree = try prepared("treeView-beta\nsrc/\n    components/\n        a-very-long-component-name-that-runs-on.swift ## and what it does")
        XCTAssertLessThan(try XCTUnwrap(tree.narrowScene).size.width, tree.scene.size.width)
        XCTAssertNil(try prepared("kanban\n todo\n  a").narrowScene, "One column fits")
    }

    func testDiagramsDeclaringNothingAreRefusedAsNothingToDraw() {
        for source in ["treeView-beta", "ishikawa\n%% only a comment"] {
            XCTAssertThrowsError(try prepared(source), source) { error in
                XCTAssertEqual(error as? MermaidDiagramPreparationFailure, .nothingToDraw, source)
            }
        }
    }

    /// Reading takes time in proportion to the text: 20,000 columns, entries or causes, each a line, are read in a fraction
    /// of the half minute a count of the board's nodes at each node took (KanbanBoardBuilder counted them all again).
    func testReadingManyNodesTakesTimeInProportionToTheirCount() throws {
        var limits = MermaidDiagramLimits.standard
        limits.maximumSourceBytes = 1_000_000
        limits.maximumNodeCount = 20_000
        let sources = ["kanban\n" + String(repeating: "a\n", count: 20_000), "kanban\ntodo\n" + String(repeating: " a\n", count: 19_999),
                       "treeView-beta\n" + String(repeating: "├── a\n", count: 20_000), "ishikawa\nE\n" + String(repeating: " c\n", count: 19_999)]
        for source in sources {
            let started = Date()
            _ = try MermaidDiagramReader.read(source, limits: limits)
            XCTAssertLessThan(Date().timeIntervalSince(started), 5, String(source.prefix(20)))
        }
    }

    /// Pele's stress tests for the three types, shortened to the source limit: each is read and laid out (or refused with
    /// a typed error) in well under Pele's three seconds, at a finite size.
    func testPelesWorstCasesAreDrawnOrRefusedQuickly() {
        let size = 49_000
        func repeated(_ count: Int, _ line: (Int) -> String) -> String { (0..<count).map(line).joined() }
        let ishikawa = "ishikawa-beta\n"
        let tree = "treeView-beta\n"
        let cases = [
            "kanban\n" + String(repeating: "(a) ", count: size / 4), "kanban\ntodo\n" + String(repeating: " \n", count: size / 2) + " a",
            "kanban\ntodo\n a" + String(repeating: "@", count: size), "kanban\ntodo\n a" + String(repeating: "@{", count: size / 2),
            "kanban\ntodo\n a@{" + String(repeating: " a: 1,\n", count: size / 7), "kanban\ntodo\n a@{" + String(repeating: "\"", count: size),
            "kanban\ntodo\n" + String(repeating: " a\n", count: 4_900), "kanban\n" + String(repeating: "a\n", count: 4_900),
            "kanban\ntodo\n a@{ " + repeated(4_000) { index in "k\(index): 1, " } + "label: x }",
            "kanban\ntodo\n a@{ a: " + String(repeating: "[", count: 20_000) + " }\n", "kanban\ntodo\n a[" + String(repeating: "word ", count: size / 5) + "]",
            "kanban\ntodo[" + String(repeating: "w", count: size) + "]", "kanban\ntodo\n a@{ assigned: \"" + String(repeating: "ab ", count: size / 3) + "\" }",
            ishikawa + String(repeating: " ", count: size), ishikawa + String(repeating: " \t\r  \n", count: size / 6) + "%",
            ishikawa + String(repeating: "ishikawa-beta ", count: size / 14), ishikawa + "  " + String(repeating: "a", count: size),
            ishikawa + "  E\n" + String(repeating: "    c\n", count: 4_900), ishikawa + "  E\n    C\n" + String(repeating: "      c\n", count: 4_900),
            ishikawa + repeated(300) { index in String(repeating: " ", count: index + 1) + "n\n" },
            ishikawa + repeated(4_000) { index in String(repeating: " ", count: 1 + (index * 7) % 13) + "n\n" },
            tree + String(repeating: "a\n", count: 4_900), tree + repeated(300) { index in String(repeating: " ", count: index) + "d/\n" },
            tree + String(repeating: "a", count: size), tree + "a" + String(repeating: " ", count: size) + "b",
            tree + String(repeating: "a :::" + String(repeating: " ", count: 95), count: size / 100) + "1",
            tree + String(repeating: "accDescr {\n", count: size / 11), tree + String(repeating: "\"a\n", count: size / 3),
            tree + "a" + String(repeating: " :::highlight", count: size / 13), tree + String(repeating: "├── a\n", count: size / 10),
            tree + repeated(300) { index in String(repeating: "│", count: index) + "├─ x\n" }, tree + String(repeating: "│   │   │\n", count: size / 20),
            tree + String(repeating: String(repeating: "\t", count: 40) + "├── a\n", count: size / 46),
        ]
        for source in cases {
            let started = Date()
            do {
                let prepared = try MermaidDiagramPreparation.prepare(source: source, typography: typography)
                XCTAssertTrue(prepared.scene.size.width.isFinite && prepared.scene.size.height.isFinite, String(source.prefix(40)))
            } catch {
                XCTAssertNotNil(error as MermaidDiagramPreparationFailure?, String(source.prefix(40)))
            }
            XCTAssertLessThan(Date().timeIntervalSince(started), 1.5, String(source.prefix(40)))
        }
    }
}
