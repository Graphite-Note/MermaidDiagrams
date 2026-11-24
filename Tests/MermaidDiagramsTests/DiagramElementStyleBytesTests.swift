/**
 * File: DiagramElementStyleBytesTests.swift
 * -----------------------------------------
 * Layer: Tests
 * Description: Checks that the style an ASCII list of declarations writes, read on its bytes, is the one 0.7.0 read
 *              from its characters (frozen as ReferenceDiagramElementStyle), with whether a declaration was not applied,
 *              on lists put together from properties, values, colons, commas, brackets and blanks, and on lists
 *              beyond ASCII, which are read through their characters.
 *
 * Authors: Bahey Shalash
 * Version: 0.2
 * Date: 24/11/2026
 */

@testable import MermaidDiagrams
import XCTest

final class DiagramElementStyleBytesTests: XCTestCase {
    private static let parts = ["fill", "FILL", "Stroke", "stroke-width", "color", ":", ":", ",", ",", " ", "\t", "  ", "#f9f", "#333", "4px", "rgb(", ")",
                                "1, 2, 3", "(", "5 5", "!important", "\n", "\r", "font-size", "none", ";", "x", "#FFAA0080", "#12", "#abcd", "red", "Grey",
                                "transparent", "stroke-dasharray", "2.5", "1e1", "inf", "-1", "17", "!IMPORTANT", "! important", "#f9fz", "rgba(1,2,3,0.5)"]

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
        for list in lists + lists.prefix(2_000).map({ list in list + "\u{A0}" }) + ["fill:#fff\u{A0}", "fill:\u{A0}#fff", "ﬁll:#fff", "fill:#ｆｆｆ"] {
            let read = DiagramElementStyle.reading(list)
            let expected = ReferenceDiagramElementStyle.reading(list)
            XCTAssertEqual(read.hasUnappliedDeclaration, expected.hasUnappliedDeclaration, list.debugDescription)
            XCTAssertTrue(Self.isIdentical(read.style, expected.style), "\(read.style), expected \(expected.style) for \(list.debugDescription)")
        }
    }

    /// Long lists of many declarations, parentheses, exclamation marks and colors are read as before, in bounded time.
    func testHostileListsAreReadAsBeforeAndBounded() {
        let lists = [
            String(repeating: "fill:#f9f,", count: 5_000), String(repeating: "(", count: 20_000) + "fill:red" + String(repeating: ")", count: 20_000),
            "fill:#fff " + String(repeating: "!", count: 40_000), String(repeating: "stroke-dasharray: 5 5 5 5,", count: 2_000),
            "color:rgb(" + String(repeating: "1,", count: 20_000) + "1)", String(repeating: ":", count: 40_000), String(repeating: ",", count: 40_000),
        ]
        let start = ContinuousClock.now
        for list in lists {
            let read = DiagramElementStyle.reading(list)
            let expected = ReferenceDiagramElementStyle.reading(list)
            XCTAssertEqual(read.hasUnappliedDeclaration, expected.hasUnappliedDeclaration, String(list.prefix(40)))
            XCTAssertTrue(Self.isIdentical(read.style, expected.style), String(list.prefix(40)))
        }
        XCTAssertLessThan(ContinuousClock.now - start, .seconds(20))
    }

    /// The styles are alike, their numbers to the bit.
    static func isIdentical(_ first: DiagramElementStyle, _ second: DiagramElementStyle) -> Bool {
        func same(_ one: DiagramColor?, _ other: DiagramColor?) -> Bool {
            guard let one, let other else { return one == nil && other == nil }
            return [one.red, one.green, one.blue, one.alpha].map(\.bitPattern) == [other.red, other.green, other.blue, other.alpha].map(\.bitPattern)
        }
        return same(first.fill, second.fill) && same(first.stroke, second.stroke) && same(first.textColor, second.textColor)
            && first.strokeWidth?.bitPattern == second.strokeWidth?.bitPattern
            && first.strokeDashLengths?.map(\.bitPattern) == second.strokeDashLengths?.map(\.bitPattern)
    }
}
