/**
 * File: XYChartLexerEquivalenceTests.swift
 * ----------------------------------------
 * Layer: Tests
 * Description: The XY chart lexer gives the tokens 0.7.0's lexer gave, kind, start, end and line, on every corpus
 *              input and spec text, thousands of them changed at random, random charts of every statement with line
 *              breaks of every kind, and long ones in time; the parser then reads the charts the corpora draw.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 25/11/2026
 */

import XCTest
@testable import MermaidDiagrams

final class XYChartLexerEquivalenceTests: XCTestCase {
    private static let tokens = ["xychart-beta", "xychart", "xychart-beta horizontal\n", "title \"Sales\"\n", "title Sales 2024\n",
                                 "x-axis [jan, feb, \"mar ch\"]\n", "x-axis \"Months\" 1 --> 12\n", "y-axis \"Revenue\" 0 --> 10000\n",
                                 "y-axis -5.5 --> +.5\n", "line [1, 2.5, -3]\n", "bar \"Bars\" [4, 5, 6]\n", "accTitle: t\n", "accDescr: d\n",
                                 "accDescr {\nblock\n}\n", "accDescr  \n : x\n", "%% c\n", "a%%b\n", "é%%x\n", "\u{1F680}%%x\n", "}%%\n", "\r\n", "\r",
                                 "\u{3000}", "\u{A0}", "-->", "--", "[", "]", "\"", "+", "=", "*", "#", "_", ".", "&", ";", "vertical", "HORIZONTAL", "barx",
                                 "lines"]

    private func tokens(_ lexed: [XYChartToken]) -> [String] {
        lexed.map { token in "\(token.kind) \(token.start) \(token.end) \(token.line)" }
    }

    @discardableResult
    private func assertLexedAsTheReference(_ source: String, file: StaticString = #filePath, line: UInt = #line) -> Bool {
        guard let cursor = MapReadingEquivalence.cursor(of: source, readAs: .xyChart) else { return false }
        XCTAssertEqual(tokens(XYChartLexer.tokens(after: cursor)), tokens(ReferenceXYChartLexer.tokens(after: cursor)), String(source.prefix(200)),
                       file: file, line: line)
        return true
    }

    func testEveryTextAndItsChangesAreLexedAsTheFrozenLexerLexedThem() throws {
        let texts = MapReadingEquivalence.texts(readAs: .xyChart, among: try MapReadingEquivalence.everyText(), mutationCount: 150, tokens: Self.tokens,
                                                seed: 0x8C_0001)
        var comparedCount = 0
        for text in texts where assertLexedAsTheReference(text) { comparedCount += 1 }
        XCTAssertGreaterThan(comparedCount, 1_000)
    }

    /// Charts of every statement, each line ending in a line feed, a carriage return, both, or several, with comments,
    /// strings across lines and accessibility blocks, so that every token's line is counted through each.
    func testRandomChartsAreLexedAsTheFrozenLexerLexedThem() {
        var random = MapReadingMutations(seed: 0x8C_0002, tokens: [])
        let statements = ["title \"A\nchart\"", "title Plain", "x-axis [a, \"b c\", d]", "x-axis \"t\" 0 --> 100", "y-axis 1.5 --> -2", "line [1, 2, 3]",
                          "bar [.5, +4, -6.25]", "accTitle: x", "accDescr {\nmany\nlines\n}", "%% comment", "é%%comment", "horizontal", "lines [1]"]
        let breaks = ["\n", "\r\n", "\r", "\n\n", "\n\r\n", " \n", "\t\r"]
        for _ in 0..<2_000 {
            var text = ["xychart-beta", "xychart-beta horizontal", "xychart"][random.below(3)] + breaks[random.below(breaks.count)]
            for _ in 0..<(1 + random.below(10)) { text += statements[random.below(statements.count)] + breaks[random.below(breaks.count)] }
            assertLexedAsTheReference(text)
        }
    }

    func testHostileChartsAreLexedAsTheFrozenLexerQuickly() {
        let cases = [
            "xychart-beta\nline [" + Array(repeating: "1.5", count: 9_000).joined(separator: ",") + "]",
            "xychart-beta\ntitle \"" + String(repeating: "t\n", count: 20_000),
            "xychart-beta\n" + String(repeating: "\r\n", count: 20_000) + "bar [1]",
            "xychart-beta\naccDescr {" + String(repeating: "d", count: 40_000),
        ]
        for source in cases {
            XCTAssertTrue(assertLexedAsTheReference(source), String(source.prefix(40)))
            guard let cursor = MapReadingEquivalence.cursor(of: source, readAs: .xyChart) else { continue }
            let start = Date()
            _ = XYChartLexer.tokens(after: cursor)
            XCTAssertLessThan(Date().timeIntervalSince(start), 1, String(source.prefix(40)))
        }
    }
}
