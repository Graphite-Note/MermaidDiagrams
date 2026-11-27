/**
 * File: GraphDiagramNameTableResetTests.swift
 * -------------------------------------------
 * Layer: Tests
 * Description: The graph diagrams' name table emptied for another text, as each thread's reading lists keep it: every
 *              name is new again and numbered from 0, whether the table is cleared whole (after a large text) or slot by
 *              slot (a small text in a table a large one grew), on names that collide in the hash's low bits too.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 26/11/2026
 */

import XCTest
@testable import MermaidDiagrams

final class GraphDiagramNameTableResetTests: XCTestCase {
    /// A table grown by thousands of names (some sharing their hash's low bits), emptied, then given a few names, then
    /// emptied and given all of them again: each name is new and numbered in order every time, and none of a previous
    /// text's names is found. The few names' table is emptied slot by slot, the many names' cleared whole.
    func testAnEmptiedTableNumbersEveryNameAgainFromZero() {
        let many = GraphDiagramNameTableTests.caseVariants(of: "abcdefghijk") + (0..<6_000).map { index in "s\(index)" }
        let few = Array(GraphDiagramNameTableTests.caseVariants(of: "abcdefghijk").prefix(40)) + ["x", "y", "z"]
        var table = GraphDiagramNameTable(isASCII: true)
        for (round, names) in [many, few, few.reversed(), many.reversed(), few].enumerated() {
            if round > 0 { table.reset(isASCII: true) }
            XCTAssertEqual(table.count, 0)
            Self.assertNumbered(names, in: &table)
        }
    }

    /// A table emptied for a text beyond ASCII keys its names by Strings, and one emptied for ASCII again by bytes.
    func testAnEmptiedTableFollowsTheTextsKind() {
        var table = GraphDiagramNameTable(isASCII: true)
        Self.assertNumbered(["a", "b"], in: &table)
        table.reset(isASCII: false)
        XCTAssertEqual(table.intern("caf\u{E9}").number, 0)
        XCTAssertFalse(table.intern("cafe\u{301}").isNew)
        table.reset(isASCII: true)
        Self.assertNumbered(["b", "a", "c"], in: &table)
    }

    /// Interns `names`, each new and numbered in order, then again, each found with its number.
    private static func assertNumbered(_ names: [String], in table: inout GraphDiagramNameTable, file: StaticString = #filePath, line: UInt = #line) {
        let text = Array(names.joined().utf8)
        var ranges: [MermaidTextRange] = []
        var start = 0
        for name in names {
            ranges.append(MermaidTextRange(start: start, end: start + name.utf8.count))
            start += name.utf8.count
        }
        text.withUnsafeBufferPointer { buffer in
            for (index, range) in ranges.enumerated() {
                let interned = table.intern(buffer, range)
                XCTAssertEqual(interned.number, index, file: file, line: line)
                XCTAssertTrue(interned.isNew, file: file, line: line)
            }
            for (index, range) in ranges.enumerated() {
                let interned = table.intern(buffer, range)
                XCTAssertEqual(interned.number, index, file: file, line: line)
                XCTAssertFalse(interned.isNew, file: file, line: line)
            }
        }
        XCTAssertEqual(table.count, names.count, file: file, line: line)
    }
}
