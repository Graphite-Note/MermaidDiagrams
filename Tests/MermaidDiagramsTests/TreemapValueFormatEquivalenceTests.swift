/**
 * File: TreemapValueFormatEquivalenceTests.swift
 * ----------------------------------------------
 * Layer: Tests
 * Description: Checks that a treemap's value formats read on their bytes write every value as 0.7.0's regular expression
 *              made them write it, and that its classDef texts separated on their bytes read as Foundation's replacements
 *              made them read, over the corpora's specifiers and classes, random and hostile texts.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 25/11/2026
 */

import Foundation
import XCTest
@testable import MermaidDiagrams

final class TreemapValueFormatEquivalenceTests: XCTestCase {
    private static let values: [Double] = [0, 1, -1, 0.5, 1.5, 2.5, -2.5, 12.6, 0.357, 1_234, 1_234_567.5, -1_234.5, 700_000, 1e21, 1e-7, 0.1, 0.2,
                                           0.30000000000000004, 1_000.10, 99.96, 123_456_789.125, 4_294_967_296, 0.125, 9.995, 1.005, .infinity,
                                           -.infinity, .nan, 1e300, 5e-324, 1_000_000_000_000_000]

    private static let specifierPieces = ["<", ">", "=", "^", "*", "x", "-", "+", "(", " ", "$", "0", "1", "7", "12", "007", ",", ".", ".2", ".007",
                                          "~", "f", "%", "d", "e", "s", "Z", "\\", "\n", "\r", "\t", "é", "中", "🚀", "\u{2028}", "\u{0085}",
                                          "\u{00A0}", ".999", "$0,0", ",.2f", "\u{0}", "\u{7F}"]

    private func assertSameTexts(_ specifier: String, file: StaticString = #filePath, line: UInt = #line) {
        let format = TreemapValueFormat(specifier: specifier)
        let reference = ReferenceTreemapValueFormat(specifier: specifier)
        for value in Self.values {
            XCTAssertEqual(format.text(value), reference.text(value), "\(specifier.debugDescription) of \(value)", file: file, line: line)
        }
    }

    func testTheSpecifiersOfTheCorporaAndTheDocumentationWriteAsBefore() throws {
        var specifiers = [",", "", "$0,0", "$", ".1f", ".1%", "$.2f", "$,.2f", "$.1%", "d", "+,", ".3~f", "not a format", ".999f", ".007f", ".000f",
                          ".0000000000000000000000003f", ".2e", ".0e", ".2~f", ",.2~f", ".3", "x", "<", "<<", "^5", "*<+$010,.3~f", "=^", "^<f"]
        for text in try MapReadingEquivalence.everyText() where text.contains("valueFormat") {
            for match in text.components(separatedBy: "valueFormat").dropFirst() {
                specifiers.append(String(match.prefix(24)))
                specifiers.append(String(match.drop { character in character == "'" || character == "\"" || character == ":" || character == " " }
                    .prefix { character in character != "'" && character != "\"" && character != "\n" }))
            }
        }
        for specifier in specifiers { assertSameTexts(specifier) }
    }

    func testRandomSpecifiersWriteAsTheRegularExpressionReadsThem() {
        var random = MapReadingMutations(seed: 0x7EE_F0_4A7, tokens: [])
        for _ in 0..<6_000 {
            let specifier = (0..<random.below(7)).map { _ in Self.specifierPieces[random.below(Self.specifierPieces.count)] }.joined()
            assertSameTexts(specifier)
        }
    }

    func testEveryPrintableByteInEachPlaceWritesAsBefore() {
        for byte in 0x20..<0x7F {
            let character = String(UnicodeScalar(UInt8(byte)))
            for specifier in [character, character + "<", "<" + character, character + "<,", character + "^.2f", ",.2" + character, "$" + character,
                              character + character + "d", "+$" + character + ".1~e"] {
                assertSameTexts(specifier)
            }
        }
    }

    func testLongSpecifiersFinishQuickly() {
        let start = Date()
        for specifier in [String(repeating: "0", count: 50_000) + "x", String(repeating: "9", count: 100_000), "." + String(repeating: "1", count: 100_000),
                          String(repeating: "<", count: 100_000), String(repeating: ",", count: 100_000)] {
            assertSameTexts(specifier)
        }
        XCTAssertLessThan(Date().timeIntervalSince(start), 5)
    }

    func testClassTextsSeparateAsFoundationSeparatedThem() throws {
        var texts = ["fill:#f96,stroke:#333", "fill:red\\,blue", "\\\\,", "a\u{0}b,c", ",,,", "\\", "\\,\\,", "fill:#f96, font-size: 20px, font-weight:bold",
                     "color:rgb(1\\,2\\,3),stroke-width:4px", "fill:é,stroke:#000", ",\u{0301}fill:red", "\\,\u{0301}"]
        for text in try MapReadingEquivalence.everyText() where text.contains("classDef") {
            for line in text.split(separator: "\n") where line.contains("classDef") { texts.append(String(line.drop { character in character != " " })) }
        }
        var random = MapReadingMutations(seed: 0xC1A55, tokens: [])
        let pieces = ["fill", ":", "#f96", ",", "\\", "\\,", ";", " ", "stroke", "red", "font-size", "20px", "font-weight", "bold", "\u{0}", "é", "\u{0301}",
                      "color", "rgb(1,2,3)", "opacity", "0.5", "!important", "\t", "url(", "font-style", "italic"]
        for _ in 0..<6_000 { texts.append((0..<random.below(10)).map { _ in pieces[random.below(pieces.count)] }.joined()) }
        for text in texts {
            let read = TreemapClassStyle.reading(text)
            let reference = ReferenceTreemapClassStyle.reading(text)
            XCTAssertEqual(read.style, reference.style, text.debugDescription)
            XCTAssertEqual(read.textStyle, reference.textStyle, text.debugDescription)
            XCTAssertEqual(read.unappliedCount, reference.unappliedCount, text.debugDescription)
        }
    }
}
