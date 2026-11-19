/**
 * File: InfoDiagramParserTests.swift
 * ----------------------------------
 * Layer: Tests
 * Description: Reading, laying out and drawing info diagrams: the inputs of Pele's ported specifications, titles, and the version line.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 19/11/2026
 */

import XCTest
@testable import MermaidDiagrams
@testable import MermaidDiagramsBenchmark

/// Mermaid's info specifications (`info.spec.ts`, `info.test.ts`) ported, and what an info diagram lays out and paints.
final class InfoDiagramParserTests: XCTestCase {
    func testEmptyInfoDiagramsAreRead() throws {
        for source in ["info", "\n    info", "info\n    ", "\n    info\n    "] {
            XCTAssertEqual(try SimpleChartReading.info(source), InfoDiagram(), source)
        }
    }

    func testShowInfoIsReadOnTheKeywordsLineOrAfterIt() throws {
        for source in ["info showInfo", "info showInfo\n    ", "\n    info showInfo", "info\n    showInfo", "info\n    showInfo\n    ",
                       "\n    info\n    showInfo\n    ", "\n    info\n    showInfo", "\n    info showInfo\n    "] {
            XCTAssertEqual(try SimpleChartReading.info(source), InfoDiagram(), source)
        }
    }

    func testAnythingElseIsRefusedWithItsLine() {
        XCTAssertEqual(SimpleChartReading.readError("info unsupported"), .invalidSyntax(line: 1, problem: .unexpectedText("unsupported")))
        XCTAssertEqual(SimpleChartReading.readError("info\nshowInfo\nshowInfo"), .invalidSyntax(line: 3, problem: .unexpectedText("showInfo")))
        XCTAssertEqual(SimpleChartReading.readError("info\ntitle x\nshowInfo"), .invalidSyntax(line: 3, problem: .unexpectedText("showInfo")))
        XCTAssertEqual(SimpleChartReading.readError("info\ntitle x\ninfo"), .invalidSyntax(line: 3, problem: .unexpectedText("info")))
        XCTAssertEqual(SimpleChartReading.readError("info showInfox"), .invalidSyntax(line: 1, problem: .unexpectedText("showInfox")))
        XCTAssertEqual(SimpleChartReading.readError("info title x y"), nil)
        XCTAssertEqual(SimpleChartReading.readError("info accTitle x"), .invalidSyntax(line: 1, problem: .unexpectedText("accTitle x")))
        XCTAssertEqual(SimpleChartReading.readError("infox"), .unsupportedDiagramType(keyword: "infox"))
    }

    func testTitlesComeFromTheDiagramOrTheFrontMatterAndTheLaterOfTwoWins() throws {
        let titled = try SimpleChartReading.info("info showInfo title Hello   world %% comment\naccTitle: Name\naccDescr: Text\n")
        XCTAssertEqual(titled.title, "Hello world")
        XCTAssertEqual(titled.accessibilityTitle, "Name")
        XCTAssertEqual(titled.accessibilityDescription, "Text")
        XCTAssertEqual(try SimpleChartReading.info("---\ntitle: From front matter\n---\ninfo").title, "From front matter")
        XCTAssertEqual(try SimpleChartReading.info("---\ntitle: From front matter\n---\ninfo\ntitle Own").title, "Own")
        XCTAssertEqual(try SimpleChartReading.info("info\ntitle x\ntitle y").title, "y")
        XCTAssertEqual(try SimpleChartReading.info("info\naccDescr {\n  a\n  b\n}\n").accessibilityDescription, "a\nb")
    }

    func testCommentsDirectivesAndBlocksOfFrontMatterBetweenStatementsAreSkipped() throws {
        let source = "%%{init: {\"theme\":\"dark\"}}%%\ninfo showInfo %% c\n%% another\n---\nignored: true\n---\ntitle T\n"
        XCTAssertEqual(try SimpleChartReading.info(source).title, "T")
        XCTAssertEqual(try SimpleChartReading.info("info%% c\nshowInfo%% d").title, nil)
    }

    func testAnInfoDiagramAlwaysHasSomethingToDraw() throws {
        XCTAssertFalse(try MermaidDiagramReader.read("info", limits: .standard).hasNothingToDraw)
    }

    func testTheLayoutCentersTheTitleOverTheVersionLine() throws {
        let layout = InfoDiagramLayoutEngine.layout(try SimpleChartReading.info("info\ntitle A title"), text: UniformWidthTextMeasurer(),
                                                    boldText: UniformWidthTextMeasurer(characterWidth: 9), font: UniformWidthLayout.font)
        let versionWidth = CGFloat(MermaidDiagramsVersion.text.count) * 8
        XCTAssertEqual(layout.size.width, (versionWidth + 16).rounded(.up))
        // 8 points of page, the title's 24, 8 between, the version's 24, 8 of page.
        XCTAssertEqual(layout.size.height, 72)
        XCTAssertEqual(layout.title?.center, CGPoint(x: layout.size.width / 2, y: 20))
        XCTAssertEqual(layout.version.center, CGPoint(x: layout.size.width / 2, y: 52))
        let bare = InfoDiagramLayoutEngine.layout(InfoDiagram(), text: UniformWidthTextMeasurer(), boldText: UniformWidthTextMeasurer(), font: UniformWidthLayout.font)
        XCTAssertNil(bare.title)
        XCTAssertEqual(bare.size.height, 40)
    }

    func testTheSceneIsTheTitleInBoldAndTheVersionInTheMutedColor() throws {
        let layout = InfoDiagramLayoutEngine.layout(try SimpleChartReading.info("info\ntitle Hi"), typography: SimpleChartReading.typography)
        let scene = DiagramScene(layout: layout)
        XCTAssertEqual(scene.items.count, 2)
        XCTAssertEqual(scene.texts.map(\.part), [.title, .version])
        XCTAssertEqual(scene.texts.map(\.isBold), [true, false])
        XCTAssertEqual(scene.texts.map(\.paint), [.foreground, .muted])
        XCTAssertEqual(scene.texts[1].block.lines, [MermaidDiagramsVersion.text])
    }

    func testTheCorpusIsReadAndLaidOut() throws {
        let examples = try InfoDiagramCorpus.documentationExamples()
        XCTAssertEqual(examples.count, 2)
        for example in examples + [InfoDiagramCorpus.titled] {
            let layout = InfoDiagramLayoutEngine.layout(try SimpleChartReading.info(example), typography: SimpleChartReading.typography)
            XCTAssertGreaterThan(layout.size.width, 100, example)
        }
    }
}
