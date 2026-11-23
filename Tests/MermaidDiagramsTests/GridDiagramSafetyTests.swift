/**
 * File: GridDiagramSafetyTests.swift
 * ----------------------------------
 * Layer: Tests
 * Description: Pele's worst cases for block diagrams and architecture diagrams (tests/block/stress.test.ts and
 *              tests/architecture/stress.test.ts) that fit the text limit, each read and laid out or refused with a
 *              typed error within seconds, and every number on their page finite.
 *
 * Authors: Bahey Shalash
 * Version: 0.3
 * Date: 23/11/2026
 */

import XCTest
@testable import MermaidDiagrams

final class GridDiagramSafetyTests: XCTestCase {
    private let typography = DiagramTypography(font: DiagramFont(postScriptName: nil, size: 16))

    private static func repeated(_ count: Int, _ line: (Int) -> String) -> String {
        (0..<count).map(line).joined()
    }

    /// Prepares `source` as a reader would, within three seconds, refused with a typed failure or drawn at a finite size.
    private func assertPreparedOrRefused(_ name: String, _ source: String, file: StaticString = #filePath, line: UInt = #line) {
        let started = Date()
        do {
            let prepared = try MermaidDiagramPreparation.prepare(source: source, typography: typography)
            XCTAssertTrue(prepared.scene.size.width.isFinite && prepared.scene.size.height.isFinite, name, file: file, line: line)
            for case .text(let text) in prepared.scene.items {
                XCTAssertTrue(text.block.center.x.isFinite && text.block.center.y.isFinite, name, file: file, line: line)
            }
            // The narrow scene is laid out when it is read: read it, so that its layout is bounded in time too.
            if let narrow = prepared.narrowScene { XCTAssertTrue(narrow.size.width.isFinite && narrow.size.height.isFinite, name, file: file, line: line) }
        } catch {
            _ = error.category
        }
        XCTAssertLessThan(Date().timeIntervalSince(started), 3, name, file: file, line: line)
    }

