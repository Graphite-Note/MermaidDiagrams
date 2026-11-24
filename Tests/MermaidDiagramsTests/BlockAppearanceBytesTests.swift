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
 * Version: 0.1
 * Date: 24/11/2026
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
}
