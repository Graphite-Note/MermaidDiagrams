/**
 * File: TreeViewLayoutEquivalenceTests.swift
 * ------------------------------------------
 * Layer: Tests
 * Description: The tree view layout of flat records gives, read as rows and guides, exactly what 0.7.0's layout gave
 *              from the entries' Strings, loose and tight at Graphite's narrow widths and narrower, on every corpus and
 *              spec text, thousands of them changed at random, random trees with every annotation and with names past
 *              ASCII and entities, hostile trees, and twelve threads at once.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 26/11/2026
 */

import Foundation
import XCTest
@testable import MermaidDiagrams

final class TreeViewLayoutEquivalenceTests: XCTestCase {
    /// No room, Graphite's narrow columns, and widths that make the tight layout squeeze names and steps.
    private static let widths: [CGFloat?] = [nil, 600, 390, 280, 160, 60, 0]

    /// The layouts of `source` at every width compared with the frozen engine's; false when `source` is no tree view.
    @discardableResult
    private func assertLaidOutAsTheReference(_ source: String, file: StaticString = #filePath, line: UInt = #line) -> Bool {
        guard let cursor = MapReadingEquivalence.cursor(of: source, readAs: .treeView),
              let diagram = try? TreeViewParser.parse(cursor, limits: .standard) else { return false }
        let reference = ReferenceTreeViewDiagram(diagram)
        let typography = DiagramSceneSamples.typography
        for width in Self.widths {
            let laidOut = TreeViewLayoutEngine.layout(diagram, typography: typography, maximumWidth: width)
            let expected = ReferenceTreeViewLayoutEngine.layout(reference, typography: typography, maximumWidth: width)
            XCTAssertEqual(ReferenceTreeViewLayout(laidOut), expected, "\(width.map { "\($0)" } ?? "unbounded"): \(source)", file: file, line: line)
        }
        return true
    }

    func testEveryTextAndItsChangesAreLaidOutAsTheFrozenEngineLaysThemOut() throws {
        let tokens = ["├── ", "└── ", "│   ", "src/", "a.ts", "\"quoted name\"", ":::highlight", " icon(folder)", " icon()", " ## a description",
                      "&amp;", "&#35;", "#59;", "é", "\u{1F4E6}", "\t", "    ", "\n"]
        let texts = MapReadingEquivalence.texts(readAs: .treeView, among: try MapReadingEquivalence.everyText(), mutationCount: 60, tokens: tokens,
                                                seed: 0x7EE_1A70)
        var comparedCount = 0
        for text in texts where assertLaidOutAsTheReference(text) { comparedCount += 1 }
        XCTAssertGreaterThan(comparedCount, 500)
    }

    func testRandomTreesAreLaidOutAsTheFrozenEngineLaysThemOut() {
        for text in Self.randomTrees(count: 800, seed: 0x7EE_1A71) { assertLaidOutAsTheReference(text) }
    }

    /// Long names, many entries and deep nesting laid out as the frozen engine lays them out.
    func testHostileTreesAreLaidOutAsTheFrozenEngineLaysThemOut() {
        let cases = [
            "treeView-beta\n    " + String(repeating: "a b ", count: 2_000),
            "treeView-beta\n    root/\n" + String(repeating: "        entry ## and its description &amp; more\n", count: 900),
            "treeView-beta\n" + (0..<200).map { depth in String(repeating: " ", count: depth + 1) + "d\(depth)/ icon(file)\n" }.joined(),
            "treeView-beta\n" + String(repeating: "├── a :::highlight\n│   └── b ## c\n", count: 600),
        ]
        for source in cases { XCTAssertTrue(assertLaidOutAsTheReference(source), String(source.prefix(40))) }
    }

    /// Twelve threads lay the same trees out at once, each layout read as the frozen engine's.
    func testTreesLaidOutOnTwelveThreadsAtOnceMatchTheFrozenEngine() {
        let typography = DiagramSceneSamples.typography
        let diagrams = Self.randomTrees(count: 120, seed: 0x7EE_1A72).compactMap { text -> TreeViewDiagram? in
            guard let cursor = MapReadingEquivalence.cursor(of: text, readAs: .treeView) else { return nil }
            return try? TreeViewParser.parse(cursor, limits: .standard)
        }
        let expected = diagrams.map { diagram in
            Self.widths.map { width in ReferenceTreeViewLayoutEngine.layout(ReferenceTreeViewDiagram(diagram), typography: typography, maximumWidth: width) }
        }
        let writer = DiagramSVGWriter(colors: .palette(.peleLight))
        let svgs = diagrams.map { diagram in
            Self.widths.map { width in
                writer.document(of: DiagramScene(layout: TreeViewLayoutEngine.layout(diagram, typography: typography, maximumWidth: width)), diagramType: "treeView")
            }
        }
        let mismatches = MismatchCounter()
        DispatchQueue.concurrentPerform(iterations: 12) { thread in
            for offset in 0..<diagrams.count {
                let index = (offset + thread * 7) % diagrams.count
                for (widthIndex, width) in Self.widths.enumerated() {
                    let laidOut = TreeViewLayoutEngine.layout(diagrams[index], typography: typography, maximumWidth: width)
                    if ReferenceTreeViewLayout(laidOut) != expected[index][widthIndex] { mismatches.add() }
                    let writer = DiagramSVGWriter(colors: .palette(.peleLight))
                    if writer.document(of: DiagramScene(layout: laidOut), diagramType: "treeView") != svgs[index][widthIndex] { mismatches.add() }
                }
            }
        }
        XCTAssertEqual(mismatches.count, 0)
    }

    /// Random trees written with indentation or box drawing: every annotation, entities, names past ASCII, front matter
    /// that shows icons and maps them.
    private static func randomTrees(count: Int, seed: UInt64) -> [String] {
        var random = MapReadingMutations(seed: seed, tokens: [])
        let names = ["src/", "index.ts", "\"spaced name\"", "README.md", "\u{1F4E6} packages/", "a", "é/", "x y z", ".env", "Dockerfile",
                     "a &amp; b", "&#35;hash;", "long name that is far wider than a narrow column allows", "\"quoted/\"", "\"\"", "a\u{301}/"]
        let annotations = ["", "", " :::highlight", " icon(folder)", " icon(file)", " icon()", " icon(logos:react)", " ## entry point",
                           " :::a icon(b) ## c", " ## a long description that wraps in a tight layout &lt;", " ## é \u{00A0}"]
        let headers = ["", "---\nconfig:\n  treeView:\n    showIcons: true\n    rowIndent: 30\n---\n",
                       "---\nconfig:\n  treeView:\n    showIcons: true\n    extensionIcons:\n      .ts: none\n      .md: folder\n---\n",
                       "---\nconfig:\n  treeView:\n    paddingX: 0\n    paddingY: 9\n    lineThickness: 3\n---\n"]
        return (0..<count).map { index in
            var text = headers[index % headers.count] + "treeView-beta\n"
            if index % 5 == 0 { text += "title A tree \(index)\n" }
            var depth = 0
            for _ in 0..<(1 + random.below(18)) {
                depth = max(0, min(depth + random.below(3) - 1, 6))
                text += String(repeating: "    ", count: depth + 1) + names[random.below(names.count)] + annotations[random.below(annotations.count)] + "\n"
            }
            return text
        }
    }
}

/// A count several threads add to.
private final class MismatchCounter: @unchecked Sendable {
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
