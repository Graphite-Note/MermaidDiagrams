/**
 * File: SequenceBlockKindTests.swift
 * ----------------------------------
 * Layer: Tests
 * Description: The keyword each sequence block shows in its tab, and the tab's width, measured in bold as it is drawn.
 *
 * Authors: Félix Chevalier, Bahey Shalash
 * Version: 0.2
 * Date: 23/11/2026
 */

import XCTest
@testable import MermaidDiagrams

final class SequenceBlockKindTests: XCTestCase {
    func testEachFramedBlockShowsTheKeywordMermaidWritesInItsTab() {
        let keywords = [SequenceBlockKind.loop, .alternatives, .optional, .parallel, .critical, .break].map(\.keyword)
        XCTAssertEqual(keywords, ["loop", "alt", "opt", "par", "critical", "break"])
    }

    func testAHighlightHasNoTab() {
        XCTAssertNil(SequenceBlockKind.highlight(nil).keyword)
        XCTAssertNil(SequenceBlockKind.highlight(SequenceHighlightColor(red: 1, green: 0, blue: 0)).keyword)
    }

    /// Pele measures a tab's keyword in bold at three quarters of the text's size and adds 14 (sequence/render.ts
    /// `frame.tabW`): in Arial at 16 points, `critical` is 38.69 points bold and its tab 52.69, where the regular 34
    /// made the documentation's critical blocks 5 points narrower than Pele's.
    func testATabIsAsWideAsItsKeywordInBold() throws {
        let typography = DiagramTypography(font: DiagramFont(postScriptName: "ArialMT", size: 16))
        let diagram = try SequenceReading.sequence("sequenceDiagram\n critical Establish a connection to the DB\n  Service-->DB: connect\n end")
        let block = try XCTUnwrap(SequenceLayoutEngine.layout(diagram, typography: typography).blocks.first)
        let bold = typography.measurer(size: 12, isBold: true)
        XCTAssertEqual(block.tab.width, bold.width(of: "critical") + SequenceSpacing.tabExtraWidth, accuracy: 0.01)
        XCTAssertEqual(block.tab.width, 52.69, accuracy: 0.05)
    }
}
