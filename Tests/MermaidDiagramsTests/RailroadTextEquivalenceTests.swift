/**
 * File: RailroadTextEquivalenceTests.swift
 * ----------------------------------------
 * Layer: Tests
 * Description: A railroad diagram's quoted strings without a backslash, read on their bytes, and its texts without a code,
 *              a line break or a tab, shown as written, are what 0.7.0 read scalar by scalar, for texts of quotation
 *              marks, escapes, codes, line breaks and characters beyond ASCII put together at random.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 25/11/2026
 */

import XCTest
@testable import MermaidDiagrams

final class RailroadTextEquivalenceTests: XCTestCase {
    /// 0.7.0's `RailroadParser.unescaped`, frozen as main dad6fb8 has it.
    private static func referenceUnescaped(_ quoted: String) -> String {
        let scalars = Array(quoted.unicodeScalars)
        guard scalars.count >= 2 else { return "" }
        var text = String.UnicodeScalarView()
        var index = 1
        while index < scalars.count - 1 {
            var scalar = scalars[index]
            if scalar == "\\", index + 1 < scalars.count - 1 {
                index += 1
                switch scalars[index] {
                case "n": scalar = "\n"
                case "r": scalar = "\r"
                case "t": scalar = "\t"
                default: scalar = scalars[index]
                }
            }
            text.append(scalar)
            index += 1
        }
        return String(text)
    }

    private static let pieces = ["\"", "'", "a", "bc", " ", "\\", "\\n", "\\\"", "#35;", "#quot;", "#", ";", "\n", "\r", "\t", "é", "e\u{301}", "\u{301}",
                                 "中", "<br>", "*", "␣"]

    private func texts(seed: UInt64, count: Int) -> [String] {
        var state = seed
        func below(_ bound: Int) -> Int {
            state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            return Int((state >> 33) % UInt64(bound))
        }
        return (0..<count).map { _ in (0..<below(7)).map { _ in Self.pieces[below(Self.pieces.count)] }.joined() }
    }

    func testStringsAreUnescapedAsZeroSevenUnescapedThem() {
        for text in texts(seed: 0x2A11_20AD, count: 30_000) {
            let read = RailroadParser.unescaped(text)
            XCTAssertEqual(Array(read.unicodeScalars), Array(Self.referenceUnescaped(text).unicodeScalars), text.debugDescription)
        }
    }

    /// `shown` with its shortcut taken away: every text read scalar by scalar.
    func testTextsAreShownAsScalarByScalar() {
        for text in texts(seed: 0x5110_E7, count: 30_000) {
            let shown = RailroadText.shown(text)
            let scalarByScalar = RailroadText.shown(text + "\t")
            XCTAssertEqual(Array((shown + "\\t").unicodeScalars), Array(scalarByScalar.unicodeScalars), text.debugDescription)
        }
    }

    /// A notation's keyword, told on the bytes of an ASCII keyword, is the one Unicode's lowering and Swift's characters
    /// tell, for keywords of every case, cut short, run on, and with characters beyond ASCII.
    func testNotationsAreToldAsUnicodesLoweringTellsThem() {
        let pieces = ["railroad", "RAILROAD", "Railroad", "-", "beta", "BETA", "ebnf", "EBNF", "abnf", "peg", "PEG", "-beta", "x", "İ", "ß", "\u{301}", ""]
        var state: UInt64 = 0x2A11_2040
        func below(_ bound: Int) -> Int {
            state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            return Int((state >> 33) % UInt64(bound))
        }
        func reference(_ keyword: String) -> RailroadNotation? {
            let lowercased = keyword.lowercased()
            return RailroadNotation.allCases.first { notation in lowercased.hasPrefix(notation.keyword) }
        }
        for _ in 0..<20_000 {
            let keyword = (0..<below(6)).map { _ in pieces[below(pieces.count)] }.joined()
            XCTAssertEqual(RailroadNotation(typeKeyword: keyword), reference(keyword), keyword.debugDescription)
        }
        for notation in RailroadNotation.allCases {
            XCTAssertEqual(RailroadNotation(typeKeyword: notation.keyword), notation)
            XCTAssertEqual(RailroadNotation(typeKeyword: notation.keyword.uppercased() + "x"), notation)
        }
    }
}
