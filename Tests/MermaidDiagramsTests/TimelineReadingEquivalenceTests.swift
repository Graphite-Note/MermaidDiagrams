/**
 * File: TimelineReadingEquivalenceTests.swift
 * -------------------------------------------
 * Layer: Tests
 * Description: The timeline reader, which trims and decodes ASCII texts on their bytes, gives the diagram 0.7.0's reader
 *              gave (ReferenceTimelineParser), or the same error, on every corpus, the specification's texts, thousands
 *              of mutated texts and random statements of every spacing and of characters beyond ASCII.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 25/11/2026
 */

import XCTest
@testable import MermaidDiagrams

final class TimelineReadingEquivalenceTests: XCTestCase {
    private static let keywords: Set<String> = ["timeline"]

    private func agree(_ source: String) -> Bool? {
        ChartReadingEquivalence.agree(source, keywords: Self.keywords, read: { (cursor, _) throws(MermaidDiagramReadError) in
            try TimelineParser.parse(cursor, limits: .standard)
        }, reference: { (cursor, _) throws(MermaidDiagramReadError) in
            try ReferenceTimelineParser.parse(cursor, limits: .standard)
        })
    }

    private func assertAgree(_ sources: [String], atLeast count: Int, file: StaticString = #filePath, line: UInt = #line) {
        var compared = 0
        for source in sources {
            guard let agrees = agree(source) else { continue }
            XCTAssertTrue(agrees, "\(source.prefix(300))", file: file, line: line)
            compared += 1
        }
        XCTAssertGreaterThanOrEqual(compared, count, file: file, line: line)
    }

    func testEveryCorpusAndMutatedTextIsReadAsZeroSevenReadIt() throws {
        let sources = try ChartReadingEquivalence.corpusSources(keywords: Self.keywords) + Self.specificationTexts
        assertAgree(sources, atLeast: 14)
        var mutations = ChartTextMutations(seed: 0x71_3E11E)
        var mutated: [String] = []
        for source in sources {
            for _ in 0..<100 { mutated.append(mutations.mutated(source)) }
            for _ in 0..<100 { mutated.append(mutations.spliced(source)) }
        }
        assertAgree(mutated, atLeast: 3_000)
    }

    func testRandomStatementsAreReadAsZeroSevenReadThem() {
        let texts = ["2004", " 2004 ", "\t2005\u{0B}", "Facebook", "  Google  ", "a<br>b", "&amp;", "#9829;", "é", " \u{A0}x\u{A0} ", "\u{3000}y", "z\u{85}",
                     "\u{FEFF}w", "", "  "]
        var state: UInt64 = 0x71_E1_1E
        func below(_ bound: Int) -> Int {
            state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            return Int((state >> 33) % UInt64(bound))
        }
        var compared = 0
        for _ in 0..<3_000 {
            var lines = ["timeline" + (below(4) == 0 ? " LR" : "")]
            for _ in 0..<(1 + below(8)) {
                switch below(6) {
                case 0: lines.append("title " + texts[below(texts.count)])
                case 1: lines.append("section " + texts[below(texts.count)])
                case 2: lines.append("    : " + texts[below(texts.count)])
                default:
                    lines.append(texts[below(texts.count)] + (0..<below(4)).map { _ in " : " + texts[below(texts.count)] }.joined())
                }
            }
            guard let agrees = agree(lines.joined(separator: "\n")) else { continue }
            XCTAssertTrue(agrees, lines.joined(separator: "\n"))
            compared += 1
        }
        XCTAssertEqual(compared, 3_000)
    }

    /// Mermaid's timeline documentation and the grammar's corners.
    static let specificationTexts = [
        "timeline\n    title History of Social Media Platform\n    2002 : LinkedIn\n    2004 : Facebook\n         : Google\n    2005 : YouTube\n",
        "timeline\n    section 17th-20th century\n        Industry 1.0 : Machinery, Water power, Steam <br>power\n    section 21st century\n        Industry 4.0 : Internet, Robotics\n",
        "timeline LR\n  a : b : c\n  d\n",
        "timeline TD\n  2004 : x: y : z\n",
        "timeline\n  accTitle: t\n  accDescr: d\n  2004 : x\n",
        "timeline\n  %% comment\n  2004 : x # not a comment\n",
        "timeline\r\n  2004 : x\r\n  2005 : y\r\n",
        "timeline\n  : orphan\n",
        "timeline\n  title\n  2004\n",
        "timeline\n  \u{A0}2004\u{A0} : \u{3000}x\u{3000}\n",
    ]
}
