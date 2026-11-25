/**
 * File: EventModelBlockTextTests.swift
 * ------------------------------------
 * Layer: Tests
 * Description: An event model's data block of ASCII alone is cut out of its braces or quotation marks on its bytes
 *              exactly as it is scalar by scalar, for texts of braces, quotation marks, blank lines, indentation and
 *              trailing white space put together at random, with and without characters beyond ASCII.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 24/11/2026
 */

import XCTest
@testable import MermaidDiagrams

final class EventModelBlockTextTests: XCTestCase {
    func testBlocksReadOnTheirBytesAsTheyAreReadScalarByScalar() {
        let pieces = ["{", "}", "\"", "'", "\n", "\r\n", "\r", " ", "  ", "\t", "\u{0B}", "\u{0C}", "a", "key: value", "\"q\": 1", "[1, 2]", "x y",
                      "    indented", "\t\ttabbed", "", "é", "\u{00A0}", "\u{3000}", "中"]
        var state: UInt64 = 0xB10C_7E47
        func below(_ bound: Int) -> Int {
            state &+= 0x9E37_79B9_7F4A_7C15
            var mixed = state
            mixed = (mixed ^ (mixed >> 30)) &* 0xBF58_476D_1CE4_E5B9
            mixed = (mixed ^ (mixed >> 27)) &* 0x94D0_49BB_1331_11EB
            return Int((mixed ^ (mixed >> 31)) % UInt64(bound))
        }
        var asciiCount = 0
        for _ in 0..<20_000 {
            var text = ""
            for _ in 0..<below(16) { text += pieces[below(pieces.count)] }
            if text.utf8.allSatisfy({ byte in byte < 0x80 }) { asciiCount += 1 }
            XCTAssertEqual(EventModelDiagramBuilder.blockText(text), EventModelDiagramBuilder.blockTextOfScalars(text), text.debugDescription)
        }
        XCTAssertGreaterThan(asciiCount, 5_000, "most texts should take the bytes' path")
    }

    func testTheDocumentedBlocksKeepTheirLinesAndLoseTheirSharedIndentation() {
        XCTAssertEqual(EventModelDiagramBuilder.blockText("{\n    \"a\": 1,\n      \"b\": 2   \n}"), "\"a\": 1,\n  \"b\": 2")
        XCTAssertEqual(EventModelDiagramBuilder.blockText("\"one line\""), "one line")
        XCTAssertEqual(EventModelDiagramBuilder.blockText("{\r\n\r\n  x\r\n\r\n}"), "x")
    }
}
