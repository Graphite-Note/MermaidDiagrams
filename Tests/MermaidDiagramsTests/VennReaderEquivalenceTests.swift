/**
 * File: VennReaderEquivalenceTests.swift
 * --------------------------------------
 * Layer: Tests
 * Description: The Venn diagram reader gives the diagram 0.7.0's reader gave, or its error with its line, on every
 *              corpus input and spec text, thousands of them changed at random, random diagrams of every statement and
 *              keyword case, and long and many ones in time; trimming a plane map's text is 0.7.0's on random texts.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 25/11/2026
 */

import XCTest
@testable import MermaidDiagrams

final class VennReaderEquivalenceTests: XCTestCase {
    private static let tokens = ["venn-beta", "set A\n", "set B[\"Label\"]: 20\n", "set \"Quoted name\"\n", "union A, B\n", "union A,B[\"AB\"]: 5\n",
                                 "  text t1\n", "  text \"x\"[\"y\"]\n", "    text 3\n", "style A fill: #ff0, color: rgb(1, 2, 3)\n", "style A,B stroke: \"red\"\n",
                                 "SET", "Union", "TEXT", "Style", "settle", "set-", "styles", "rgba(1,2,3,0.5)", "title A diagram\n", "title\n", "[", "]",
                                 "[\" padded \"]", "[\"unclosed", "\u{3000}", "\u{FEFF}"]

    @discardableResult
    private func assertReadAsTheReference(_ source: String, file: StaticString = #filePath, line: UInt = #line) -> Bool {
        guard let cursor = MapReadingEquivalence.cursor(of: source, readAs: .venn) else { return false }
        let read = MapReadingEquivalence.outcome { () throws(MermaidDiagramReadError) in try VennParser.parse(cursor, limits: .standard) }
        let expected = MapReadingEquivalence.outcome { () throws(MermaidDiagramReadError) in try ReferenceVennParser.parse(cursor, limits: .standard) }
        XCTAssertEqual(read, expected, String(source.prefix(200)), file: file, line: line)
        return true
    }

    func testEveryTextAndItsChangesReadAsTheFrozenReaderReadThem() throws {
        let texts = MapReadingEquivalence.texts(readAs: .venn, among: try MapReadingEquivalence.everyText(), mutationCount: 200, tokens: Self.tokens,
                                                seed: 0x7E77_0001)
        var comparedCount = 0
        for text in texts where assertReadAsTheReference(text) { comparedCount += 1 }
        XCTAssertGreaterThan(comparedCount, 1_500)
    }

    /// Diagrams of every statement, their keywords in every case and run into words (`settle`, `set-`), names quoted,
    /// padded and beyond ASCII, unions of known and unknown sets, indented texts and styles.
    func testRandomDiagramsReadAsTheFrozenReaderReadThem() {
        var random = MapReadingMutations(seed: 0x7E77_0002, tokens: [])
        let names = ["A", "B", "Cats", "\"Dogs and cats\"", "\" padded \"", "é", "x_1", "\"中\""]
        let keywords = [("set", ["set", "SET", "Set", "sEt"]), ("union", ["union", "UNION", "Union"]), ("style", ["style", "STYLE"])]
        for _ in 0..<2_000 {
            var text = ["venn-beta\n", "VENN-BETA\n", "venn-beta\ntitle Sets\n"][random.below(3)]
            for _ in 0..<(1 + random.below(10)) {
                let (kind, spellings) = keywords[random.below(keywords.count)]
                let keyword = spellings[random.below(spellings.count)]
                let label = ["", "[\"label\"]", "[plain]", "[\" spaced \"]"][random.below(4)]
                let size = ["", ": 10", ":3.5", ": x"][random.below(4)]
                switch kind {
                case "set": text += "\(keyword) \(names[random.below(names.count)])\(label)\(size)\n"
                case "union": text += "\(keyword) \(names[random.below(names.count)]), \(names[random.below(names.count)])\(label)\(size)\n"
                default: text += "\(keyword) \(names[random.below(names.count)]) fill: #f0f, color: \"blue\"\n"
                }
                if random.below(3) == 0 { text += ["  text t\n", "    text \"q\"[\"r\"]\n", "\ttext 7\n", "  text\n"][random.below(4)] }
            }
            assertReadAsTheReference(text)
        }
    }

    func testHostileDiagramsReadAsTheFrozenReaderQuickly() {
        let cases = [
            "venn-beta\n" + (0..<1_500).map { index in "set S\(index)" }.joined(separator: "\n"),
            "venn-beta\nset A\nset B\nunion " + Array(repeating: "A", count: 6_000).joined(separator: ", "),
            "venn-beta\nset \"" + String(repeating: "n", count: 40_000) + "\"",
            "venn-beta\nset A\n" + String(repeating: "  text t\n", count: 3_000),
            "venn-beta\nset A\nstyle A " + Array(repeating: "fill: #fff", count: 3_000).joined(separator: ", "),
        ]
        for source in cases {
            XCTAssertTrue(assertReadAsTheReference(source), String(source.prefix(40)))
            guard let cursor = MapReadingEquivalence.cursor(of: source, readAs: .venn) else { continue }
            let start = Date()
            _ = try? VennParser.parse(cursor, limits: .standard)
            XCTAssertLessThan(Date().timeIntervalSince(start), 1, String(source.prefix(40)))
        }
    }

    /// Trimming is 0.7.0's on texts made of printable ASCII, spaces, every ASCII and Unicode white space and characters
    /// beyond ASCII at either end.
    func testPlaneMapTrimmingIsTheFrozenOne() {
        var random = MapReadingMutations(seed: 0x7E77_0003, tokens: [])
        let pieces = ["a", "Z", "\"", "~", "!", " ", "\t", "\n", "\r", "\u{0B}", "\u{0C}", "\u{A0}", "\u{1680}", "\u{2003}", "\u{2028}", "\u{3000}",
                      "\u{FEFF}", "é", "中", "\u{85}", "\u{200B}", "e\u{301}"]
        for _ in 0..<50_000 {
            let text = (0..<random.below(6)).map { _ in pieces[random.below(pieces.count)] }.joined()
            XCTAssertEqual(PlaneMapText.trimmed(text), ReferencePlaneMapText.trimmed(text), text.debugDescription)
        }
    }
}
