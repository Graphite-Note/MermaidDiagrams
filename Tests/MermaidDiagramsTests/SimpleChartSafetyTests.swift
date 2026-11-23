/**
 * File: SimpleChartSafetyTests.swift
 * ----------------------------------
 * Layer: Tests
 * Description: Hostile info, packet, radar and treemap texts (Pele's worst cases and the documentation examples cut and mutated) are
 *              refused with a typed error or prepared within bounds, in time, never a crash.
 *
 * Authors: Bahey Shalash
 * Version: 0.2
 * Date: 23/11/2026
 */

import XCTest
@testable import MermaidDiagrams
@testable import MermaidDiagramsBenchmark

final class SimpleChartSafetyTests: XCTestCase {
    private static let characterCount = 50_000

    private func repeated(_ count: Int, _ line: (Int) -> String) -> String { (0..<count).map(line).joined() }

    private func list(_ count: Int, _ item: (Int) -> String) -> String { (0..<count).map(item).joined(separator: ",") }

    /// The worst cases of Pele's stress tests for the four types, each cut to the source limit where the text is longer.
    private func worstCases() -> [(String, String)] {
        let n = Self.characterCount
        let packetConfig = { (body: String) in "---\nconfig:\n  packet:\n    bitsPerRow: 1\n---\n" + body }
        return [
            ("info: a 50,000 character title", "info\ntitle " + String(repeating: "word ", count: n / 5)),
            ("info: 6,000 titles", "info\n" + String(repeating: "title t\n", count: n / 8)),
            ("info: a title of entities and line breaks", "info\ntitle " + String(repeating: "#35;&amp;<br>", count: n / 13)),
            ("info: 25,000 blank lines", "info" + String(repeating: "\n ", count: n / 2) + "showInfo"),
            ("info: a line of spaces", "info" + String(repeating: " ", count: n) + "showInfo"),
            ("info: 20,000 comments", "info\n" + String(repeating: "%% c\n", count: n / 5)),
            ("info: unclosed directives", "info\n" + String(repeating: "%%{\n", count: n / 4)),
            ("info: front matter fences", "info\n" + String(repeating: "---\n", count: n / 4)),
            ("info: an unclosed accDescr block", "info\naccDescr {" + String(repeating: " a\n", count: n / 3)),
            ("info: a closed accDescr block", "info\naccDescr {" + String(repeating: " a\n", count: n / 3 - 10) + "}"),
            ("info: the keyword 10,000 times", String(repeating: "info ", count: n / 5)),
            ("info: showInfo run together", "info " + String(repeating: "showInfo", count: n / 8)),
            ("packet: 4,000 single-bit fields", "packet\n" + repeated(4_000) { index in "\(index): \"f\(index)\"\n" }),
            ("packet: 5,000 counted fields", "packet\n" + repeated(5_000) { index in "+\(index % 40 + 1): \"f\"\n" }),
            ("packet: one field of a billion bits", "packet\n+1000000000: \"wide\"\n+1: \"after\""),
            ("packet: a field of more bits than a number holds", "packet\n+" + String(repeating: "9", count: 400) + ": \"x\"\n+1: \"y\""),
            ("packet: rows of one bit", packetConfig("packet\n+20000: \"a\"")),
            ("packet: a 50,000 character label", "packet\n0-31: \"" + String(repeating: "word ", count: n / 5) + "\""),
            ("packet: a long label on thousands of rows", packetConfig("packet\n+4000: \"" + String(repeating: "x", count: 40_000) + "\"")),
            ("packet: a label of entities", "packet\n0-31: \"" + String(repeating: "#35;&amp;", count: n / 9) + "\""),
            ("packet: a 50,000 digit number", "packet\n" + String(repeating: "1", count: n) + ": \"a\""),
            ("packet: 50,000 zeros", "packet\n" + String(repeating: "0", count: n)),
            ("packet: 50,000 dashes", "packet\n0" + String(repeating: "-", count: n)),
            ("packet: dashes that open front matter", "packet\n" + String(repeating: "---\n", count: n / 4)),
            ("packet: an unclosed string", "packet\n0: \"" + String(repeating: "a", count: n)),
            ("packet: a string of backslashes", "packet\n0: \"" + String(repeating: "\\", count: n)),
            ("packet: unclosed directives", "packet\n" + String(repeating: "%%{\n", count: n / 4)),
            ("packet: an unclosed accDescr block", "packet\naccDescr {" + String(repeating: " a\n", count: n / 3)),
            ("packet: a title on every line", "packet\n" + String(repeating: "title t\n", count: n / 8)),
            ("packet: 20,000 blank lines", "packet\n" + String(repeating: "\n \t", count: n / 3) + "0: \"a\""),
            ("radar: 5,000 axes and one curve", "radar-beta\naxis " + list(5_000) { index in "a\(index)" } + "\ncurve c{" + list(5_000) { index in String(index) } + "}"),
            ("radar: 4,000 axes with a polygon graticule of 32 ticks", "radar-beta\naxis " + list(4_000) { index in "a\(index)" } + "\ncurve c{" + list(4_000) { _ in "1" } + "}\ngraticule polygon\nticks 32"),
            ("radar: 2,000 axes and curves of named entries",
             "radar-beta\naxis " + list(1_500) { index in "a\(index)" } + "\ncurve x{" + list(1_500) { index in "a\(1_499 - index) \(index)" } + "}"),
            ("radar: 4,000 curves", "radar-beta\naxis a,b,c\n" + repeated(1_500) { index in "curve c\(index){1,2,3}\n" }),
            ("radar: 5,000 options", "radar-beta\n" + String(repeating: "ticks 3\nmax 9\n", count: 2_500)),
            ("radar: 50,000 zeros as curve values", "radar-beta\ncurve c{" + String(repeating: "0", count: n) + "}"),
            ("radar: 50,000 zeros before a decimal point", "radar-beta\nmax " + String(repeating: "0", count: n) + ".5"),
            ("radar: a 50,000 digit number", "radar-beta\naxis a\ncurve c{1}\nmax " + String(repeating: "9", count: n)),
            ("radar: numbers and dots", "radar-beta\ncurve c{" + String(repeating: "1.2", count: n / 3) + "}"),
            ("radar: a 50,000 character name", "radar-beta\naxis " + String(repeating: "a", count: n)),
            ("radar: a name of dashes", "radar-beta\naxis a" + String(repeating: "-", count: n)),
            ("radar: keywords run together", "radar-beta\n" + String(repeating: "axis", count: n / 4)),
            ("radar: accDescr opened 5,000 times", "radar-beta\n" + String(repeating: "accDescr {", count: n / 10)),
            ("radar: an unclosed accDescr block", "radar-beta\naccDescr {" + String(repeating: " a\n", count: n / 3)),
            ("radar: an unclosed string", "radar-beta\naxis a[\"" + String(repeating: "x", count: n)),
            ("radar: a 50,000 character label", "radar-beta\naxis a[\"" + String(repeating: "word ", count: n / 5) + "\"], b\ncurve c{1,2}"),
            ("radar: 25,000 open brackets", "radar-beta\naxis a" + String(repeating: "[", count: n / 2)),
            ("radar: 20,000 line breaks inside a curve", "radar-beta\naxis a\ncurve c{" + String(repeating: "\n", count: 20_000) + "1" + String(repeating: "\n", count: 20_000) + "}"),
            ("radar: unclosed directives", "radar-beta\n" + String(repeating: "%%{\n", count: n / 4)),
            ("radar: a long title", "radar-beta\ntitle " + String(repeating: "x", count: n)),
            ("treemap: 5,000 leaves", "treemap\n" + repeated(4_999) { index in "\"l\(index)\": \(index + 1)\n" }),
            ("treemap: 4,000 leaves of equal value in one section", "treemap\n\"s\"\n" + String(repeating: " \"l\": 1\n", count: 4_000)),
            ("treemap: 4,000 leaves of very unequal value", "treemap\n" + repeated(4_000) { index in "\"l\": \(index % 2 == 1 ? "0.0001" : "99999999")\n" }),
            ("treemap: 2,000 sections with one leaf each", "treemap\n" + repeated(2_000) { index in "\"s\(index)\"\n  \"l\": \(index + 1)\n" }),
            ("treemap: 300 levels of nesting", "treemap\n" + repeated(300) { level in String(repeating: " ", count: level) + "\"s\(level)\"\n" } + String(repeating: " ", count: 300) + "\"leaf\": 1\n"),
            ("treemap: 2,400 sections that step in and out", "treemap\n" + String(repeating: "\"s\"\n \"t\"\n", count: 2_400)),
            ("treemap: 4,000 sections and no leaves", "treemap\n" + repeated(4_000) { index in "\"s\(index)\"\n" }),
            ("treemap: 4,000 class definitions", "treemap\n\"a\": 1:::c1\n" + repeated(1_500) { index in "classDef c\(index) fill:red\n" }),
            ("treemap: one class with 5,000 declarations", "treemap\n\"a\": 1:::c1\nclassDef c1 " + String(repeating: "fill:red,", count: 5_000) + "stroke:blue;\n"),
            ("treemap: a class applied to 3,000 leaves", "treemap\nclassDef c1 fill:red,stroke:blue,color:white\n" + repeated(3_000) { index in "\"l\(index)\": 5:::c1\n" }),
            ("treemap: a 50,000 character name", "treemap\n\"" + String(repeating: "word ", count: n / 5) + "\": 1"),
            ("treemap: a 50,000 character section name", "treemap\n\"" + String(repeating: "x", count: n) + "\"\n \"a\": 1"),
            ("treemap: a name of entities", "treemap\n\"" + String(repeating: "#35;&amp;", count: n / 9) + "\": 1"),
            ("treemap: a 50,000 digit value", "treemap\n\"a\": " + String(repeating: "9", count: n)),
            ("treemap: a value of dots and commas", "treemap\n\"a\": " + String(repeating: ".,_", count: n / 3)),
            ("treemap: classDef followed by 50,000 spaces", "treemap\nclassDef" + String(repeating: " ", count: n) + "1"),
            ("treemap: classDef 6,000 times with one-letter names", "treemap\n" + String(repeating: "classDef a\n", count: n / 11)),
            ("treemap: classDef and 25,000 blank lines", "treemap\nclassDef" + String(repeating: "\n ", count: n / 2) + "ab"),
            ("treemap: a class style of 50,000 characters", "treemap\n\"a\": 1:::cc\nclassDef cc " + String(repeating: "x", count: n)),
            ("treemap: accDescr opened 5,000 times", "treemap\n" + String(repeating: "accDescr\n", count: n / 10) + "{"),
            ("treemap: an unclosed accDescr block", "treemap\naccDescr {" + String(repeating: " a\n", count: n / 3)),
            ("treemap: an unclosed string", "treemap\n\"" + String(repeating: "a", count: n)),
            ("treemap: 25,000 quotes", "treemap\n" + String(repeating: "\"", count: n / 2)),
            ("treemap: 50,000 colons", "treemap\n\"a\"" + String(repeating: ":", count: n)),
            ("treemap: a line of spaces", "treemap\n" + String(repeating: " ", count: n) + "\"a\": 1"),
            ("treemap: 20,000 comments", "treemap\n" + String(repeating: "%% c\n", count: n / 5) + "\"a\": 1"),
            ("treemap: a long title", "treemap\ntitle " + String(repeating: "x", count: n)),
            ("treemap: a 50,000 character value format", "---\nconfig:\n  treemap:\n    valueFormat: \"" + String(repeating: "0", count: 40_000) + "x\"\n---\ntreemap\n\"a\": 1"),
        ]
    }

