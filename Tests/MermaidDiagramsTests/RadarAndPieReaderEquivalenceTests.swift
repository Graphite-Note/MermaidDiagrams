/**
 * File: RadarAndPieReaderEquivalenceTests.swift
 * ---------------------------------------------
 * Layer: Tests
 * Description: The radar chart and pie chart readers give the charts 0.7.0's readers gave, or their errors with their
 *              lines, on every corpus input and spec text, thousands of them changed at random, random charts of every
 *              statement, escaped and unclosed strings, and long and many entries in time.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 25/11/2026
 */

import XCTest
@testable import MermaidDiagrams

final class RadarAndPieReaderEquivalenceTests: XCTestCase {
    private static let radarTokens = ["radar-beta", "radar-beta:", "axis A, B, C\n", "axis a[\"Label\"], b['Other']\n", "curve c{1, 2, 3}\n",
                                      "curve d[\"D\"]{A: 1, B: 2, C: 3}\n", "curve e{C 1, A 2}\n", "showLegend true\n", "showLegend falsecurve",
                                      "graticule polygon\n", "graticule circle", "ticks 5\n", "max 10, min 0\n", "{", "}", "[\"\\\"esc\\\"\"]",
                                      "[\"unclosed", "axes", "axis-", "axis_1", "01", "1.5", "1.", ".5", "true", "polygon", "maxed", "title Skills\n"]
    private static let pieTokens = ["pie", "pie showData", "showData", "\"Dogs\" : 386\n", "'Cats' : 85.5\n", "\"a\\\"b\" : 1\n", "\"line\\nbreak\" : 2\n",
                                    "\"\" : 0\n", "\"neg\" : -1\n", "\"lead\" : 01\n", "\"dot\" : 1.\n", "\"Dogs\" : 3\n", "\"unclosed : 1\n",
                                    "title Pets\n", "accTitle: t\n", "accDescr { d\n}\n", "\"é\" : 4\n", "'mixed\" : 5\n"]

    @discardableResult
    private func assertRadarReadAsTheReference(_ source: String, file: StaticString = #filePath, line: UInt = #line) -> Bool {
        guard let cursor = MapReadingEquivalence.cursor(of: source, readAs: .radar) else { return false }
        let read = MapReadingEquivalence.outcome { () throws(MermaidDiagramReadError) in try RadarChartParser.parse(cursor, limits: .standard) }
        let expected = MapReadingEquivalence.outcome { () throws(MermaidDiagramReadError) in try ReferenceRadarChartParser.parse(cursor, limits: .standard) }
        XCTAssertEqual(read, expected, String(source.prefix(200)), file: file, line: line)
        return true
    }

    @discardableResult
    private func assertPieReadAsTheReference(_ source: String, file: StaticString = #filePath, line: UInt = #line) -> Bool {
        guard let cursor = MapReadingEquivalence.cursor(of: source, readAs: .pieChart) else { return false }
        let read = MapReadingEquivalence.outcome { () throws(MermaidDiagramReadError) in try PieChartParser.parse(cursor, limits: .standard) }
        let expected = MapReadingEquivalence.outcome { () throws(MermaidDiagramReadError) in try ReferencePieChartParser.parse(cursor, limits: .standard) }
        XCTAssertEqual(read, expected, String(source.prefix(200)), file: file, line: line)
        return true
    }

    func testEveryTextAndItsChangesReadAsTheFrozenReadersReadThem() throws {
        let every = try MapReadingEquivalence.everyText()
        var radarCount = 0
        for text in MapReadingEquivalence.texts(readAs: .radar, among: every, mutationCount: 200, tokens: Self.radarTokens, seed: 0x7AD_A001)
            where assertRadarReadAsTheReference(text) {
            radarCount += 1
        }
        var pieCount = 0
        for text in MapReadingEquivalence.texts(readAs: .pieChart, among: every, mutationCount: 200, tokens: Self.pieTokens, seed: 0x919_E001)
            where assertPieReadAsTheReference(text) {
            pieCount += 1
        }
        XCTAssertGreaterThan(radarCount, 1_000)
        XCTAssertGreaterThan(pieCount, 1_000)
    }

