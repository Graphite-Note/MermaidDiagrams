/**
 * File: SankeyReaderEquivalenceTests.swift
 * ----------------------------------------
 * Layer: Tests
 * Description: The Sankey reader gives the diagram 0.7.0's reader gave, or its error with its line, on every corpus
 *              input and spec text, thousands of them changed at random, random diagrams with names beyond ASCII,
 *              canonically equal spellings and doubled quotation marks, and many, long and colliding names in time.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 25/11/2026
 */

import XCTest
@testable import MermaidDiagrams

final class SankeyReaderEquivalenceTests: XCTestCase {
    private static let tokens = ["sankey-beta\n", "a,b,1\n", "\"quoted, name\",b,2\n", "\"say \"\"hi\"\"\",c,3\n", "x , y ,  4.5\n", "%% comment\n",
                                 "  %% indented comment\n", "%%{init: {}}%%\n", "\n\n", "\r\n", "\r", ",", "\"", "\"\"", "&#35;", "&#1;", "#9;",
                                 "Kelvin \u{212A},K,1\n", "K,Kelvin \u{212A},1\n", "e\u{301},\u{E9},2\n", "\u{3000}", "\u{FEFF}", "1e3", "-2", ".5", "NaN"]

    @discardableResult
    static func assertReadAsTheReference(_ source: String, limits: MermaidDiagramLimits = .standard, file: StaticString = #filePath,
                                         line: UInt = #line) -> Bool {
        // The front end alone, so that a text past the standard limits is compared under the limits given.
        guard let frontEnd = try? MermaidFrontEnd.read(source), frontEnd.typeKeyword == .sankey else { return false }
        let cursor = MermaidTextCursor(frontEnd)
        let read = MapReadingEquivalence.outcome { () throws(MermaidDiagramReadError) in try SankeyParser.parse(cursor, limits: limits) }
        let expected = MapReadingEquivalence.outcome { () throws(MermaidDiagramReadError) in try ReferenceSankeyParser.parse(cursor, limits: limits) }
        XCTAssertEqual(read, expected, String(source.prefix(200)), file: file, line: line)
        return true
    }

    func testEveryTextAndItsChangesReadAsTheFrozenReaderReadThem() throws {
        let texts = MapReadingEquivalence.texts(readAs: .sankey, among: try MapReadingEquivalence.everyText(), mutationCount: 150, tokens: Self.tokens,
                                                seed: 0x5A_4E_E1)
        var comparedCount = 0
        for text in texts where Self.assertReadAsTheReference(text) { comparedCount += 1 }
        XCTAssertGreaterThan(comparedCount, 1_000)
    }

    /// Names in every form a row writes them: plain, quoted with commas and doubled quotation marks, padded, beyond ASCII,
    /// canonically equal to an ASCII name (the Kelvin sign and K) or to each other (é composed and decomposed), with entity
    /// codes, comments and blank lines between the rows.
    func testRandomDiagramsReadAsTheFrozenReaderReadThem() {
        var random = MapReadingMutations(seed: 0x5A_0001, tokens: [])
        let asciiNames = ["Coal", "Bio-conversion", "\"Agricultural 'waste'\"", " padded ", "\"a, b\"", "Losses", "x", "Gas", "&amp;", "a#59;"]
        let otherNames = ["\u{212A}", "K", "\u{E9}t\u{E9}", "e\u{301}te\u{301}", "\"say \"\"hi\"\"\"", "Énergie", "中文", "\u{3000}spaced\u{3000}"]
        let values = ["1", "0.5", "124.729", "1e2", "-3", "", "abc", "  7  "]
        let separators = ["\n", "\n\n", "\n%% a comment\n", "\n   \n", "\r\n"]
        for index in 0..<2_000 {
            let names = index % 3 == 0 ? asciiNames + otherNames : asciiNames
            var text = index % 4 == 0 ? "sankey\n\n" : "sankey-beta\n"
            for row in 0..<(1 + random.below(18)) {
                if row > 0 { text += separators[random.below(separators.count)] }
                text += names[random.below(names.count)] + "," + names[random.below(names.count)] + "," + values[random.below(values.count)]
            }
            if random.below(4) == 0 { text += "\n  \n" }
            Self.assertReadAsTheReference(text)
        }
    }

    /// Rows past the node and link limits are refused as the frozen reader refuses them.
    func testDiagramsPastTheLimitsAreRefusedAlike() {
        let limits = MermaidDiagramLimits(maximumSourceBytes: 1_000_000, maximumNodeCount: 40, maximumEdgeCount: 30, maximumLayoutPointCount: 100_000)
        let manyNodes = "sankey\n" + (0..<25).map { index in "a\(index),b\(index),1" }.joined(separator: "\n")
        let manyLinks = "sankey\n" + (0..<35).map { index in "a\(index % 3),b\(index % 4),1" }.joined(separator: "\n")
        let manyOtherNodes = "sankey\n" + (0..<25).map { index in "é\(index),b\(index),1" }.joined(separator: "\n")
        for source in [manyNodes, manyLinks, manyOtherNodes] { XCTAssertTrue(Self.assertReadAsTheReference(source, limits: limits)) }
    }

    /// Long names, many rows and names whose hashes share their low bits whatever the basis are read as the frozen reader
    /// reads them, the colliding ones in time that grows with their count: ten times the names in at most forty times the
    /// time, where names all falling in one run of slots would take about a hundred times.
    func testManyLongAndCollidingNamesReadAlikeAndInTime() {
        let limits = MermaidDiagramLimits(maximumSourceBytes: 10_000_000, maximumNodeCount: 100_000, maximumEdgeCount: 100_000,
                                          maximumLayoutPointCount: 1_000_000)
        func diagram(_ names: [String]) -> String {
            "sankey\n" + names.enumerated().map { index, name in "\(name),\(names[(index &* 7 &+ 1) % names.count]),\(index)" }.joined(separator: "\n")
        }
        let caseVariants = GraphDiagramNameTableTests.caseVariants(of: "abcdefghijklm")
        let highBitVariants = GraphDiagramNameTableTests.highBitVariants(count: caseVariants.count)
        let longName = String(repeating: "long name ", count: 4_000)
        let sources = [diagram(caseVariants), diagram(highBitVariants), "sankey\n\(longName),\(longName)x,1\n\(longName)x,\(longName),2"]
        for source in sources { XCTAssertTrue(Self.assertReadAsTheReference(source, limits: limits)) }
        func seconds(_ source: String) -> Double {
            let start = Date()
            for _ in 0..<3 { _ = try? MermaidDiagramReader.read(source, limits: limits) }
            return Date().timeIntervalSince(start)
        }
        for names in [caseVariants, highBitVariants] {
            let small = diagram(Array(names.prefix(names.count / 10)))
            _ = seconds(small)
            XCTAssertLessThan(seconds(diagram(names)), max(seconds(small), 0.002) * 40)
        }
    }
}
