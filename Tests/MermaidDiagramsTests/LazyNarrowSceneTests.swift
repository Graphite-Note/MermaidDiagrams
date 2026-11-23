/**
 * File: LazyNarrowSceneTests.swift
 * --------------------------------
 * Layer: Tests
 * Description: A prepared diagram lays out its narrow scene only when it is read, once, whichever threads read it, and a
 *              column it fits never reads it; literal text breaks into the same lines as when each probe was made from
 *              the text's characters.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 23/11/2026
 */

import CoreGraphics
import Foundation
import XCTest
@testable import MermaidDiagrams
@testable import MermaidDiagramsBenchmark

final class LazyNarrowSceneTests: XCTestCase {
    private let typography = DiagramTypography(font: DiagramFont(postScriptName: nil, size: 16))

    private func prepared(_ source: String, narrowestColumnWidth: CGFloat? = PreparedMermaidDiagram.standardNarrowestColumnWidth) throws
        -> PreparedMermaidDiagram {
        try MermaidDiagramPreparation.prepare(source: source, typography: typography, narrowestColumnWidth: narrowestColumnWidth,
                                              now: GanttChartCorpus.now, timeZone: GanttChartCorpus.timeZone)
    }

    func testAColumnTheDiagramFitsNeverLaysOutItsNarrowScene() throws {
        let flowchart = try prepared(FlowchartCorpus.fourteenShapesInARow)
        let store = try XCTUnwrap(flowchart.preparedNarrowScene, "A wide flowchart may have a narrow scene")
        XCTAssertTrue(store.isPending, "Preparing lays nothing out a second time")
        let fittingWidth = flowchart.scene.size.width + 1
        XCTAssertFalse(flowchart.showsNarrowScene(inColumnWidth: fittingWidth))
        XCTAssertEqual(flowchart.scene(inColumnWidth: fittingWidth).size, flowchart.scene.size)
        XCTAssertFalse(flowchart.showsNarrowScene(inColumnWidth: flowchart.scene.size.width, scale: 0.5), "Scaled down it fits too")
        XCTAssertFalse(flowchart.showsNarrowScene(inColumnWidth: 0), "A column not measured yet")
        XCTAssertTrue(store.isPending, "No column it fits reads the narrow scene")
        XCTAssertTrue(flowchart.showsNarrowScene(inColumnWidth: 350))
        XCTAssertFalse(store.isPending, "A column too narrow lays it out")
        XCTAssertEqual(flowchart.scene(inColumnWidth: 350).size, try XCTUnwrap(flowchart.narrowScene).size)
    }

    func testADiagramWithNoNarrowSceneKeepsNoWorkForOne() throws {
        XCTAssertNil(try prepared("flowchart LR\n  A --> B").preparedNarrowScene, "No wider than the narrowest column")
        XCTAssertNil(try prepared(FlowchartCorpus.fourteenShapesInARow, narrowestColumnWidth: nil).preparedNarrowScene, "No narrow layout asked for")
        XCTAssertNil(try prepared("venn-beta\n  set A\n  set B").preparedNarrowScene, "A type with no narrow layout")
        let wideGraph = "gitGraph\n" + String(repeating: " commit\n", count: 12)
        XCTAssertNil(try prepared(wideGraph, narrowestColumnWidth: 700).preparedNarrowScene,
                     "Pele keeps a diagram it only turns across in a container of 640 points or more")
        XCTAssertNotNil(try prepared(wideGraph).preparedNarrowScene)
    }

    func testANarrowSceneTheTurnedLayoutDoesNotNarrowIsNil() throws {
        // A turned layout as wide as the regular one, one that fails, and none: the work runs and makes no scene.
        let context = MermaidDiagramPreparationContext(typography: typography, limits: .standard, narrowestColumnWidth: 280, now: GanttChartCorpus.now,
                                                       timeZone: GanttChartCorpus.timeZone)
        let wide = DiagramScene(size: CGSize(width: 900, height: 100), font: typography.font, items: [])
        let deferred = try XCTUnwrap(context.narrowScene(of: "turned", regularSize: CGSize(width: 400, height: 100), laidOut: { turned in turned }) { _ in
            wide
        })
        XCTAssertNil(deferred.scene, "Turned it is no narrower than the regular scene")
        XCTAssertFalse(deferred.isPending)
        let failing = try XCTUnwrap(context.narrowScene(of: "turned", regularSize: CGSize(width: 400, height: 100),
                                                        laidOut: { (_: String) throws -> String in throw CancellationError() }) { _ in wide })
        XCTAssertNil(failing.scene, "A turned layout that fails keeps the regular scene alone")
        let notTurned = try XCTUnwrap(context.narrowScene(of: String?.none, regularSize: CGSize(width: 400, height: 100), laidOut: { turned in turned }) { _ in
            wide
        })
        XCTAssertNil(notTurned.scene, "A diagram its type does not turn")
    }

