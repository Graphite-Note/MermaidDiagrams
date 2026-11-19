/**
 * File: GridDiagramSafetyTests.swift
 * ----------------------------------
 * Layer: Tests
 * Description: Pele's worst cases for block diagrams and architecture diagrams (tests/block/stress.test.ts and
 *              tests/architecture/stress.test.ts) that fit the text limit, each read and laid out or refused with a
 *              typed error within seconds, and every number on their page finite.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 19/11/2026
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
            ("prototype names", "block\n__proto__ constructor toString\nclassDef __proto__ fill:red\nclass constructor,toString __proto__\nstyle __proto__ fill:blue\n__proto__ --> constructor"),
        ]
        for (name, source) in cases {
            XCTAssertLessThanOrEqual(source.utf8.count, MermaidDiagramLimits.standard.maximumSourceBytes, name)
            assertPreparedOrRefused(name, source)
        }
    }
}