    func testBlockWorstCasesAreDrawnOrRefusedQuickly() {
        let fifty = 50_000
        let cases: [(String, String)] = [
            ("one row of 4,000 blocks", "block\n" + Self.repeated(4_000) { index in "b\(index) " }),
            ("one column of 4,000 blocks", "block\ncolumns 1\n" + Self.repeated(4_000) { index in "b\(index)\n" }),
            ("grid of labelled blocks", "block\ncolumns 100\n" + Self.repeated(4_000) { index in "b\(index)[\"x\"] " }),
            ("4,000 nested composites", "block\n" + String(repeating: "block\n", count: 4_000) + "a\n" + String(repeating: "end\n", count: 4_000)),
            ("2,000 nested titled composites", "block\n" + Self.repeated(2_000) { index in "block:g\(index)\n" } + "a\n" + String(repeating: "end\n", count: 2_000)),
            ("unclosed composites", "block\n" + String(repeating: "block\n", count: 8_000) + "a"),
            ("stray ends", "block\na\n" + String(repeating: "end\n", count: 12_000)),
            ("sibling composites", "block\ncolumns 50\n" + Self.repeated(2_000) { index in "block\nn\(index)\nend\n" }),
            ("one statement of links", "block\na0" + Self.repeated(4_000) { index in "-->a\(index + 1)" }),
            ("edges across a grid", "block\ncolumns 20\n" + Self.repeated(400) { index in "n\(index) " } + "\n"
                + Self.repeated(2_000) { index in "n\(index % 400) --> n\((index * 37 + 11) % 400)\n" }),
            ("complete graph of 40", "block\ncolumns 9\n" + Self.repeated(40) { first in Self.repeated(40 - first - 1) { offset in "n\(first)-->n\(first + offset + 1)\n" } }),
            ("parallel edges and self loops", "block\nA space B\n" + String(repeating: "A-->B\n", count: 2_000) + String(repeating: "A-->A\n", count: 2_000)),
            ("labelled edges", "block\nA space:3 B\n" + String(repeating: "A -- \"label text\" --> B\n", count: 1_500)),
            ("space past the limit", "block\n" + String(repeating: "space:99999 ", count: 400)),
            ("space count of 400 digits", "block\na space:" + String(repeating: "9", count: 400) + " b"),
            ("block width of 400 digits", "block\ncolumns 3\na:" + String(repeating: "9", count: 400) + " b c"),
            ("column count of 400 digits", "block\ncolumns " + String(repeating: "9", count: 400) + "\na b"),
            ("many wide blocks", "block\n" + Self.repeated(4_000) { index in "b\(index):999 " }),
            ("one long label", "block\nA[\"" + String(repeating: "word ", count: 9_000) + "\"]"),
            ("label of entities and line breaks", "block\nA[\"" + String(repeating: "#35;&amp;<br>", count: 3_500) + "\"]"),
            ("unclosed label", "block\nA[\"" + String(repeating: "x", count: fifty - 20)),
            ("unclosed markdown label", "block\nA[\"`" + String(repeating: "x`", count: 24_000)),
            ("arrow with directions", "block\nA<[\"x\"]>(" + String(repeating: "up, down , x,y ", count: 3_000) + ")"),
            ("class list of ids", "block\nA\nclass " + String(repeating: "A,", count: 20_000) + "A hot\nclassDef hot fill:#f96"),
            ("style list of commas", "block\nA\nstyle A " + String(repeating: ",", count: 45_000)),
            ("style of semicolons", "block\nA\nstyle A " + String(repeating: "fill:red;", count: 5_000)),
            ("classes on one block", "block\nA\n" + Self.repeated(1_200) { index in "classDef c\(index) fill:red\nclass A c\(index)\n" }),
            ("runs of dashes, dots, equals", "block\nA" + String(repeating: "-", count: 16_000) + String(repeating: ".", count: 16_000) + String(repeating: "=", count: 16_000)),
            ("links without blocks", "block\n" + String(repeating: "--> ", count: 12_000)),
            ("one long identifier", "block\n" + String(repeating: "a", count: fifty - 10)),
            ("brackets only", "block\n" + String(repeating: "(([[{{", count: 8_000)),
            ("blank lines and comment lines", "block\n" + String(repeating: "\n \n%% c\n", count: 5_500) + "a[\"x\n" + String(repeating: "%% c\n", count: 1_000) + "y\"]"),
            ("filled composites under many edges", "block\ncolumns 40\nclassDef d fill:#222\n" + Self.repeated(1_000) { index in "block:g\(index)\nn\(index)\nend\n" }
                + "class " + Self.repeated(1_000) { index in index == 0 ? "g0" : ",g\(index)" } + " d\n"
                + Self.repeated(1_400) { index in "n\(index % 1_000)-->n\((index * 7 + 3) % 1_000)\n" }),
            ("prototype names", "block\n__proto__ constructor toString\nclassDef __proto__ fill:red\nclass constructor,toString __proto__\nstyle __proto__ fill:blue\n__proto__ --> constructor"),
        ]
        for (name, source) in cases {
            XCTAssertLessThanOrEqual(source.utf8.count, MermaidDiagramLimits.standard.maximumSourceBytes, name)
            assertPreparedOrRefused(name, source)
        }
    }

