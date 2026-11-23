/**
 * File: VennUnsafeValueScanTests.swift
 * ------------------------------------
 * Layer: Tests
 * Description: Checks that the hand-written scan for unsafe style values finds what Pele's pattern, run as a regular
 *              expression, finds, on values put together from the pattern's pieces, blanks and other characters.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 23/11/2026
 */

import Foundation
@testable import MermaidDiagrams
import XCTest

final class VennUnsafeValueScanTests: XCTestCase {
    private static let pattern = #"url\s*\(|expression\s*\(|javascript:|[<>{};\\]|@import|image-set|/\*"#

    private static let pieces = ["url", "URL", "Url", "expression", "EXPRESSION", "javascript", "JavaScript:", ":", "@import", "@IMPORT", "image-set",
                                 "Image-Set", "(", ")", "/", "*", "/*", " ", "\t", "\n", "\r", "\u{0C}", "#f9f", "red", "5px", "<", ">", "{", "}", ";",
                                 "\\", "u", "rl", "ima", "ge-set", "@", "import", "-", "0", "x"]

    func testTheScanFindsWhatThePatternFinds() {
        var generator = SplitMixGenerator(state: 0x2545_F491_4F6C_DD1D)
        var values = Self.pieces
        for _ in 0..<20_000 {
            let count = Int(generator.next() % 6) + 1
            values.append((0..<count).map { _ in Self.pieces[Int(generator.next() % UInt64(Self.pieces.count))] }.joined())
        }
        for value in values {
            let byPattern = value.range(of: Self.pattern, options: [.regularExpression, .caseInsensitive]) != nil
            XCTAssertEqual(VennUnsafeValueScan.matchesUnsafePattern(value), byPattern, value.debugDescription)
        }
    }

    func testTextBeyondASCIIIsLeftToThePattern() {
        for value in ["ſtroke", "javaſcript:", "#ff0000 ✓", "url\u{2003}(", "imaɡe-set", "red\u{A0}"] {
            XCTAssertNil(VennUnsafeValueScan.matchesUnsafePattern(value))
            let byPattern = value.range(of: Self.pattern, options: [.regularExpression, .caseInsensitive]) != nil
            XCTAssertEqual(VennAppearance.isUnsafe(value), byPattern, value.debugDescription)
        }
    }
}

/// SplitMix64: the same values on every run.
private struct SplitMixGenerator {
    var state: UInt64

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var mixed = state
        mixed = (mixed ^ (mixed >> 30)) &* 0xBF58_476D_1CE4_E5B9
        mixed = (mixed ^ (mixed >> 27)) &* 0x94D0_49BB_1331_11EB
        return mixed ^ (mixed >> 31)
    }
}
