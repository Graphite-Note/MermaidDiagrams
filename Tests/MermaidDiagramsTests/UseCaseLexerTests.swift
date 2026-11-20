/**
 * File: UseCaseLexerTests.swift
 * -----------------------------
 * Layer: Tests
 * Description: The use case lexer gives Mermaid's tokens, as Pele's port of Mermaid's usecase.lexer.spec.ts and its
 *              worst cases (tests/usecase/stress.test.ts) check them.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 19/11/2026
 */

import XCTest
@testable import MermaidDiagrams

final class UseCaseLexerTests: XCTestCase {
    private func assertTokens(_ source: String, _ expected: [(String, String)], file: StaticString = #filePath, line: UInt = #line) {
        guard let tokens = UseCaseReading.tokens(source) else { return XCTFail("not lexed: \(source)", file: file, line: line) }
        XCTAssertEqual(tokens.map(\.0), expected.map(\.0), source, file: file, line: line)
        XCTAssertEqual(tokens.map(\.1), expected.map(\.1), source, file: file, line: line)
    }

    func testTheLongestOperatorAndDelimiterWin() {
        assertTokens("--|> ..> <<Human>> ::: ---> <--- --o o-- --x x-- --", [
            ("GENERALIZATION", "--|>"), ("DEPENDENCY_ARROW", "..>"), ("STEREOTYPE_START", "<<"), ("STEREOTYPE_TEXT", "Human"),
            ("STEREOTYPE_END", ">>"), ("CLASS_SEPARATOR", ":::"), ("FORWARD_SOLID", "--->"), ("BACKWARD_SOLID", "<---"),
            ("FORWARD_CIRCLE", "--o"), ("BACKWARD_CIRCLE", "o--"), ("FORWARD_CROSS", "--x"), ("BACKWARD_CROSS", "x--"), ("MARKERLESS_SOLID", "--"),
        ])
    }

    func testKeywordsStayOutOfLongerIdentifiersAndIncludeAndExtendIgnoreCase() {
        assertTokens("actor actorName include INCLUDE Include included extend EXTEND extended", [
            ("ACTOR", "actor"), ("IDENTIFIER", "actorName"), ("INCLUDE", "include"), ("INCLUDE", "INCLUDE"), ("INCLUDE", "Include"),
            ("IDENTIFIER", "included"), ("EXTEND", "extend"), ("EXTEND", "EXTEND"), ("IDENTIFIER", "extended"),
        ])
    }

    func testEachPhysicalLineBreakIsOneToken() {
        for lineBreak in ["\n", "\r\n", "\r"] {
            XCTAssertEqual(UseCaseReading.tokens(lineBreak + lineBreak)?.map(\.0), ["NEWLINE", "NEWLINE"], lineBreak.debugDescription)
        }
    }

    func testMarkdownRunsOverLinesAndHoldsCommentLookalikes() {
        assertTokens("\"`first\n%% still markdown\nlast`\"", [("MARKDOWN_STRING", "\"`first\n%% still markdown\nlast`\"")])
    }

    func testCommentsStartOnlyALineAndPercentPairsAfterTextArePunctuation() {
        assertTokens("  %% comment\n", [("COMMENT", "%% comment"), ("NEWLINE", "\n")])
        XCTAssertEqual(UseCaseReading.tokens("A %% data")?.map(\.0), ["IDENTIFIER", "PERCENT", "PERCENT", "IDENTIFIER"])
    }

    func testJSONIsBalancedOutsideItsStrings() {
        let source = "json Payload@{\n  \"text\": \"} \\\" {\",\n  \"nested\": {\"items\": [1, 2]}\n}:::data"
        XCTAssertEqual(UseCaseReading.tokens(source)?.map(\.0), ["JSON_DECLARATION_START", "JSON_OBJECT_LITERAL", "CLASS_SEPARATOR", "IDENTIFIER"])
        let text = UseCaseCharacters(units: Array(source.utf16))
        let tokens = try? UseCaseLexer.tokens(of: text)
        XCTAssertEqual(tokens?.starts[1], 13)
        XCTAssertEqual(tokens.map { tokens in text.line(of: tokens.ends[1] - 1) }, 4)
    }

    func testUnclosedJSONMarkdownAndStereotypesAreReadOnce() {
        let json = UseCaseReading.tokens("json Payload@{" + String(repeating: "{", count: 32_000))
        XCTAssertEqual(json?.last?.0, "UNCLOSED_JSON_OBJECT_LITERAL")
        XCTAssertEqual(UseCaseReading.tokens(String(repeating: "\"`x", count: 32_000))?.map(\.0), ["UNCLOSED_MARKDOWN_STRING"])
        XCTAssertEqual(UseCaseReading.tokens("<<" + String(repeating: "x", count: 128_000))?.map(\.0), ["STEREOTYPE_START", "UNCLOSED_STEREOTYPE_TEXT"])
    }

