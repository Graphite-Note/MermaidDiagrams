/**
 * File: IshikawaLayoutEquivalenceTests.swift
 * ------------------------------------------
 * Layer: Tests
 * Description: The Ishikawa fishbone of flat records, its texts measured from the diagram's bytes, gives, read as
 *              categories and head, exactly what 0.7.0's layout gave from blocks of decoded labels, across and at
 *              Graphite's narrow widths, on every corpus and spec text, thousands of them changed at random, random
 *              fishbones with deep causes, entities, markup and text past ASCII, hostile ones, and twelve threads at once.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 26/11/2026
 */

import Foundation
import XCTest
@testable import MermaidDiagrams

final class IshikawaLayoutEquivalenceTests: XCTestCase {
    private static let widths: [CGFloat?] = [nil, 600, 390, 280, 120]
    private static let tokens = ["Effect\n", "  Cause\n", "    Sub cause\n", "      deeper\n", "&amp;", "<br>", "**bold**", "é café", "🚀", "\t", "\n",
                                 "a long cause that wraps past two hundred points of room in the small face of the causes"]

    /// The diagram read from `source` when it is an Ishikawa diagram.
    private static func diagram(_ source: String) -> IshikawaDiagram? {
        guard source.utf8.count <= MermaidDiagramLimits.standard.maximumSourceBytes, let frontEnd = try? MermaidFrontEnd.read(source),
              frontEnd.typeKeyword == .other, frontEnd.keywordText.lowercased().hasPrefix("ishikawa") else { return nil }
        return try? IshikawaParser.parse(keyword: frontEnd.keywordText, endingAt: MermaidTextCursor(frontEnd), limits: .standard)
    }

    /// 0.7.0's layout at `width`: the frozen fishbone, or the outline, which is unchanged, when that is narrower.
    private static func referenceLayout(_ diagram: IshikawaDiagram, width: CGFloat?) -> ReferenceIshikawaLayout {
        let typography = DiagramSceneSamples.typography
        let measurers = DiagramTextMeasurerSet(typography: typography)
        let across = ReferenceIshikawaLayoutEngine.fishbone(diagram, measurers: measurers, font: typography.font)
        guard let width, width > 0, width.isFinite, across.size.width > width, width < ReferenceIshikawaLayoutEngine.breakpoint else { return across }
        let down = ReferenceIshikawaLayout(IshikawaOutlinePlacement.layout(diagram, measurers: measurers, font: typography.font, maximumWidth: width))
        return down.size.width < across.size.width ? down : across
    }

    @discardableResult
    private func assertLaidOutAsTheReference(_ source: String, file: StaticString = #filePath, line: UInt = #line) -> Bool {
        guard let diagram = Self.diagram(source) else { return false }
        for width in Self.widths {
            let laidOut = IshikawaLayoutEngine.layout(diagram, typography: DiagramSceneSamples.typography, maximumWidth: width)
            XCTAssertEqual(ReferenceIshikawaLayout(laidOut), Self.referenceLayout(diagram, width: width), "\(String(describing: width)): \(source)",
                           file: file, line: line)
        }
        return true
    }

    func testEveryTextAndItsChangesAreLaidOutAsTheFrozenEngineLaysThemOut() throws {
        let own = try MapReadingEquivalence.everyText().filter { text in Self.diagram(text) != nil }
        XCTAssertFalse(own.isEmpty)
        var mutations = MapReadingMutations(seed: 0x15_41_1A70, tokens: Self.tokens)
        var comparedCount = 0
        for text in own {
            if assertLaidOutAsTheReference(text) { comparedCount += 1 }
            for _ in 0..<300 where assertLaidOutAsTheReference(mutations.mutated(text)) { comparedCount += 1 }
        }
        XCTAssertGreaterThan(comparedCount, 500)
    }

    func testRandomFishbonesAreLaidOutAsTheFrozenEngineLaysThemOut() {
        for text in Self.randomDiagrams(count: 1_200, seed: 0x15_41_1A71) { assertLaidOutAsTheReference(text) }
    }

    /// Many categories, many causes, deep nesting and a long text, laid out as the frozen engine lays them out.
    func testHostileFishbonesAreLaidOutAsTheFrozenEngineLaysThemOut() {
        let cases = [
            "ishikawa-beta\n    Effect\n" + (0..<300).map { index in "        Category \(index)\n            cause\n" }.joined(),
            "ishikawa-beta\n    Effect\n        Category\n" + String(repeating: "            cause &amp; effect\n", count: 1_500),
            "ishikawa-beta\n    Effect\n" + (0..<150).map { depth in String(repeating: "  ", count: depth + 4) + "d\(depth)\n" }.joined(),
            "ishikawa-beta\n    " + String(repeating: "word ", count: 3_000) + "\n        c\n            " + String(repeating: "x", count: 5_000) + "\n",
        ]
        for source in cases { XCTAssertTrue(assertLaidOutAsTheReference(source), String(source.prefix(40))) }
    }

    /// Twelve threads lay the same fishbones out at once, each layout read as the frozen engine's.
    func testFishbonesLaidOutOnTwelveThreadsAtOnceMatchTheFrozenEngine() {
        let diagrams = Self.randomDiagrams(count: 100, seed: 0x15_41_1A72).compactMap(Self.diagram)
        let expected = diagrams.map { diagram in Self.widths.map { width in Self.referenceLayout(diagram, width: width) } }
        let mismatches = IshikawaMismatchCounter()
        DispatchQueue.concurrentPerform(iterations: 12) { thread in
            for offset in 0..<diagrams.count {
                let index = (offset + thread * 5) % diagrams.count
                for (widthIndex, width) in Self.widths.enumerated() {
                    let laidOut = IshikawaLayoutEngine.layout(diagrams[index], typography: DiagramSceneSamples.typography, maximumWidth: width)
                    if ReferenceIshikawaLayout(laidOut) != expected[index][widthIndex] { mismatches.add() }
                }
            }
        }
        XCTAssertEqual(mismatches.count, 0)
    }

    /// Random fishbones: up to a dozen categories, causes three levels deep and more, texts with entities, markup, breaks
    /// and characters past ASCII, some wider than their room.
    private static func randomDiagrams(count: Int, seed: UInt64) -> [String] {
        var random = MapReadingMutations(seed: seed, tokens: [])
        let texts = ["Effect", "Cause", "Sub cause", "é café", "🚀 launch", "a &amp; b", "line<br>break", "**bold** text", "#59; code",
                     "a long cause that wraps past two hundred points of room in the small face of the causes", "x", "  padded  ", "Ünïcödé"]
        return (0..<count).map { index in
            var text = (index % 4 == 0 ? "---\ntitle: Fishbone \(index)\n---\n" : "") + "ishikawa-beta\n    " + texts[random.below(texts.count)] + "\n"
            for _ in 0..<random.below(12) {
                text += "        " + texts[random.below(texts.count)] + "\n"
                var depth = 0
                for _ in 0..<random.below(9) {
                    depth = max(0, min(depth + random.below(3) - 1, 5))
                    text += String(repeating: "    ", count: depth + 3) + texts[random.below(texts.count)] + "\n"
                }
            }
            return text
        }
    }
}

/// A count several threads add to.
private final class IshikawaMismatchCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var value = 0

    func add() {
        lock.lock()
        value += 1
        lock.unlock()
    }

    var count: Int {
        lock.lock()
        defer { lock.unlock() }
        return value
    }
}
