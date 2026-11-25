/**
 * File: PacketLabelTrimmingTests.swift
 * ------------------------------------
 * Layer: Tests
 * Description: A packet field's label, its entity codes read, is trimmed on its bytes as Foundation trims it: random
 *              labels of every white space of ASCII and beyond it, written or as entity codes, give the text Foundation's
 *              trimming of the decoded label gives.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 25/11/2026
 */

import Foundation
import XCTest
@testable import MermaidDiagrams

final class PacketLabelTrimmingTests: XCTestCase {
    func testLabelsAreTrimmedAsFoundationTrimsThem() {
        let pieces = ["\t", "\n", "\u{000B}", "\u{000C}", "\r", " ", "\u{00A0}", "\u{2003}", "\u{0085}", "\u{FEFF}", "\u{1C}", "&#11;", "&#12;",
                      "&#9;", "&#160;", "&#x2003;", "&nbsp;", "&amp;", "a", "Bit", "é", "<br>", "0x1F"]
        var seed: UInt64 = 0x9AC4_E7
        func next(_ bound: Int) -> Int {
            seed = seed &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            return Int((seed >> 33) % UInt64(bound))
        }
        for _ in 0..<20_000 {
            let label = (0..<(1 + next(6))).map { _ in pieces[next(pieces.count)] }.joined()
            let expected = DiagramLabelDecoder.decodingEntities(label).trimmingCharacters(in: .whitespacesAndNewlines)
            XCTAssertEqual(PacketTextBlocks.trimmedLabel(label), expected, label.debugDescription)
        }
    }
}
