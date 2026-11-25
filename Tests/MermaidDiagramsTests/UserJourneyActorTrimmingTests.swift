/**
 * File: UserJourneyActorTrimmingTests.swift
 * -----------------------------------------
 * Layer: Tests
 * Description: A user journey's actor names of ASCII alone, trimmed on their bytes, keep the same Unicode scalars as
 *              when they are trimmed scalar by scalar through Unicode's White_Space property.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 24/11/2026
 */

import XCTest
@testable import MermaidDiagrams

final class UserJourneyActorTrimmingTests: XCTestCase {
    /// Names of letters, blanks, every ASCII control character around them (the tab to the carriage return have the
    /// White_Space property, the information separators U+001C to U+001F do not), carriage return and line feed pairs,
    /// and characters beyond ASCII, which take the scalars' path.
    func testNamesTrimmedOnTheirBytesKeepTheScalarsTrimmedOneByOne() {
        var pieces = ["a", "Dad", "b c", " ", "  ", "\r\n", "\u{0085}", "\u{00A0}", "é", "\u{2028}", "#", ",", "\u{7F}"]
        pieces += (0..<0x20).map { value in String(UnicodeScalar(UInt8(value))) }
        var state: UInt64 = 0xAC_70_12_77
        func below(_ bound: Int) -> Int {
            state &+= 0x9E37_79B9_7F4A_7C15
            var mixed = state
            mixed = (mixed ^ (mixed >> 30)) &* 0xBF58_476D_1CE4_E5B9
            mixed = (mixed ^ (mixed >> 27)) &* 0x94D0_49BB_1331_11EB
            return Int((mixed ^ (mixed >> 31)) % UInt64(bound))
        }
        var asciiCount = 0
        for _ in 0..<20_000 {
            var name = ""
            for _ in 0..<below(10) { name += pieces[below(pieces.count)] }
            if name.utf8.allSatisfy({ byte in byte < 0x80 }) { asciiCount += 1 }
            let trimmed = UserJourneyDiagramBuilder.trimmed(Substring(name))
            let expected = UserJourneyDiagramBuilder.trimmedScalarByScalar(Substring(name))
            XCTAssertEqual(Array(trimmed.unicodeScalars), Array(expected.unicodeScalars), name.debugDescription)
        }
        XCTAssertGreaterThan(asciiCount, 5_000, "most names should take the bytes' path")
    }

    func testTheWhiteSpaceOfASCIIIsTrimmedAndTheInformationSeparatorsAreKept() {
        XCTAssertEqual(UserJourneyDiagramBuilder.trimmed(" \t\u{0B}\u{0C}\r\nDad \r\n"), "Dad")
        XCTAssertEqual(Array(UserJourneyDiagramBuilder.trimmed("\u{1C}Dad\u{1F}").unicodeScalars), Array("\u{1C}Dad\u{1F}".unicodeScalars))
    }
}
