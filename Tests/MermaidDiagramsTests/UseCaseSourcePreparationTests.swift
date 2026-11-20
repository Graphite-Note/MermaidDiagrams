/**
 * File: UseCaseSourcePreparationTests.swift
 * -----------------------------------------
 * Layer: Tests
 * Description: The use case reader reads the text Pele's parse hands its parser: comment lines taken out (blank lines
 *              before them too), line breaks made `\n`, a line break added at the end; errors name their line as
 *              written. The expected results are Pele's own, read from its parser.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 19/11/2026
 */

import XCTest
@testable import MermaidDiagrams

final class UseCaseSourcePreparationTests: XCTestCase {
    /// Text cut off at the end breaks on the line break Pele adds there, as in the middle of the text.
    func testTextCutOffAtTheEndBreaksOnTheLineBreakAdded() {
        for source in ["usecase-beta\nA <<", "usecase-beta\nA <<\n", "usecase-beta\nactor A\nfoo bar\nA <<"] {
            XCTAssertEqual(UseCaseReading.problem(source)?.problem, .unexpectedCharacter, source)
        }
        XCTAssertEqual(UseCaseReading.problem("usecase-beta\nactor A\nfoo bar\nA <<")?.line, 4)
    }

    /// The end of the text is on the line after the last one written, where Pele names a statement left open.
    func testAStatementLeftOpenAtTheEndIsNamedOnTheLineAfterTheText() {
        XCTAssertEqual(UseCaseReading.problem("usecase-beta\nsystemBoundary S\nA")?.line, 4)
        XCTAssertEqual(UseCaseReading.problem("usecase-beta\nsystemBoundary S\nA")?.problem, .unexpectedToken(found: "", expected: .token("END")))
        XCTAssertEqual(UseCaseReading.problem("usecase-beta\nA@{\n")?.line, 4)
    }

    /// A comment line inside a JSON object, a metadata block or a Markdown string is gone before they are read.
    func testCommentLinesAreTakenOutBeforeTheTextIsRead() throws {
        let table = try UseCaseReading.lines("json J@{", "%% \"a\": 1,", "\"b\": 2}")
        XCTAssertEqual(table.jsonNodes.first.map { json in UseCaseJSONRow.rows(of: json.value).map(\.key) }, ["b"])
        let actor = try UseCaseReading.lines("actor A@{", "  %% hidden", " type: hollow }")
        XCTAssertEqual(actor.actor("A")?.type, .hollow)
        let oval = try UseCaseReading.lines("A(\"`x", "  %% hidden", "y`\")")
        XCTAssertEqual(oval.useCase("A")?.label, "x\ny")
        XCTAssertNotNil(UseCaseReading.problem("usecase-beta\nA@{\n%%{ x }\n type: hollow }"), "a directive is not a comment line")
    }

    /// An error after comment lines, and the blank lines before them that go with them, names its line as written.
    func testAnErrorAfterCommentLinesNamesItsLineAsWritten() {
        XCTAssertEqual(UseCaseReading.problem("usecase-beta\nA --> B\n\n\n%% c\nfoo bar")?.line, 6)
        XCTAssertEqual(UseCaseReading.problem("usecase-beta\r\n%% c\r\nfoo bar")?.line, 3)
        XCTAssertEqual(UseCaseReading.problem("usecase-beta\nA --> B\nstyle A fill:#f00;\n%% c\n\nfoo bar")?.line, 6)
        XCTAssertEqual(UseCaseReading.problem("usecase-beta\naccDescr {\n%% c\nx\n}\nfoo bar")?.line, 6)
        XCTAssertEqual(UseCaseReading.problem("usecase-beta\n   %%\nfoo bar")?.line, 3)
    }
}
