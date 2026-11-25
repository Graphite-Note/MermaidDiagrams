/**
 * File: BlockAppearanceBytesTests.swift
 * -------------------------------------
 * Layer: Tests
 * Description: A block's look read from its declarations' bytes is, field for field, the look 0.7.0 read through their
 *              characters (ReferenceBlockAppearance), on the corpora's styles and classes and on thousands of random
 *              declarations: properties in any case, `!important` anywhere, unsafe values, sizes, weights, and text
 *              beyond ASCII.
 *
 * Authors: Bahey Shalash
 * Version: 0.2
 * Date: 25/11/2026
 */

import XCTest
@testable import MermaidDiagrams

final class BlockAppearanceBytesTests: XCTestCase {
    private func assertSameLook(classNames: [String]?, styles: [String]?, classes: [String: BlockClassDefinition], file: StaticString = #filePath,
                                line: UInt = #line) {
        let look = BlockAppearance(classNames: classNames, styles: styles, classes: classes)
        let reference = ReferenceBlockAppearance(classNames: classNames, styles: styles, classes: classes)
        let label = "\(String(describing: classNames)) \(String(describing: styles))"
        XCTAssertEqual(look.style, reference.style, label, file: file, line: line)
        XCTAssertEqual(look.isBold, reference.isBold, label, file: file, line: line)
        XCTAssertEqual(look.isItalic, reference.isItalic, label, file: file, line: line)
        XCTAssertEqual(look.fontSize, reference.fontSize, label, file: file, line: line)
    }

    func testTheCorporaStylesAndClassesLookAsZeroSevenRead() throws {
        var compared = 0
        for source in try ChartReadingEquivalence.corpusSources(keywords: ["block", "block-beta"]) + BlockReadingEquivalenceTests.specificationTexts {
            guard case .block(let diagram)? = try? MermaidDiagramReader.read(source, limits: .standard) else { continue }
            for block in diagram.blocks {
                assertSameLook(classNames: block.classNames, styles: block.styles, classes: diagram.classes)
                compared += 1
            }
        }
        XCTAssertGreaterThan(compared, 100)
    }

    func testRandomDeclarationsLookAsZeroSevenRead() {
        var state: UInt64 = 0xA77E_A2A9
        func next(_ bound: Int) -> Int {
            state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            return Int((state >> 33) % UInt64(bound))
        }
        let properties = ["fill", "Fill", " stroke ", "STROKE-WIDTH", "stroke-dasharray", "color", "font-weight", "Font-Style", "font-size", "opacity",
                          "", "fill\u{A0}", "fïll"]
        let values = ["#f96", "red", " #333 !important", "4px", "5 5", "bold", "BOLD", "700", "599", "bolder", "italic", "20px", "14", "0", "300px",
                      "url(x)", "expression (1)", "a;b", "!IMPORTANT", "!imp!importantortant", "", "javascript:alert", "<b>", "rgb(1,2,3)", "é", "\u{3000}red"]
        for _ in 0..<6_000 {
            var entry = ""
            for index in 0...next(3) {
                if index > 0 { entry += next(4) == 0 ? ";;" : ";" }
                entry += properties[next(properties.count)] + (next(9) == 0 ? "" : ":") + values[next(values.count)]
            }
            let classes = ["hot": BlockClassDefinition(styles: [entry]), "default": BlockClassDefinition(styles: [values[next(values.count)]])]
            assertSameLook(classNames: nil, styles: [entry], classes: [:])
            assertSameLook(classNames: next(2) == 0 ? ["hot"] : nil, styles: next(2) == 0 ? [entry, entry] : nil, classes: classes)
        }
    }

    /// Removing every `!important` again and again in one pass leaves what removing the first again and again leaves, on
    /// random runs of its pieces, cases and nestings.
    func testImportanceIsTakenOutAsRemovingTheFirstAgainAndAgain() {
        func removedOneByOne(_ text: String) -> [UInt8] {
            var value = Array(text.utf8)
            let word = Array("!important".utf8)
            while let start = (0..<max(0, value.count - word.count + 1)).first(where: { start in
                (0..<word.count).allSatisfy { offset in MermaidByte.lowercased(value[start + offset]) == word[offset] }
            }) {
                value.removeSubrange(start..<(start + word.count))
            }
            return value
        }
        var state: UInt64 = 0x1A90_47A2
        func next(_ bound: Int) -> Int {
            state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            return Int((state >> 33) % UInt64(bound))
        }
        let pieces = ["!", "!imp", "ortant", "!important", "!IMPORTANT", "!Important", "important", "t", "i", "x", " ", "red", "!!", "nt"]
        for _ in 0..<20_000 {
            let text = (0..<next(12)).map { _ in pieces[next(pieces.count)] }.joined()
            let removed = Array(text.utf8).withUnsafeBufferPointer { bytes in BlockAppearance.withoutImportance(bytes) }
            XCTAssertEqual(removed, removedOneByOne(text), text)
        }
    }

    /// A style of many nested or repeated `!important`s, `url`s and declarations reads in time that grows with its length.
    func testLongStylesReadInLinearTime() {
        let nested = String(repeating: "!imp", count: 20_000) + String(repeating: "ortant", count: 20_000)
        let texts = ["fill:" + nested + "red", "fill:" + String(repeating: "!important", count: 40_000) + "#f96",
                     "color:" + String(repeating: "url ", count: 50_000), String(repeating: "fill:red;", count: 40_000),
                     "stroke:" + String(repeating: "u", count: 200_000)]
        let start = Date()
        for text in texts {
            let look = BlockAppearance(classNames: nil, styles: [text], classes: [:])
            if text.hasPrefix("fill:!") { XCTAssertNotNil(look.style.fill, String(text.prefix(40))) }
        }
        XCTAssertLessThan(Date().timeIntervalSince(start), 5)
    }
}