    func testPelesWorstCasesAreRefusedOrPreparedInTime() {
        let typography = DiagramSceneSamples.typography
        var preparedCount = 0
        var refusedCount = 0
        for (name, source) in worstCases() {
            let started = Date()
            do {
                let prepared = try MermaidDiagramPreparation.prepare(source: source, typography: typography)
                XCTAssertTrue(prepared.scene.size.width.isFinite && prepared.scene.size.height.isFinite, name)
                for shape in prepared.scene.shapes { XCTAssertTrue(shape.path.boundingBoxOfPath.width.isFinite || shape.path.isEmpty, name) }
                // The narrow scene is laid out when it is read: read it, so that its layout is bounded in time too.
                if let narrow = prepared.narrowScene { XCTAssertTrue(narrow.size.width.isFinite && narrow.size.height.isFinite, name) }
                preparedCount += 1
            } catch {
                refusedCount += 1
            }
            XCTAssertLessThan(Date().timeIntervalSince(started), 5, name)
        }
        XCTAssertGreaterThan(preparedCount, 10)
        XCTAssertGreaterThan(refusedCount, 10)
    }

    /// Every text of the four types' documentation examples, cut short and changed at random places, is prepared or refused.
    func testTheExamplesOfTheFourTypesCutShortOrMutatedArePreparedOrRefused() throws {
        let examples = try InfoDiagramCorpus.documentationExamples() + PacketDiagramCorpus.documentationExamples() + RadarChartCorpus.documentationExamples()
            + TreemapCorpus.documentationExamples()
        let typography = DiagramSceneSamples.typography
        var generator = SimpleChartGenerator(seed: 0xC0FFEE)
        let insertedBytes = Array("[]{}()|\"'-:;,%`<>#\\+.0 \n".utf8)
        var preparedCount = 0
        func check(_ text: String) {
            if let prepared = try? MermaidDiagramPreparation.prepare(source: text, typography: typography) {
                XCTAssertTrue(prepared.scene.size.width.isFinite && prepared.scene.size.height.isFinite, text)
                if let narrow = prepared.narrowScene { XCTAssertTrue(narrow.size.width.isFinite && narrow.size.height.isFinite, text) }
                preparedCount += 1
            }
        }
        for example in examples {
            let bytes = Array(example.utf8)
            for cut in stride(from: 1, to: bytes.count, by: max(1, bytes.count / 60)) { check(String(decoding: bytes[..<cut], as: UTF8.self)) }
            for _ in 0..<60 {
                var mutated = bytes
                let position = Int(generator.next() % UInt64(mutated.count))
                switch generator.next() % 3 {
                case 0: mutated.remove(at: position)
                case 1: mutated.insert(insertedBytes[Int(generator.next() % UInt64(insertedBytes.count))], at: position)
                default: mutated.insert(contentsOf: mutated[position...].prefix(30), at: position)
                }
                check(String(decoding: mutated, as: UTF8.self))
            }
        }
        XCTAssertGreaterThan(preparedCount, 500)
    }