    /// Radar charts of every statement: axes with and without labels, curves of numbers and of named entries (fewer and
    /// more than the reader searches, in any order, repeated, missing, before the axes), options, and titles.
    func testRandomRadarChartsReadAsTheFrozenReaderReadThem() {
        var random = MapReadingMutations(seed: 0x7AD_0002, tokens: [])
        let axisNames = ["A", "B", "speed", "axis_2", "x-y", "Kelvin", "é", "_u"]
        let labels = ["", "[\"Label\"]", "['Single']", "[\"esc \\\"q\\\"\"]", "[\"line\\nbreak\"]", "[ \"spaced\" ]", "[\"é\"]"]
        for _ in 0..<2_000 {
            var text = ["radar-beta\n", "radar-beta:\n", "radar-beta :\n"][random.below(3)]
            let axisCount = random.below(6)
            if axisCount > 0 {
                text += "axis " + (0..<axisCount).map { index in axisNames[index] + labels[random.below(labels.count)] }.joined(separator: ", ") + "\n"
            }
            for curve in 0..<(1 + random.below(4)) {
                let entryCount = random.below(3) == 0 ? 17 + random.below(6) : 1 + random.below(6)
                let isNamed = random.below(2) == 0
                let entries = (0..<entryCount).map { _ in
                    (isNamed ? axisNames[random.below(axisNames.count)] + [": ", " ", ":"][random.below(3)] : "") + ["1", "0", "2.5", "10", "01"][random.below(5)]
                }
                text += "curve c\(curve)" + labels[random.below(labels.count)] + "{" + entries.joined(separator: [", ", ",\n", " , "][random.below(3)]) + "}\n"
            }
            if random.below(3) == 0 { text += ["showLegend true", "ticks 3, max 20", "graticule polygon", "min 1", "showLegend nope"][random.below(5)] + "\n" }
            if random.below(4) == 0 { text += "title A chart\n" }
            assertRadarReadAsTheReference(text)
        }
    }

    func testRandomPieChartsReadAsTheFrozenReaderReadThem() {
        var random = MapReadingMutations(seed: 0x919_0002, tokens: [])
        let labels = ["\"Dogs\"", "'Cats'", "\"a \\\"quoted\\\" b\"", "\"tab\\there\"", "\"multi\nline\"", "\"Été\"", "\"\"", "\"back\\\\slash\"", "'it\\'s'"]
        let values = ["1", "0", "42.96", "-3", "007", "1.", "1e3", "2"]
        for _ in 0..<2_000 {
            var text = random.below(3) == 0 ? "pie showData\n" : "pie\n"
            if random.below(3) == 0 { text += "title Pets  adopted\n" }
            for _ in 0..<(1 + random.below(8)) {
                text += "  " + labels[random.below(labels.count)] + [" : ", ":", "  :  "][random.below(3)] + values[random.below(values.count)] + "\n"
            }
            assertPieReadAsTheReference(text)
        }
    }

    /// Long labels, many axes, curves and entries, and long strings without their end are read as the frozen readers
    /// read them, each in well under a second.
    func testHostileChartsReadAsTheFrozenReadersQuickly() {
        let radars = [
            "radar-beta\naxis " + (0..<900).map { index in "a\(index)" }.joined(separator: ", ") + "\ncurve c{" + (0..<900).map { index in "a\(899 - index): 1" }.joined(separator: ", ") + "}",
            "radar-beta\naxis a\ncurve c{" + String(repeating: "1, ", count: 9_000) + "1}",
            "radar-beta\naxis a[\"" + String(repeating: "l", count: 40_000) + "\"]",
            "radar-beta\naxis a[\"" + String(repeating: "l", count: 40_000),
        ]
        let pies = [
            "pie\n" + (0..<2_000).map { index in "\"slice \(index)\" : \(index)" }.joined(separator: "\n"),
            "pie\n\"" + String(repeating: "label ", count: 8_000) + "\" : 1",
            "pie\n\"" + String(repeating: "\\\"", count: 20_000),
        ]
        for source in radars {
            XCTAssertTrue(assertRadarReadAsTheReference(source), String(source.prefix(40)))
            guard let cursor = MapReadingEquivalence.cursor(of: source, readAs: .radar) else { continue }
            let start = Date()
            _ = try? RadarChartParser.parse(cursor, limits: .standard)
            XCTAssertLessThan(Date().timeIntervalSince(start), 1, String(source.prefix(40)))
        }
        for source in pies {
            XCTAssertTrue(assertPieReadAsTheReference(source), String(source.prefix(40)))
            guard let cursor = MapReadingEquivalence.cursor(of: source, readAs: .pieChart) else { continue }
            let start = Date()
            _ = try? PieChartParser.parse(cursor, limits: .standard)
            XCTAssertLessThan(Date().timeIntervalSince(start), 1, String(source.prefix(40)))
        }
    }
}
