/**
 * File: WardleyMapReaderEquivalenceTests.swift
 * --------------------------------------------
 * Layer: Tests
 * Description: The Wardley map reader gives the map 0.7.0's reader gave, or its error with its line, on every corpus
 *              input and spec text, thousands of them changed at random, random maps of every statement, and long,
 *              many and hostile ones, and arrows and escapes whose signs a combining mark follows.
 *
 * Authors: Bahey Shalash
 * Version: 0.2
 * Date: 24/11/2026
 */

import XCTest
@testable import MermaidDiagrams

final class WardleyMapReaderEquivalenceTests: XCTestCase {
    private static let tokens = ["wardley-beta", "anchor A [0.9, 0.1]\n", "component B [0.5, 0.5]\n", "component C [0.4, 0.6] label [-10, 5]\n", "A -> B\n",
                                 "B -.-> C\n", "A +<> B\n", "A +'flows'<> C\n", "A +'é'> C\n", "A +'<b'> C\n", "B --> C ; label\n", "evolve B 0.8\n",
                                 "pipeline B {\n  component D [0.3]\n}\n", "note \"a \\\"note\\\"\" [0.2, 0.3]\n", "annotations [0.1, 0.1]\n",
                                 "annotation 1,[0.2, 0.2] \"text\"\n", "accelerator X [0.5, 0.5]\n", "deaccelerator Y [0.5, 0.5]\n", "size [800, 600]\n",
                                 "evolution Genesis -> Custom -> Product -> Commodity\n", "(build)", "(buy)", "(outsource)", "(market)", "inertia",
                                 "buy", "build", "market", "note", "notes", "anchorage", "componentX", "@", "/", "+<", "+>", "-->", "->", "-.->", ".-."]

    @discardableResult
    private func assertReadAsTheReference(_ source: String, file: StaticString = #filePath, line: UInt = #line) -> Bool {
        guard let cursor = MapReadingEquivalence.cursor(of: source, readAs: .wardleyMap) else { return false }
        let read = MapReadingEquivalence.outcome { () throws(MermaidDiagramReadError) in try WardleyMapParser.parse(cursor, limits: .standard) }
        let expected = MapReadingEquivalence.outcome { () throws(MermaidDiagramReadError) in try ReferenceWardleyMapParser.parse(cursor, limits: .standard) }
        XCTAssertEqual(read, expected, source, file: file, line: line)
        return true
    }

    func testEveryTextAndItsChangesReadAsTheFrozenReaderReadThem() throws {
        let texts = MapReadingEquivalence.texts(readAs: .wardleyMap, among: try MapReadingEquivalence.everyText(), mutationCount: 120, tokens: Self.tokens,
                                                seed: 0x3A7D_1E1)
        var comparedCount = 0
        for text in texts where assertReadAsTheReference(text) { comparedCount += 1 }
        XCTAssertGreaterThan(comparedCount, 2_000)
    }

    func testRandomMapsReadAsTheFrozenReaderReadThem() {
        var random = MapReadingMutations(seed: 0x3A7D_0002, tokens: [])
        let names = ["A", "Business", "Cup of Tea", "Hot_Water", "Kettle (old)", "\"Quoted name\"", "\"é escaped \\n\"", "R&D", "x-y"]
        let arrows = [" -> ", " --> ", " -.-> ", " +<> ", " +> ", " +< ", " +'label'<> ", " +'é'> ", " +'a<b'< ", " > "]
        for _ in 0..<1_500 {
            var text = "wardley-beta\n"
            for _ in 0..<(1 + random.below(16)) {
                let name = names[random.below(names.count)]
                let other = names[random.below(names.count)]
                let point = "[0.\(random.below(10))\(random.below(10)), 0.\(random.below(10))]"
                switch random.below(8) {
                case 0: text += "anchor \(name) \(point)\n"
                case 1: text += "component \(name) \(point)" + ["", " (build)", " (buy)", " (market)", " inertia", " label [-5, 10]"][random.below(6)] + "\n"
                case 2: text += name + arrows[random.below(arrows.count)] + other + (random.below(3) == 0 ? " ; a label" : "") + "\n"
                case 3: text += "evolve \(name) 0.\(random.below(10))\n"
                case 4: text += "note \"note \(random.below(9))\" \(point)\n"
                case 5: text += "pipeline \(name) {\n  component \(other) [0.\(random.below(10))]\n}\n"
                case 6: text += ["accelerator", "deaccelerator", "annotations", "title A map", "size [600, 400]"][random.below(5)]
                    + (random.below(2) == 0 ? " \(name) \(point)\n" : "\n")
                default: text += "annotation \(random.below(5)),\(point) \"text\"\n"
                }
            }
            assertReadAsTheReference(text)
        }
    }

    /// A labelled arrow's `<`, `>`, `<>` or `-.->` and a note's backslash followed by a combining mark, which joins them
    /// into one character: the byte search's Foundation fallback for text past ASCII finds or misses them as 0.7.0's
    /// `contains` did, and an escape so joined is kept as it was.
    func testArrowSignsAndEscapesJoinedByACombiningMarkReadAsTheFrozenReaderReadThem() {
        let components = "wardley-beta\ncomponent A [0.5, 0.5]\ncomponent B [0.4, 0.4]\n"
        let arrows = ["A +'<\u{301}'> B", "A +'x<\u{301}y'> B", "A +'é<'> B", "A +'-.\u{301}->'> B", "A +'-.->\u{301}'> B", "A +'<>\u{301}'< B",
                      "A +'<\u{20D2}'> B", "A +'>\u{301}'< B", "A +'é'<> B"]
        for arrow in arrows { XCTAssertTrue(assertReadAsTheReference(components + arrow + "\n"), arrow) }
        for note in ["a\\\u{301}b", "a\\\u{301}nb\\n", "\\\u{301}\\\u{301}", "é\\\"x"] {
            XCTAssertTrue(assertReadAsTheReference("wardley-beta\nnote \"\(note)\" [0.2, 0.3]\n"), note)
        }
    }

    /// A long name, many components and links, and runs of punctuation read as the frozen reader reads them, each in
    /// well under a second.
    func testHostileMapsReadAsTheFrozenReaderQuickly() {
        let cases = [
            "wardley-beta\ncomponent " + String(repeating: "a", count: 40_000) + " [0.5, 0.5]\n",
            "wardley-beta\n" + (0..<1_200).map { index in "component C\(index) [0.5, 0.5]\n" }.joined(),
            "wardley-beta\n" + (0..<1_200).map { index in "C\(index % 40) -> C\((index * 7) % 40)\n" }.joined(),
            "wardley-beta\n" + String(repeating: "[", count: 40_000),
            "wardley-beta\nA +'" + String(repeating: "<", count: 40_000) + "'> B\n",
            "wardley-beta\n" + String(repeating: "pipeline A {\n", count: 3_000),
        ]
        for source in cases {
            assertReadAsTheReference(source)
            guard let cursor = MapReadingEquivalence.cursor(of: source, readAs: .wardleyMap) else {
                XCTFail("a Wardley map: \(source.prefix(40))")
                continue
            }
            let start = Date()
            _ = try? WardleyMapParser.parse(cursor, limits: .standard)
            XCTAssertLessThan(Date().timeIntervalSince(start), 1, String(source.prefix(40)))
        }
    }
}