    func testThreadsReadingTogetherGetOneSceneLaidOutOnce() throws {
        let source = try PacketDiagramCorpus.documentationExamples().max { first, second in first.count < second.count } ?? ""
        let expected = try XCTUnwrap(try prepared(source).narrowScene, "A packet diagram wider than the column")
        let expectedDocument = DiagramSVGWriter().document(of: expected, diagramType: "packet")
        let shared = try prepared(source)
        let documents = LockedDocuments()
        DispatchQueue.concurrentPerform(iterations: 32) { _ in
            documents.add(shared.narrowScene.map { scene in DiagramSVGWriter().document(of: scene, diagramType: "packet") } ?? "none")
        }
        XCTAssertEqual(documents.all.count, 32)
        XCTAssertEqual(Set(documents.all), [expectedDocument], "Every thread reads the scene a preparation read at once makes")

        let context = MermaidDiagramPreparationContext(typography: typography, limits: .standard, narrowestColumnWidth: 280, now: GanttChartCorpus.now,
                                                       timeZone: GanttChartCorpus.timeZone)
        let narrowPage = DiagramScene(size: CGSize(width: 200, height: 300), font: typography.font, items: [])
        let layouts = LockedDocuments()
        let deferred = try XCTUnwrap(context.narrowScene(of: "turned", regularSize: CGSize(width: 390, height: 100), laidOut: { turned in
            layouts.add(turned)
            return turned
        }) { _ in narrowPage })
        DispatchQueue.concurrentPerform(iterations: 32) { _ in XCTAssertEqual(deferred.scene?.size, narrowPage.size) }
        XCTAssertEqual(layouts.all, ["turned"], "Laid out once, by the first read")
    }

    func testLiteralTextBreaksAsWhenEachProbeWasMadeFromItsCharacters() {
        let measurer = typography.edgeText
        let texts = ["", "a", "Source Port", "Sequence Number (32 bits) of the segment", "   leading and trailing   ", "no-spaces-at-all-here-to-break",
                     "two\nlines\n\nwith an empty one", "e\u{301}te\u{301} cafe\u{301} à la carte", "日本語のテキストは空白なしで折り返す", "flags 🇨🇭👩‍👩‍👧 emoji",
                     "tab\tseparated\twords", "a\r\nb", "  ", "x y z w v u t s r q p o n m l k j i h g f e d c b a",
                     "a \u{301}b c \u{301}\u{301}d", "no\u{A0}break\u{A0}spaces", "日本\u{3000}語\u{3000}の文", "form\u{0B}feed\u{0C}page",
                     "unit\u{1F}separator\u{1F}kept", "line\u{2028}separator \u{85}next"]
        for text in texts {
            for room in [1, 8, 20, 37.5, 60, 120, 400] as [CGFloat] {
                let block = DiagramTextBlock(literal: text, measurer: measurer, room: room)
                let expected = Self.literalLinesFromCharacters(text, measurer: measurer, room: room)
                XCTAssertEqual(block.lines, expected, "\(text.debugDescription) in \(room)")
                XCTAssertEqual(block.lineWidths, expected.map { line in measurer.width(of: line) }, "\(text.debugDescription) in \(room)")
            }
        }
    }

    /// The lines as `DiagramTextBlock(literal:measurer:room:)` made them before its probes were made from slices of the text:
    /// each probe a String of an array of the text's characters, a line trimmed by reversing it.
    private static func literalLinesFromCharacters(_ text: String, measurer: some DiagramTextMeasuring, room: CGFloat) -> [String] {
        guard !text.isEmpty else { return [] }
        var lines: [String] = []
        for written in text.split(separator: "\n", omittingEmptySubsequences: false) {
            let characters = Array(written)
            guard !characters.isEmpty else {
                lines.append("")
                continue
            }
            var start = 0
            while start < characters.count {
                let remaining = characters.count - start
                func fits(_ length: Int) -> Bool { measurer.width(of: String(characters[start..<(start + length)])) <= room }
                var upper = 1
                while upper < remaining, fits(upper) { upper = min(remaining, upper * 2) }
                var taken = 1
                while taken < upper {
                    let middle = (taken + upper + 1) / 2
                    if fits(middle) { taken = middle } else { upper = middle - 1 }
                }
                let wraps = start + taken < characters.count
                if wraps, !characters[start + taken].isWhitespace,
                   let lastSpace = (1..<taken).last(where: { offset in characters[start + offset].isWhitespace }) {
                    taken = lastSpace + 1
                }
                let line = String(characters[start..<(start + taken)])
                let trimmed = String(line.reversed().drop { character in character.isWhitespace }.reversed())
                lines.append(wraps && !trimmed.isEmpty ? trimmed : line)
                start += taken
                while wraps, start < characters.count, characters[start].isWhitespace { start += 1 }
            }
        }
        return lines
    }
}

/// Texts added from several threads.
private final class LockedDocuments: @unchecked Sendable {
    private let lock = NSLock()
    private var documents: [String] = []

    func add(_ document: String) {
        lock.lock()
        documents.append(document)
        lock.unlock()
    }

    var all: [String] {
        lock.lock()
        defer { lock.unlock() }
        return documents
    }
}
