/**
 * File: QuadrantChartReaderEquivalenceTests.swift
 * -----------------------------------------------
 * Layer: Tests
 * Description: The quadrant reader, whose tokens hold ranges of the text's bytes, gives the chart 0.7.0's reader gave
 *              with Strings, or its error with its line and excerpt, on every corpus input and spec text, thousands of
 *              them changed at random, random charts of every statement, and long and many hostile ones.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 25/11/2026
 */

import XCTest
@testable import MermaidDiagrams

final class QuadrantChartReaderEquivalenceTests: XCTestCase {
    private static let tokens = ["quadrantChart", "title ", "x-axis ", "y-axis ", "X-AXIS", " --> ", "--->", "-->", "quadrant-1 ", "quadrant-4 ",
                                 "quadrant-5", "classDef ", ":::", ":::c", ": [0.3, 0.6]", ":[1,0]", ": [ 0.25 ,\n1 ]", ": [0x5, 0,5]", ": [2, 0.1]",
                                 " radius: 10", " color: #ff3300", "stroke-color: #10f", "stroke-width: 5px", "radius:", "width: 1", ", ",
                                 "\"quoted\"", "\"`**md**`\"", "\"\"", "\" spaced \"", "\"Été\"", "&", "*", "!", "_", "\u{0085}", "\u{2003}"]

    private func cursor(of source: String) -> MermaidTextCursor? {
        MapReadingEquivalence.cursor(of: source, readAs: .quadrantChart)
    }

    @discardableResult
    private func assertReadAsTheReference(_ source: String, file: StaticString = #filePath, line: UInt = #line) -> Bool {
        guard let cursor = cursor(of: source) else { return false }
        let read = MapReadingEquivalence.outcome { () throws(MermaidDiagramReadError) in try QuadrantChartParser.parse(cursor, limits: .standard) }
        let expected = MapReadingEquivalence.outcome { () throws(MermaidDiagramReadError) in
            try ReferenceQuadrantChartParser.parse(cursor, limits: .standard)
        }
        XCTAssertEqual(read, expected, source, file: file, line: line)
        return true
    }

    func testEveryTextAndItsChangesReadAsTheFrozenReaderReadThem() throws {
        let own = try MapReadingEquivalence.everyText().filter { text in cursor(of: text) != nil }
        XCTAssertFalse(own.isEmpty)
        var mutations = MapReadingMutations(seed: 0x0A_D2_A1, tokens: Self.tokens)
        var comparedCount = 0
        for text in own {
            if assertReadAsTheReference(text) { comparedCount += 1 }
            for _ in 0..<800 where assertReadAsTheReference(mutations.mutated(text)) { comparedCount += 1 }
        }
        XCTAssertGreaterThan(comparedCount, 2_000)
    }

    func testRandomChartsReadAsTheFrozenReaderReadThem() {
        var random = MapReadingMutations(seed: 0x0A_D2_0002, tokens: [])
        let words = ["Reach", "High Reach", "Low-Engagement", "Été", "a_b", "x&y", "2b", "\"Quoted text\"", "\"  padded  \"", "\"`**Bold** md`\"",
                     "\"Été déjà\" more", "\"a\" b-c", "🚀 go", "#tag", "a*b!"]
        let styles = ["radius: 10", "color: #ff3300", "color: f30", "stroke-color: #10f0f0", "stroke-width: 5px", "radius: 1e3", "color: #12",
                      "stroke-width: 5", "  radius :  7 : 9 ", "colour: red", "radius", "radius: 99999999999999999999999"]
        for _ in 0..<3_000 {
            var text = "quadrantChart\n"
            for _ in 0..<(1 + random.below(12)) {
                let word = words[random.below(words.count)]
                switch random.below(8) {
                case 0: text += "  title \(word)\n"
                case 1: text += "  x-axis \(word)" + ["", " --> \(words[random.below(words.count)])", " -->", " --->  "][random.below(4)] + "\n"
                case 2: text += "  y-axis \(word) --> \(words[random.below(words.count)])\n"
                case 3: text += "  quadrant-\(1 + random.below(4)) \(word)\n"
                case 4: text += "  classDef c\(random.below(3)) \(styles[random.below(styles.count)]), \(styles[random.below(styles.count)])\n"
                case 5: text += ["  accTitle: t\n", "  accDescr: d\n", "  accDescr {\n multi \n}\n", "  %% comment\n"][random.below(4)]
                default:
                    let className = random.below(3) == 0 ? ":::c\(random.below(3))" : ""
                    let coordinates = [": [0.3, 0.6]", ":[1, 0]", ": [0.05,0.95]", ": [0.5, 1.5]", ": [0x5, 0.1]"][random.below(5)]
                    let pointStyles = random.below(2) == 0 ? "" : " " + (0..<(1 + random.below(3))).map { _ in styles[random.below(styles.count)] }
                        .joined(separator: ", ")
                    text += "  \(word)\(className)\(coordinates)\(pointStyles)" + [";", "\n"][random.below(2)]
                }
            }
            assertReadAsTheReference(text)
        }
    }

    /// A long line, many points and classes, many styles and long quotations read as the frozen reader reads them, each
    /// in well under a second.
    func testHostileChartsReadAsTheFrozenReaderQuickly() {
        let cases = [
            "quadrantChart\n  title " + String(repeating: "a", count: 45_000),
            "quadrantChart\n" + String(repeating: "  P: [0.5, 0.5]\n", count: 2_900),
            "quadrantChart\n" + (0..<1_000).map { index in "  classDef c\(index) color: #ff3300, radius: 3\n" }.joined(),
            "quadrantChart\n  P: [0.5, 0.5] " + String(repeating: "radius: 1, ", count: 4_000) + "radius: 2",
            "quadrantChart\n  x-axis \"" + String(repeating: "q ", count: 20_000) + "\" tail --> b",
            "quadrantChart\n  quadrant-1 " + String(repeating: "word ", count: 9_000),
        ]
        for source in cases {
            XCTAssertTrue(assertReadAsTheReference(source), String(source.prefix(40)))
            guard let cursor = cursor(of: source) else { continue }
            let start = Date()
            _ = try? QuadrantChartParser.parse(cursor, limits: .standard)
            XCTAssertLessThan(Date().timeIntervalSince(start), 1, String(source.prefix(40)))
        }
    }
}
