/**
 * File: BlockUnsafeValueTests.swift
 * ---------------------------------
 * Layer: Tests
 * Description: Checks that a block diagram's unsafe style values read from the bytes of ASCII values are those its
 *              search through characters finds, on values put together from the unsafe words, blanks and brackets.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 23/11/2026
 */

@testable import MermaidDiagrams
import XCTest

final class BlockUnsafeValueTests: XCTestCase {
    private static let pieces = ["url", "URL", "expression", "Expression", "javascript:", "JAVASCRIPT", ":", "@import", "image-set", "/", "*", "(", ")",
                                 " ", "\t", "\n", "<", ">", "{", "}", ";", "\\", "red", "#fff", "5px", "x"]

    func testTheBytesFindWhatTheCharactersFind() {
        var state: UInt64 = 0x5DEE_CE66_D1CE_4E5B
        var values = Self.pieces
        for _ in 0..<20_000 {
            state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            var value = ""
            for shift in stride(from: 0, to: 30, by: 5) where (state >> (shift + 30)) & 1 == 1 || shift == 0 {
                value += Self.pieces[Int((state >> shift) % UInt64(Self.pieces.count))]
            }
            values.append(value)
        }
        for value in values {
            XCTAssertEqual(BlockAppearance.isUnsafe(ascii: value), Self.isUnsafeByCharacters(value), value.debugDescription)
        }
        XCTAssertNil(BlockAppearance.isUnsafe(ascii: "url\u{A0}("))
    }

    /// The search through the value's characters the package keeps for text beyond ASCII.
    private static func isUnsafeByCharacters(_ value: String) -> Bool {
        let lowered = value.lowercased()
        if lowered.contains("javascript:") || lowered.contains("@import") || lowered.contains("image-set") || lowered.contains("/*") { return true }
        if value.contains(where: { character in "<>{};\\".contains(character) }) { return true }
        for function in ["url", "expression"] {
            guard let range = lowered.range(of: function) else { continue }
            if lowered[range.upperBound...].drop(while: { character in character == " " || character == "\t" }).first == "(" { return true }
        }
        return false
    }
}
