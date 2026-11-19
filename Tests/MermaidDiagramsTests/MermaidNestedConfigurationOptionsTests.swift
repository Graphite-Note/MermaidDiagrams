/**
 * File: MermaidNestedConfigurationOptionsTests.swift
 * --------------------------------------------------
 * Layer: Tests
 * Description: Options inside an option that is a mapping, and options written as YAML flow collections in the front
 *              matter, read as Pele's YAML reader reads them.
 *
 * Authors: Bahey Shalash
 * Version: 0.2
 * Date: 19/11/2026
 */

import XCTest
@testable import MermaidDiagrams

final class MermaidNestedConfigurationOptionsTests: XCTestCase {
    private func read(_ source: String, section: String = "xyChart") -> MermaidConfigurationOptions {
        MermaidConfigurationOptions(section: section, in: Array(source.utf8))
    }

    func testAMappingInsideTheSectionGivesItsOptionsByTheirPath() {
        let options = read("---\nconfig:\n  xyChart:\n    width: 300\n    xAxis:\n      showLabel: false\n      deeper:\n        value: 3\n    yAxis:\n      showTick: false\n---\nxychart")
        XCTAssertEqual(options.values, ["width": .number(300), "xAxis": .collection, "yAxis": .collection])
        XCTAssertEqual(options.nestedValues, ["xAxis.showLabel": .boolean(false), "xAxis.deeper": .collection, "xAxis.deeper.value": .number(3),
                                              "yAxis.showTick": .boolean(false)])
    }

    func testAFlowMappingOfTheSectionIsReadWhereverItIsWritten() {
        let inline = read("---\nconfig:\n  gitGraph: {showBranches: false, mainBranchName: \"trunk\", rotateCommitLabel: true}\n---\n", section: "gitGraph")
        XCTAssertEqual(inline.values, ["showBranches": .boolean(false), "mainBranchName": .text("trunk"), "rotateCommitLabel": .boolean(true)])
        let jsonLike = read("---\nconfig: {\"gitGraph\": {\"showBranches\": false, \"nested\": {\"a\": 1}}, \"theme\": \"dark\"}\n---\n", section: "gitGraph")
        XCTAssertEqual(jsonLike.values, ["showBranches": .boolean(false), "nested": .collection])
        XCTAssertEqual(jsonLike.nestedValues, ["nested.a": .number(1)])
        let option = read("---\nconfig:\n  xyChart:\n    xAxis: {showLabel: false, showTick: false}\n    width: 400\n---\n")
        XCTAssertEqual(option.values, ["xAxis": .collection, "width": .number(400)])
        XCTAssertEqual(option.nestedValues, ["xAxis.showLabel": .boolean(false), "xAxis.showTick": .boolean(false)])
    }

    func testAFlowMappingMayRunOverSeveralLinesAndTheLinesAfterItAreStillRead() {
        let options = read("---\nconfig:\n  xyChart: {\n    width: 300, # the width\n    height: 200,\n    yAxis: {showTitle: false}\n  }\n  other:\n    width: 9\n---\n")
        XCTAssertEqual(options.values, ["width": .number(300), "height": .number(200), "yAxis": .collection])
        XCTAssertEqual(options.nestedValues, ["yAxis.showTitle": .boolean(false)])
        let after = read("---\nconfig:\n  gitGraph: {showBranches: false}\ntitle: kept\n  xyChart:\n    width: 1\n---\n", section: "gitGraph")
        XCTAssertEqual(after.values, ["showBranches": .boolean(false)])
    }

    func testFlowScalarsAreBooleansNumbersNullAndText() {
        let options = read("---\nconfig:\n  xyChart: {a: true, b: 1.5, c: ~, d: left, e: 'it''s', f: \"tab\\there\", g: [1, 2], h: {}, i: 0x1F}\n---\n")
        XCTAssertEqual(options.values["a"], .boolean(true))
        XCTAssertEqual(options.values["b"], .number(1.5))
        XCTAssertNil(options.values["c"], "null sets nothing")
        XCTAssertEqual(options.values["d"], .text("left"))
        XCTAssertEqual(options.values["e"], .text("it's"))
        XCTAssertEqual(options.values["f"], .text("tab\there"))
        XCTAssertEqual(options.values["g"], .collection)
        XCTAssertEqual(options.values["h"], .collection)
        XCTAssertEqual(options.values["i"], .number(31), "A hexadecimal number, as Pele's reader reads it.")
    }

    func testAFlowCollectionThatIsNotValidSetsNothing() {
        for written in ["{a: 1", "{a: 1,, b: 2}", "{, a: 1}", "{a: \"open}", "[1, 2", "{a: \"bad\\q\"}"] {
            let options = read("---\nconfig:\n  gitGraph: \(written)\n---\n", section: "gitGraph")
            XCTAssertTrue(options.values.isEmpty || options.values == ["gitGraph": .collection], written)
            XCTAssertTrue(options.nestedValues.isEmpty, written)
        }
        XCTAssertEqual(read("---\nconfig:\n  gitGraph: {a: 1, b: 2,}\n---\n", section: "gitGraph").values, ["a": .number(1), "b": .number(2)], "One trailing comma closes")
        XCTAssertEqual(read("---\nconfig:\n  gitGraph: {a: 1 b: 2}\n---\n", section: "gitGraph").values, ["a": .text("1 b: 2")], "A plain value runs to the comma or the brace, as in Pele")
    }

    func testADirectivesNestedObjectGivesItsOptionsByTheirPath() {
        let options = read("%%{init: {\"xyChart\": {\"width\": 300, \"xAxis\": {\"showLabel\": false, \"t\": {\"u\": null}}}}}%%\nxychart")
        XCTAssertEqual(options.values, ["width": .number(300), "xAxis": .collection])
        XCTAssertEqual(options.nestedValues, ["xAxis.showLabel": .boolean(false), "xAxis.t": .collection])
        let over = read("---\nconfig:\n  xyChart:\n    xAxis:\n      showLabel: true\n---\n%%{init: {\"xyChart\": {\"xAxis\": {\"showLabel\": false}}}}%%\nxychart")
        XCTAssertEqual(over.nestedValues["xAxis.showLabel"], .boolean(false), "The directive's option is over the front matter's")
    }

    func testNestingBeyondTheLimitAndManyUnclosedCollectionsAreCheap() {
        let deep = String(repeating: "{a: ", count: 200) + "1" + String(repeating: "}", count: 200)
        XCTAssertTrue(read("---\nconfig:\n  xyChart: \(deep)\n---\n").nestedValues.isEmpty)
        let unclosed = "---\nconfig:\n  xyChart:\n" + (0..<4000).map { index in "    k\(index): {a: [\n" }.joined() + "---\n"
        let start = Date()
        _ = read(unclosed)
        XCTAssertLessThan(Date().timeIntervalSince(start), 2, "A text of many collections that never close is read in time proportional to its length")
    }
}
