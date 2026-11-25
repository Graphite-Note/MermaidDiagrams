/**
 * File: IshikawaReaderEquivalenceTests.swift
 * ------------------------------------------
 * Layer: Tests
 * Description: The Ishikawa reader, on bytes, gives the diagram 0.7.0's reader gave on UTF-16 units, or its error with
 *              its line and excerpt, on every corpus input and spec text, thousands of them changed at random, random
 *              diagrams indented with every white space of JavaScript, and long, many and deep hostile ones.
 *
 * Authors: Bahey Shalash
 * Version: 0.3
 * Date: 25/11/2026
 */

import XCTest
@testable import MermaidDiagrams

final class IshikawaReaderEquivalenceTests: XCTestCase {
    private static let tokens = ["ishikawa-beta", "ishikawa", "ISHIKAWA-BETA x", "ishikawa_x", "ishikawa2", "ishikawa-notes", "Effect\n", "  Cause\n",
                                 "    Sub cause\n", "\t\tdeep\n", "\u{2003}em indent\n", "\u{1680}x", "\u{205F}", "\u{FEFF}", "\u{2029}", "%% c\u{2028}x",
                                 "  %%", "\n\n", " \n ", "🚀 rocket"]

    /// The cursor the reader hands the Ishikawa parser for `source`, and its keyword, when `source` is one.
    private func cursor(of source: String) -> (keyword: String, cursor: MermaidTextCursor)? {
        guard source.utf8.count <= MermaidDiagramLimits.standard.maximumSourceBytes, let frontEnd = try? MermaidFrontEnd.read(source),
              frontEnd.typeKeyword == .other, let first = frontEnd.keywordText.first, first == "i" || first == "I",
              frontEnd.keywordText.lowercased().hasPrefix("ishikawa") else { return nil }
        return (frontEnd.keywordText, MermaidTextCursor(frontEnd))
    }

    @discardableResult
    private func assertReadAsTheReference(_ source: String, file: StaticString = #filePath, line: UInt = #line) -> Bool {
        guard let (keyword, cursor) = cursor(of: source) else { return false }
        let read = MapReadingEquivalence.outcome { () throws(MermaidDiagramReadError) in
            ReferenceIshikawaDiagram(try IshikawaParser.parse(keyword: keyword, endingAt: cursor, limits: .standard))
        }
        let expected = MapReadingEquivalence.outcome { () throws(MermaidDiagramReadError) in
            try ReferenceIshikawaParser.parse(keyword: keyword, endingAt: cursor, limits: .standard)
        }
        XCTAssertEqual(read, expected, source, file: file, line: line)
        return true
    }

    func testEveryTextAndItsChangesReadAsTheFrozenReaderReadThem() throws {
        let own = try MapReadingEquivalence.everyText().filter { text in cursor(of: text) != nil }
        XCTAssertFalse(own.isEmpty)
        var mutations = MapReadingMutations(seed: 0x15_41_CA_3A, tokens: Self.tokens)
        var comparedCount = 0
        for text in own {
            if assertReadAsTheReference(text) { comparedCount += 1 }
            for _ in 0..<600 where assertReadAsTheReference(mutations.mutated(text)) { comparedCount += 1 }
        }
        XCTAssertGreaterThan(comparedCount, 1_000)
    }

    func testRandomDiagramsReadAsTheFrozenReaderReadThem() {
        var random = MapReadingMutations(seed: 0x15_41_0002, tokens: [])
        let blanks = [" ", "  ", "\t", "\u{00A0}", "\u{2003}", "\u{3000}", "\u{FEFF}", "\u{000B}", "\u{000C}", "\r"]
        let texts = ["Effect", "Cause", "Sub cause", "é café", "🚀", "x  ", " trailing\u{2003}", "%% not a comment?", "ishikawa again", "a\u{0085}b"]
        for _ in 0..<2_500 {
            var text = ["ishikawa-beta", "ishikawa", "Ishikawa-Beta extra", "ishikawa-beta  "][random.below(4)] + "\n"
            for _ in 0..<(1 + random.below(18)) {
                let indentation = (0..<random.below(6)).map { _ in blanks[random.below(blanks.count)] }.joined()
                text += indentation + texts[random.below(texts.count)] + ["\n", "\n\n", "\n%% c\n", "\u{2028}", "\n \n"][random.below(5)]
            }
            assertReadAsTheReference(text)
        }
    }

