/**
 * File: DiagramTextBlockTests.swift
 * ---------------------------------
 * Layer: Tests
 * Description: Lines of text measured, wrapped at spaces and placed as a diagram's text blocks are.
 *
 * Authors: Félix Chevalier, Bahey Shalash
 * Version: 0.1
 * Date: 23/11/2026
 */

import XCTest
@testable import MermaidDiagrams

final class DiagramTextBlockTests: XCTestCase {
    private let measurer = UniformWidthTextMeasurer()

    func testALineWiderThanTheLimitWrapsAtSpaces() {
        let block = DiagramTextBlock(label: DiagramLabel("one two three four"), measurer: measurer, maximumWidth: 79)
        XCTAssertEqual(block.lines, ["one two", "three", "four"])
        XCTAssertEqual(block.lineWidths, [56, 40, 32])
        // Three lines 1.3 times the size apart, rounded (21 at 16), as Pele's layoutLabel sets a text of several lines.
        XCTAssertEqual(block.size, CGSize(width: 56, height: 3 * 21))
    }

    func testAWordWiderThanTheLimitStaysWhole() {
        let block = DiagramTextBlock(label: DiagramLabel("supercalifragilistic"), measurer: measurer, maximumWidth: 80)
        XCTAssertEqual(block.lines, ["supercalifragilistic"])
    }

    func testBrokenLinesStayBrokenAndAnEmptyLabelHasNoLines() {
        XCTAssertEqual(DiagramTextBlock(label: DiagramLabel(lines: ["a", "b"]), measurer: measurer, maximumWidth: 200).lines, ["a", "b"])
        XCTAssertTrue(DiagramTextBlock(label: DiagramLabel(""), measurer: measurer, maximumWidth: 200).lines.isEmpty)
    }
}
