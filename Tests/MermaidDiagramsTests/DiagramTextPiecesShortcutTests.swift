/**
 * File: DiagramTextPiecesShortcutTests.swift
 * ------------------------------------------
 * Layer: Tests
 * Description: Checks that the pieces of ASCII text cut at its bytes, and the byte ranges found for the pieces of any
 *              text, are the pieces Pele's pattern gives read scalar by scalar, on texts made of words, white space,
 *              brackets, punctuation, Chinese and Japanese text, hints, accents, combining marks and emoji.
 *
 * Authors: Bahey Shalash
 * Version: 0.2
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

    /// Text beyond ASCII of one, two, three and four bytes a scalar, which wrapping cuts at the byte positions of the
    /// scalars' pieces.
    private static let partsBeyondASCII = ["word", " ", "\t", "\u{A0}", "\u{2003}", "\u{3000}", "\u{FEFF}", "\u{AD}", "\u{200B}", "日本語", "中", "、",
                                           "。", "（", "「", "」", "é", "e\u{301}", "\u{1F600}", "\u{1F469}\u{200D}\u{1F4BB}", "ü", "→", "«", "»", "(", ")"]

    func testByteRangesOfPiecesAreThePiecesReadScalarByScalar() {
        var state: UInt64 = 0x0B17_E5CA_1A85
        var checkedBeyondASCII = 0
        for _ in 0..<10_000 {
            var text = ""
            state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            for _ in 0..<Int((state >> 40) % 10) {
                state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
                text += Self.partsBeyondASCII[Int((state >> 33) % UInt64(Self.partsBeyondASCII.count))]
            }
            // A text in the middle of others' bytes, as a span of a line is.
            let bytes = Array(("ab" + text + "cd").utf8)
            var ranges: [Range<Int>] = []
            DiagramTextPieces.appendPieces(ofScalarsIn: bytes[2..<(bytes.count - 2)], to: &ranges)
            let pieces = ranges.map { range in String(decoding: bytes[range], as: UTF8.self) }
            XCTAssertEqual(pieces, DiagramTextPieces.pieces(ofScalars: text), text.debugDescription)
            XCTAssertEqual(ranges.first?.lowerBound ?? 2, 2, text.debugDescription)
            XCTAssertEqual(ranges.last?.upperBound ?? 2, bytes.count - 2, text.debugDescription)
            if text.utf8.contains(where: { byte in byte >= 0x80 }) { checkedBeyondASCII += 1 }
        }
        XCTAssertGreaterThan(checkedBeyondASCII, 5_000)
    }
}