    /// Texts that start, end and are made of each white space of ASCII and beyond it, after the indentation, read as the
    /// frozen reader reads them: the reader trims them on their bytes where they are ASCII.
    func testTextsEndingInEveryWhiteSpaceReadAsTheFrozenReaderReadThem() {
        let blanks = ["\t", "\u{000B}", "\u{000C}", " ", "\u{00A0}", "\u{2003}", "\u{0085}", "\u{FEFF}"]
        for blank in blanks {
            for other in blanks {
                assertReadAsTheReference("ishikawa-beta\nEffect\(blank)\n  Cause\(blank)\(other)\n    x\(other)y\(blank)\n  \(blank)\n  z\(other)\n")
                assertReadAsTheReference("ishikawa\n\(blank)Effect \(other)\n  \(other)Cause\n")
            }
        }
    }

    /// A long line, many causes, deep nesting and runs of white space read as the frozen reader reads them, each in well
    /// under a second.
    func testHostileDiagramsReadAsTheFrozenReaderQuickly() {
        let cases = [
            "ishikawa-beta\n" + String(repeating: "a", count: 45_000),
            "ishikawa-beta\nEffect\n" + String(repeating: "  Cause\n", count: 5_000),
            "ishikawa-beta\nEffect\n" + (0..<280).map { depth in String(repeating: " ", count: depth + 2) + "c\(depth)\n" }.joined(),
            "ishikawa-beta\nEffect\n" + String(repeating: "\u{3000}", count: 15_000) + "x",
            "ishikawa-beta\n" + String(repeating: "%% c\n\n", count: 8_000),
        ]
        for source in cases {
            assertReadAsTheReference(source)
            guard let (keyword, cursor) = cursor(of: source) else {
                XCTFail("an Ishikawa diagram: \(source.prefix(40))")
                continue
            }
            let start = Date()
            _ = try? IshikawaParser.parse(keyword: keyword, endingAt: cursor, limits: .standard)
            XCTAssertLessThan(Date().timeIntervalSince(start), 1, String(source.prefix(40)))
        }
    }

    /// Diagrams read from texts that differ before and around their lines are equal when their nodes are, and a text
    /// beyond ASCII is trimmed as Foundation trims it, its bytes kept after the text's.
    func testDiagramsCompareByTheirNodesWhereverTheirTextsAre() throws {
        let first = try IshikawaReading.diagram("ishikawa-beta\nEffect\n  Café\u{2003}\n    deep")
        let second = try IshikawaReading.diagram("ishikawa\n  Effect  \n\u{00A0}Café\u{2003}\n\u{00A0}\u{00A0}deep\n")
        XCTAssertEqual(first, second)
        XCTAssertEqual(first.nodes.map(\.text), ["Effect", "Café", "deep"])
        XCTAssertEqual(first.nodes.map(\.parentIndex), [nil, 0, 1])
        XCTAssertEqual(first.nodes.map(\.childIndices), [[1], [2], []])
        XCTAssertNotEqual(first, try IshikawaReading.diagram("ishikawa-beta\nEffect\n  Cafe\n    deep"))
        XCTAssertNotEqual(first, try IshikawaReading.diagram("ishikawa-beta\nEffect\n  Café\n  deep"))
    }

    /// Many causes under one category, deep nesting and many categories are laid out across and down, each in well
    /// under a second.
    func testHostileDiagramsAreLaidOutQuickly() throws {
        let typography = DiagramTypography(font: DiagramFont(postScriptName: nil, size: 16))
        let cases = [
            "ishikawa-beta\nEffect\n  Category\n" + String(repeating: "    Cause\n", count: 4_000),
            "ishikawa-beta\nEffect\n" + (0..<250).map { depth in String(repeating: " ", count: depth + 2) + "c\(depth)\n" }.joined(),
            "ishikawa-beta\nEffect\n" + (0..<1_500).map { index in "  Category \(index)\n    Cause\n" }.joined(),
        ]
        for source in cases {
            let diagram = try IshikawaReading.diagram(source)
            let start = Date()
            let across = IshikawaLayoutEngine.layout(diagram, typography: typography)
            let down = IshikawaLayoutEngine.layout(diagram, typography: typography, maximumWidth: 300)
            XCTAssertLessThan(Date().timeIntervalSince(start), 1, String(source.prefix(40)))
            XCTAssertGreaterThan(across.size.width, 0)
            XCTAssertGreaterThan(down.size.height, 0)
        }
    }
}
