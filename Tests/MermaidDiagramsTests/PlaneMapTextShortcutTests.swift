/**
 * File: PlaneMapTextShortcutTests.swift
 * -------------------------------------
 * Layer: Tests
 * Description: The plane maps' text values taken on their bytes give what 0.7.0's character readings gave: a title's,
 *              an accessibility title's and description's runs of blanks made one, and a quoted string's text without
 *              its quotation marks, for every pairing of blanks, marks joining a quotation mark, prepended characters,
 *              line breaks, backslashes and plain ASCII, and for random texts of them.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 26/11/2026
 */

import XCTest
@testable import MermaidDiagrams

final class PlaneMapTextShortcutTests: XCTestCase {
    private static let pieces = ["a", "B", " ", "  ", "\t", " \t", "\u{301}", "\u{600}", "é", "\r\n", "\n", "\\", "\\n", "\"", "'", "\u{A0}", "\u{3000}",
                                 "\u{200D}", "x y", "%%", "🚀", ".", "\u{FEFF}"]

    /// Every text of up to three pieces, and its quoted forms, read by both.
    func testEveryShortTextIsReadAsTheCharacterReadingReadsIt() {
        var texts = [""]
        for first in Self.pieces {
            texts.append(first)
            for second in Self.pieces {
                texts.append(first + second)
                for third in Self.pieces { texts.append(first + second + third) }
            }
        }
        for text in texts { assertReadAsTheReference(text) }
    }

    func testRandomTextsAreReadAsTheCharacterReadingReadsThem() {
        var state: UInt64 = 0x9_1A_4E_7E
        for _ in 0..<20_000 {
            var text = ""
            for _ in 0..<(1 + Int(state >> 60)) {
                state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
                text += Self.pieces[Int((state >> 33) % UInt64(Self.pieces.count))]
            }
            assertReadAsTheReference(text)
        }
    }

    /// Compared byte for byte: Strings compare equal when their characters are canonically equivalent.
    private func assertReadAsTheReference(_ text: String, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(Array(PlaneMapText.singleSpaced(text).utf8), Array(ReferencePlaneMapText.singleSpaced(text).utf8), text.debugDescription,
                       file: file, line: line)
        XCTAssertEqual(Array(PlaneMapTerminalValues.title("title" + text).utf8), Array(ReferencePlaneMapTerminalValues.title("title" + text).utf8),
                       file: file, line: line)
        XCTAssertEqual(Array(PlaneMapTerminalValues.accessibilityTitle("accTitle:" + text).utf8),
                       Array(ReferencePlaneMapTerminalValues.accessibilityTitle("accTitle:" + text).utf8), file: file, line: line)
        for quote in ["\"", "'"] {
            let token = quote + text + quote
            XCTAssertEqual(Array(PlaneMapTerminalValues.string(token).utf8), Array(ReferencePlaneMapTerminalValues.string(token).utf8),
                           token.debugDescription, file: file, line: line)
        }
    }
}
