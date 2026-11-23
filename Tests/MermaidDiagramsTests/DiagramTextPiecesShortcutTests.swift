/**
 * File: DiagramTextPiecesShortcutTests.swift
 * ------------------------------------------
 * Layer: Tests
 * Description: Checks that the pieces of ASCII text cut at its bytes are the pieces Pele's pattern gives read scalar
 *              by scalar, on texts made of words, spaces, tabs, line breaks, brackets and punctuation.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 23/11/2026
 */

@testable import MermaidDiagrams
import XCTest

final class DiagramTextPiecesShortcutTests: XCTestCase {
    private static let parts = ["word", "a", " ", "  ", "\t", "\n", "\r", "\u{0B}", "\u{0C}", "(", "((", ")", "[", "]", "{", "}", ",", ".", ":", ";", "!",
                                "?", "-", "x1", "Ab", "\"", "'", "_"]

    func testASCIIPiecesAreThePiecesReadScalarByScalar() {
        var state: UInt64 = 0xDEAD_BEEF_CAFE_F00D
        var texts = Self.parts + [""]
        for _ in 0..<20_000 {
            var text = ""
            for _ in 0..<Int(state % 9) {
                state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
                text += Self.parts[Int((state >> 33) % UInt64(Self.parts.count))]
            }
            state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            texts.append(text)
        }
        for text in texts {
            XCTAssertEqual(DiagramTextPieces.pieces(ofASCII: text), DiagramTextPieces.pieces(ofScalars: text), text.debugDescription)
        }
        XCTAssertNil(DiagramTextPieces.pieces(ofASCII: "日本 語"))
    }
}
