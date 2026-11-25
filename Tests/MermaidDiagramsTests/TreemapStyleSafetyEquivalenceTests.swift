/**
 * File: TreemapStyleSafetyEquivalenceTests.swift
 * ----------------------------------------------
 * Layer: Tests
 * Description: A treemap class's value is refused as unsafe on its bytes exactly when 0.7.0's test, on its lowered text
 *              with Foundation's searches and a regular expression, refused it: random ASCII values made of the parts it
 *              looks for, white space of every kind and other characters, and values beyond ASCII; and a classDef's
 *              declarations are read alike whether or not they hold a comma.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 25/11/2026
 */

import Foundation
import XCTest
@testable import MermaidDiagrams

final class TreemapStyleSafetyEquivalenceTests: XCTestCase {
    /// 0.7.0's `TreemapClassTextStyle.isUnsafe`, frozen as main dad6fb8 had it.
    private static func referenceIsUnsafe(_ value: String) -> Bool {
        let lowered = value.lowercased()
        let unsafeParts = ["javascript:", "@import", "image-set", "/*", "<", ">", "{", "}", ";", "\\"]
        if unsafeParts.contains(where: { part in lowered.contains(part) }) { return true }
        return lowered.range(of: #"(url|expression)\s*\("#, options: .regularExpression) != nil
    }

    func testRandomValuesAreRefusedExactlyAsTheRegularExpressionRefusesThem() {
        var random = MapReadingMutations(seed: 0x7E_E5_AF, tokens: [])
        let pieces = ["url", "URL", "Url", "expression", "EXPRESSION", "uurl", "ur l", "(", ")", " ", "\t", "\n", "\r", "\u{0B}", "\u{0C}", "  ",
                      "javascript:", "JavaScript:", "@import", "image-set", "/*", "*/", "<", ">", "{", "}", ";", "\\", "#ff0000", "red", "rgb(1,2,3)",
                      "bold", "12px", "é", "\u{00A0}", "\u{2003}", "\u{0085}", "İ", "x", "-", ":"]
        for _ in 0..<20_000 {
            let value = (0..<random.below(8)).map { _ in pieces[random.below(pieces.count)] }.joined()
            XCTAssertEqual(TreemapClassTextStyle.isUnsafe(value), Self.referenceIsUnsafe(value), value.debugDescription)
        }
        for value in ["url(", "url \t\n\r\u{0C}(", "url\u{0B}(", "expression (x)", "urlx(", "a url b url(", "URL  (", "ex pression("] {
            XCTAssertEqual(TreemapClassTextStyle.isUnsafe(value), Self.referenceIsUnsafe(value), value.debugDescription)
        }
    }

    /// The separator's replacements change nothing in a text without a comma or the marker, which they are skipped for.
    func testDeclarationsWithoutACommaReadAsBefore() {
        for text in ["fill:#f96", "fill:#f96;stroke:#333", "fill:red\\;x", "color: blue ; font-size: 20px", "", ";;", "fill:red;color:#123"] {
            let read = TreemapClassStyle.reading(text)
            let separated = text.replacingOccurrences(of: "\\,", with: "\u{0}").replacingOccurrences(of: ",", with: ";")
                .replacingOccurrences(of: "\u{0}", with: ",")
            let expected = TreemapClassStyle.reading(separated + ",")
            XCTAssertEqual(read.style, expected.style, text)
            XCTAssertEqual(read.textStyle, expected.textStyle, text)
            XCTAssertEqual(read.unappliedCount, expected.unappliedCount, text)
        }
    }
}