    func testArchitectureWorstCasesAreDrawnOrRefusedQuickly() {
        let head = "architecture-beta\n"
        func services(_ count: Int) -> String { Self.repeated(count) { index in "service n\(index)\n" } }
        func diagonalGroup(_ group: Int, _ sides: String) -> String {
            "group g\(group)\n" + Self.repeated(12) { index in "service m\(group)x\(index) in g\(group)\n" }
                + Self.repeated(11) { index in "m\(group)x\(index):\(sides):m\(group)x\(index + 1)\n" }
        }
        let cases: [(String, String)] = [
            ("unconnected services", head + services(3_500)),
            ("a chain", head + services(1_500) + Self.repeated(1_499) { index in "n\(index):R -- L:n\(index + 1)\n" }),
            ("a diagonal", head + services(1_500) + Self.repeated(1_499) { index in "n\(index):R -- T:n\(index + 1)\n" }),
            ("a star all wanting one cell", head + services(1_500) + Self.repeated(1_499) { index in "n0:R -- L:n\(index + 1)\n" }),
            ("a star of bends", head + services(1_500) + Self.repeated(1_499) { index in "n0:B -- L:n\(index + 1)\n" }),
            ("a star of like sides", head + services(1_500) + Self.repeated(1_499) { index in "n0:R -- R:n\(index + 1)\n" }),
            ("edges between two services", head + "service a\nservice b\n" + String(repeating: "a:R <-[x]-> L:b\n", count: 2_500)),
            ("self edges", head + "service a\n" + String(repeating: "a:R --> L:a\n", count: 2_500)),
            ("a complete graph of 40", head + services(40) + Self.repeated(40) { first in Self.repeated(40 - first - 1) { offset in "n\(first):R -- L:n\(first + offset + 1)\n" } }),
            ("nested groups", head + "group g0\n" + Self.repeated(1_999) { index in "group g\(index + 1) in g\(index)\n" } + "service a in g1999\n"),
            ("titled nested groups with edges out", head + "group g0[T]\n" + Self.repeated(799) { index in "group g\(index + 1)[T] in g\(index)\n" }
                + "service a in g799\nservice b\n" + String(repeating: "a:R -- L:b\n", count: 500)),
            ("sibling groups in a chain", head + Self.repeated(1_000) { index in "group g\(index)\nservice n\(index) in g\(index)\n" }
                + Self.repeated(999) { index in "n\(index):R -- L:n\(index + 1)\n" }),
            ("groups wanting the same place", head + "service hub\n" + Self.repeated(900) { index in "group g\(index)\nservice n\(index) in g\(index)\nhub:R -- L:n\(index)\n" }),
            ("large groups wanting the same place", head + "service hub\n" + Self.repeated(40) { group in diagonalGroup(group, "R -- T") + "hub:R -- L:m\(group)x0\n" }),
            ("align directives", head + services(1_500) + "align row " + Self.repeated(750) { index in "n\(index) " } + "\n"
                + Self.repeated(750) { index in "align column n\(index) n\(index + 750)\n" }),
            ("one long service title", head + "service a[" + String(repeating: "word ", count: 9_000) + "]"),
            ("one long unbroken title", head + "service a[" + String(repeating: "w", count: 45_000) + "]"),
            ("one long icon text", head + "service a \"" + String(repeating: "word ", count: 9_000) + "\""),
            ("unbroken icon text", head + "service a \"" + String(repeating: "\u{1F600}", count: 11_000) + "\""),
            ("titles of entities and line breaks", head + "service a[\"" + String(repeating: "#35;&amp;<br>", count: 3_500) + "\"]"),
            ("quoted titles that never close", head + Self.repeated(2_000) { index in "service n\(index)[\"a]\n" }),
            ("title keyword on every line", head + String(repeating: "title a %% b\n", count: 3_500)),
            ("one line of spaces", head + String(repeating: " ", count: 45_000) + "service a"),
            ("one long identifier", head + "service " + String(repeating: "a-", count: 22_000) + "a"),
            ("keywords glued to identifiers", head + Self.repeated(2_000) { index in "service service\(index)\n" } + "service in-in-in\n"),
            ("unclosed brackets", head + "service a" + String(repeating: "[", count: 45_000)),
            ("unclosed parentheses", head + "service a(" + String(repeating: "a:-", count: 15_000)),
            ("unclosed string", head + "service a \"" + String(repeating: "a\\\"", count: 15_000)),
            ("runs of dashes", head + "service a\nservice b\na:R " + String(repeating: "-", count: 45_000) + " L:b"),
            ("fence openers with no closer", head + "service a\nservice b\n" + String(repeating: "a:R ---\n", count: 5_000)),
            ("unclosed directives", head + String(repeating: "%%{\n", count: 12_000)),
            ("accDescr with a brace that never closes", head + String(repeating: "accDescr\n", count: 4_000) + "accDescr {" + String(repeating: " a\n", count: 1_000)),
            ("side letters", head + String(repeating: "L", count: 45_000)),
            ("arrows", head + "service a\nservice b\na:R " + String(repeating: "<>", count: 22_000)),
            ("group modifiers", head + "service a\na" + String(repeating: "{group}", count: 6_000)),
        ]
        for (name, source) in cases {
            XCTAssertLessThanOrEqual(source.utf8.count, MermaidDiagramLimits.standard.maximumSourceBytes, name)
            assertPreparedOrRefused(name, source)
        }
    }
}