    /// A nest of sections as deep as the text allows is laid out and read on a thread with the small stack of the reading view's.
    func testDeepNestingNeedsNoRecursion() {
        let finished = expectation(description: "the work finished")
        let thread = Thread {
            let depth = 4_000
            let source = "treemap\n" + (0..<depth).map { level in String(repeating: " ", count: level % 200) + "\"s\(level)\"\n" }.joined() + " \"leaf\": 1\n"
            // Its narrow scene read too, as it is laid out only then, so that the narrow layout runs on the small stack as well.
            _ = (try? MermaidDiagramPreparation.prepare(source: String(source.prefix(MermaidDiagramLimits.standard.maximumSourceBytes)),
                                                        typography: DiagramSceneSamples.typography))?.narrowScene
            finished.fulfill()
        }
        thread.stackSize = 512 * 1024
        thread.start()
        wait(for: [finished], timeout: 120)
    }
}

/// A generator of numbers from a seed, so that the mutated texts are the same on every run.
private struct SimpleChartGenerator: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var mixed = state
        mixed = (mixed ^ (mixed >> 30)) &* 0xBF58_476D_1CE4_E5B9
        mixed = (mixed ^ (mixed >> 27)) &* 0x94D0_49BB_1331_11EB
        return mixed ^ (mixed >> 31)
    }
}
