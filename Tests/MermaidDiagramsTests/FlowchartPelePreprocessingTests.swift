/**
 * File: FlowchartPelePreprocessingTests.swift
 * -------------------------------------------
 * Layer: Tests
 * Description: A flowchart read after Pele's preprocessing: tags' attributes in single quotation marks, directives
 *              removed within and across lines; and a line of many short tokens read in time linear in its length.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 23/11/2026
 */

import XCTest
@testable import MermaidDiagrams

final class FlowchartPelePreprocessingTests: XCTestCase {
    /// preprocess.ts puts a tag's attribute values in single quotation marks before any type reads the text, so a node's
    /// plain text, which takes no `"`, takes `<span style="color:red">`; the tag is dropped from the drawn label.
    func testATagWithDoubleQuotedAttributesIsPlainText() throws {
        let diagram = try FlowchartReading.flowchart("flowchart LR\nA[<span style=\"color:red\">x</span>] --> B[<a href=\"u\" title=\"t\">y</a>]")
        XCTAssertEqual(diagram.nodes.map(\.label.lines), [["x"], ["y"]])
        XCTAssertNotNil(FlowchartReading.readError("flowchart LR\nA[say \"x\"]"), "a quotation mark outside a tag stays refused")
    }

    /// A directive is removed, not blanked: the text on either side of it joins, within a line and across lines.
    func testADirectiveIsRemovedAndTheTextAroundItJoins() throws {
        XCTAssertEqual(try FlowchartReading.flowchart("flowchart LR\nfoo%%{init: {}}%%bar --> B").nodes.map(\.identifier), ["foobar", "B"])
        let acrossLines = try FlowchartReading.flowchart("flowchart LR\nA -->%%{init:\n{\"a\": 1}}%%B")
        XCTAssertEqual(acrossLines.nodes.map(\.identifier), ["A", "B"])
        XCTAssertEqual(acrossLines.edges.count, 1)
        // The lines after the joined one keep the numbers the text shows.
        XCTAssertEqual(FlowchartReading.readError("flowchart TD\nA -->%%{\n init: {}\n}%%B\nA --> ["), .invalidSyntax(line: 5, problem: .unexpectedText("[")))
    }

    /// The lexer's look-ahead (a direction statement later on the line, a link identifier's `@` later in the word) is
    /// found once for the text: a line of 48,000 bytes of one- and two-byte tokens ran for minutes when each token
    /// scanned to the line's end.
    func testALongLineOfShortTokensIsReadQuickly() {
        let lines = [String(repeating: "a:", count: 24_000), String(repeating: "&", count: 48_000), String(repeating: "#", count: 48_000),
                     "style A " + String(repeating: "a:", count: 24_000), String(repeating: "A & ", count: 12_000) + "B"]
        for line in lines {
            let started = Date()
            _ = try? MermaidDiagramReader.read("graph TD\n" + line + " --> B", limits: .standard)
            XCTAssertLessThan(Date().timeIntervalSince(started), 3, String(line.prefix(12)))
        }
    }
}
