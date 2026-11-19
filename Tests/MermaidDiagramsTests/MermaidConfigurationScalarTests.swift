/**
 * File: MermaidConfigurationScalarTests.swift
 * -------------------------------------------
 * Layer: Tests
 * Description: The front matter's plain values read as Pele's YAML reader reads them, and front matters of many flow
 *              collections read in full.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 19/11/2026
 */

import XCTest
@testable import MermaidDiagrams

final class MermaidConfigurationScalarTests: XCTestCase {
    private func read(_ source: String, section: String = "sankey") -> MermaidConfigurationOptions {
        MermaidConfigurationOptions(section: section, in: Array(source.utf8))
    }

    func testPlainValuesInTheBlockFormAreReadAsPeleReadsThem() {
        let options = read("""
        ---
        config:
          sankey:
            upper: TRUE
            capital: False
            absent: NULL
            tilde: ~
            hexadecimal: 0x1F
            octal: -0o17
            binary: +0b101
            infinite: .inf
            text: 0x1G
        ---
        sankey-beta
        """)
        XCTAssertEqual(options.values["upper"], .boolean(true))
        XCTAssertEqual(options.values["capital"], .boolean(false))
        XCTAssertNil(options.values["absent"], "null in any of its spellings is no option.")
        XCTAssertNil(options.values["tilde"])
        XCTAssertEqual(options.values["hexadecimal"], .number(31))
        XCTAssertEqual(options.values["octal"], .number(-15))
        XCTAssertEqual(options.values["binary"], .number(5))
        XCTAssertEqual(options.values["infinite"], .number(.infinity))
        XCTAssertEqual(options.values["text"], .text("0x1G"))
    }

    func testPlainValuesInAFlowMappingAreReadTheSameWay() {
        let options = read("---\nconfig:\n  sankey: {showValues: FALSE, linkColor: Null, nodeWidth: 0x14, number: .NaN}\n---\nsankey-beta\n")
        XCTAssertEqual(options.values["showValues"], .boolean(false))
        XCTAssertNil(options.values["linkColor"])
        XCTAssertEqual(options.values["nodeWidth"], .number(20))
        guard case .number(let number) = options.values["number"] else { return XCTFail("`.NaN` is a number.") }
        XCTAssertTrue(number.isNaN)
        let escapes = read("---\nconfig:\n  sankey: {prefix: \"a\\Lb\\Pc\"}\n---\nsankey-beta\n")
        XCTAssertEqual(escapes.values["prefix"], .text("a\u{2028}b\u{2029}c"), "YAML's line and paragraph separator escapes.")
    }

    func testASankeyDiagramTakesTheOptionsSoWritten() throws {
        let source = "---\nconfig:\n  sankey:\n    showValues: False\n    linkColor: null\n    nodeWidth: 0x14\n---\nsankey-beta\nA,B,5\n"
        guard case .sankey(let sankey) = try MermaidDiagramReader.read(source, limits: .standard) else { return XCTFail("A Sankey diagram.") }
        XCTAssertFalse(sankey.options.showsValues, "Pele hides the values for `False`.")
        XCTAssertEqual(sankey.options.linkColor, SankeyLinkColor.gradient, "A null linkColor is no option, not the text `null`.")
        XCTAssertEqual(sankey.options.nodeWidth, 20)
    }

    func testEveryFlowCollectionOfALongFrontMatterIsRead() {
        // Many collections that read, then the one wanted, then a long rest: each collection costs only its own length.
        let collections = (1...40).map { index in "    option\(index): {value: \(index)}" }.joined(separator: "\n")
        let rest = (1...400).map { index in "# a comment line of the front matter, number \(index)" }.joined(separator: "\n")
        let options = read("---\nconfig:\n  xyChart:\n\(collections)\n    xAxis: {showLabel: false}\n\(rest)\n---\nxychart\n", section: "xyChart")
        XCTAssertEqual(options.nestedValues["xAxis.showLabel"], .boolean(false))
        XCTAssertEqual(options.nestedValues["option40.value"], .number(40))
    }

    func testCollectionsThatNeverCloseStillCostNoMoreThanTheBudget() {
        let unclosed = (1...4_000).map { index in "    option\(index): {value: \(index)," }.joined(separator: "\n")
        let started = Date()
        let options = read("---\nconfig:\n  xyChart:\n\(unclosed)\n---\nxychart\n", section: "xyChart")
        XCTAssertLessThan(Date().timeIntervalSince(started), 2)
        XCTAssertEqual(options.values["option1"], .collection)
    }
}
