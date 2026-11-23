/**
 * File: DiagramElementStyleBytesTests.swift
 * -----------------------------------------
 * Layer: Tests
 * Description: Checks that the declarations of an ASCII style list read from its bytes are those read from its
 *              characters, on lists put together from properties, values, colons, commas, brackets and blanks.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 23/11/2026
 */

@testable import MermaidDiagrams
import XCTest

final class DiagramElementStyleBytesTests: XCTestCase {
    private static let parts = ["fill", "FILL", "Stroke", "stroke-width", "color", ":", ":", ",", ",", " ", "\t", "  ", "#f9f", "#333", "4px", "rgb(", ")",
                                "1, 2, 3", "(", "5 5", "!important", "\n", "\r", "font-size", "none", ";", "x"]

    func testTheBytesReadWhatTheCharactersRead() {
        var state: UInt64 = 0x1234_5678_9ABC_DEF1
        var lists = Self.parts + [""]
        for _ in 0..<20_000 {
            var list = ""
            state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            for _ in 0..<Int((state >> 40) % 10) {
                state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
                list += Self.parts[Int((state >> 33) % UInt64(Self.parts.count))]
            }
            lists.append(list)
        }
        for list in lists {
            guard let bytes = DiagramElementStyle.asciiPropertiesAndValues(list) else { return XCTFail("\(list.debugDescription) is ASCII") }
            let characters = DiagramElementStyle.propertiesAndValues(list)
            XCTAssertEqual(bytes.map(\.property), characters.map(\.property), list.debugDescription)
            XCTAssertEqual(bytes.map(\.value), characters.map(\.value), list.debugDescription)
        }
        XCTAssertNil(DiagramElementStyle.asciiPropertiesAndValues("fill:#fff\u{A0}"))
    }
}