    func testStringsColorsUnitsAndEscapedCommasKeepTheirText() {
        assertTokens("\"%%\" 'plain' #f96 4px 50% red\\,blue", [
            ("PLAIN_STRING", "\"%%\""), ("PLAIN_STRING", "'plain'"), ("HASH_COLOR", "#f96"), ("IDENTIFIER", "4px"), ("IDENTIFIER", "50"),
            ("PERCENT", "%"), ("IDENTIFIER", "red"), ("CSS_ESCAPED_COMMA", "\\,"), ("IDENTIFIER", "blue"),
        ])
    }

    func testLeftOverPunctuationAndNonASCIICharactersAreLabelText() {
        assertTokens("*bold* ; < > ` \\ Ärlig 日本語", [
            ("CSS_PUNCTUATION", "*"), ("IDENTIFIER", "bold"), ("CSS_PUNCTUATION", "*"), ("LABEL_PUNCTUATION", ";"), ("LABEL_PUNCTUATION", "<"),
            ("LABEL_PUNCTUATION", ">"), ("LABEL_PUNCTUATION", "`"), ("LABEL_PUNCTUATION", "\\"), ("LABEL_SYMBOL", "Ä"), ("IDENTIFIER", "rlig"),
            ("LABEL_SYMBOL", "日本語"),
        ])
        assertTokens("<-- --> ..> ::: @{ \\,", [("BACKWARD_SOLID", "<--"), ("FORWARD_SOLID", "-->"), ("DEPENDENCY_ARROW", "..>"),
                                              ("CLASS_SEPARATOR", ":::"), ("METADATA_START", "@{"), ("CSS_ESCAPED_COMMA", "\\,")])
    }

    func testIdentifiersMayStartWithADigitWhileDecimalsStayNumbers() {
        assertTokens("1 1mg a1 _x", [("IDENTIFIER", "1"), ("IDENTIFIER", "1mg"), ("IDENTIFIER", "a1"), ("IDENTIFIER", "_x")])
        assertTokens("1.5 1.5px .5", [("NUMBER", "1.5"), ("NUMBER", "1.5px"), ("NUMBER", ".5")])
    }

    func testAccessibilityLinesAndBlocksStartALine() {
        assertTokens("accTitle: Title here\naccDescr {\n a\n}", [("ACC_TITLE_LINE", "accTitle: Title here"), ("NEWLINE", "\n"),
                                                                 ("ACC_DESCR_BLOCK", "accDescr {\n a\n}")])
        XCTAssertEqual(UseCaseReading.tokens("A accTitle: x")?.map(\.0), ["IDENTIFIER", "IDENTIFIER", "COLON", "IDENTIFIER"])
    }

    /// A plain string unclosed on its line, and `<<` at the end of a line, start no token.
    func testAnUnclosedStringOrStereotypeIsAnErrorAtItsLine() {
        XCTAssertNil(UseCaseReading.tokens("A(\"x"))
        XCTAssertEqual(UseCaseReading.problem("usecase-beta\nBroken(\"First\nSecond\")")?.line, 2)
        XCTAssertEqual(UseCaseReading.problem("usecase-beta\nactor A\nA <<\nB")?.problem, .unexpectedCharacter)
        XCTAssertEqual(UseCaseReading.problem("usecase-beta\nactor A\nA <<\nB")?.line, 3)
    }

    /// Pele's worst cases for its lexer (tests/usecase/stress.test.ts): each is read in well under a second.
    func testPelesWorstCasesForTheLexerAreQuick() {
        let size = 50_000
        let header = "usecase-beta\n"
        let cases = [
            header + "A " + String(repeating: "-", count: size) + " B", header + String(repeating: "-- ", count: size / 3),
            header + String(repeating: "A <<x\n", count: size / 6), header + "A " + String(repeating: "<<", count: size / 2),
            header + String(repeating: "A <<x\n", count: size / 6) + ">>", header + String(repeating: "accDescr {\n", count: size / 11),
            header + String(repeating: "accDescr {\n", count: size / 11) + "}",
            header + String(repeating: "accTitle" + String(repeating: " ", count: 40) + "\n", count: size / 49),
            header + String(repeating: "\"`x", count: size / 3), header + String(repeating: "A \"x", count: size / 4),
            header + "json P@" + String(repeating: "{", count: size), header + String(repeating: "json P@{ \"a\": \n", count: size / 15),
            header + String(repeating: "A" + String(repeating: " ", count: 40) + "%%\n", count: size / 44),
            header + String(repeating: String(repeating: " ", count: 100) + String(repeating: "%", count: 100) + "\n", count: size / 201),
            header + String(repeating: "endx forx notex truex classDefx jsonx ", count: size / 38), header + String(repeating: "é日", count: size / 2),
        ]
        for source in cases {
            let started = Date()
            _ = UseCaseReading.tokens(source)
            XCTAssertLessThan(Date().timeIntervalSince(started), 1, String(source.prefix(40)))
        }
    }
}
