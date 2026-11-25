/**
 * File: QuadrantChartLexerTests.swift
 * -----------------------------------
 * Layer: Tests
 * Description: How the quadrant chart's text is cut into tokens, as Mermaid's quadrant lexer cuts it, each token
 *              holding the ranges of the bytes of its text.
 *
 * Authors: felixchvl, Bahey Shalash
 * Version: 0.2
 * Date: 25/11/2026
 */

import XCTest
@testable import MermaidDiagrams

/// How the quadrant chart's text is cut into tokens, as Mermaid's quadrant lexer cuts it.
final class QuadrantChartLexerTests: XCTestCase {
    private func kinds(_ statements: String) throws -> [QuadrantChartTokenKind] {
        try tokens(statements).map(\.kind)
    }

    private func tokens(_ statements: String) throws -> [QuadrantChartToken] {
        var cursor = MermaidTextCursor(bytes: Array(("quadrantChart" + statements).utf8))
        cursor.advance(by: "quadrantChart".utf8.count)
        return try QuadrantChartLexer.tokens(after: cursor).tokens
    }

    /// The text of `range` of `statements` after the keyword.
    private func text(_ range: MermaidTextRange?, of statements: String) -> String? {
        range.map { range in String(decoding: Array(("quadrantChart" + statements).utf8)[range.lowerBound..<range.upperBound], as: UTF8.self) }
    }

    func testKeywordsAndTheArrowTakeTheSpacesAroundThem() throws {
        let tokens = try tokens("\n  x-axis  Low   --->  High")
        XCTAssertEqual(tokens.map(\.kind), [.lineBreak, .xAxis, .letters, .axisArrow, .letters])
        XCTAssertEqual(tokens[1].start, "quadrantChart\n".utf8.count, "From the first space")
        XCTAssertEqual(tokens[3].end, tokens[4].start, "To the next text")
    }

    func testTextIsCutIntoRunsAndSingleCharacters() throws {
        XCTAssertEqual(try kinds("\nquadrant-1 Été 2-b, a_c&*#!"),
                       [.lineBreak, .quadrant1, .otherCharacters, .letters, .otherCharacters, .space, .digits, .hyphen, .letters, .comma, .space,
                        .letters, .otherPunctuation, .letters, .ampersand, .asterisk, .numberSign, .otherPunctuation])
    }

    func testAQuadrantNeedsItsDigitAndAWordItsEnd() throws {
        XCTAssertEqual(try kinds("\nquadrant-5"), [.lineBreak, .letters, .hyphen, .digits])
        XCTAssertEqual(try kinds("\ntitles"), [.lineBreak, .letters])
        XCTAssertEqual(text(try tokens("\ntitle  Hi").last?.content, of: "\ntitle  Hi"), "  Hi")
    }

    func testAPointHoldsItsCoordinatesAsWritten() throws {
        let statements = " A \n : \n [ 0.25 ,1 ]  radius"
        let tokens = try tokens(statements)
        XCTAssertEqual(tokens.map(\.kind), [.space, .letters, .point, .letters])
        XCTAssertEqual(text(tokens[2].content, of: statements), "0.25")
        XCTAssertEqual(text(tokens[2].second, of: statements), "1")
    }

    func testCommentsTakeTheRestOfTheirLineAndTheCharacterBeforeThem() throws {
        XCTAssertEqual(try kinds("\n%% all of it\nA %% the rest"), [.lineBreak, .letters], "The line break before a comment goes with it")
        XCTAssertEqual(try kinds("\nA%% the rest"), [.lineBreak], "A character that starts a token just before %% goes with the comment, as in Mermaid")
    }

    func testACharacterNoRuleTakesIsAnError() {
        XCTAssertThrowsError(try kinds("\n  [x]")) { error in
            XCTAssertEqual(error as? MermaidDiagramReadError, .invalidSyntax(line: 2, problem: .unexpectedText("[x]")))
        }
    }
}
