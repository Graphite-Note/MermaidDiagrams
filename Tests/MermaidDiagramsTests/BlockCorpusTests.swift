/**
 * File: BlockCorpusTests.swift
 * ----------------------------
 * Layer: Tests
 * Description: Mermaid's 30 block diagram documentation examples read and laid out, tight for a narrow column too,
 *              and generated grids, every block inside the page and no number past what is drawn.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 19/11/2026
 */

import XCTest
@testable import MermaidDiagrams
@testable import MermaidDiagramsBenchmark

final class BlockCorpusTests: XCTestCase {
    private let typography = DiagramTypography(font: DiagramFont(postScriptName: nil, size: 16))

    /// Every documentation example reads but the one that is wrong in Mermaid too (a `style` statement with `fill#969`
    /// reads, as Pele's lexer takes it to the end of its line), and lays out with every block and edge on the page.
    func testEveryDocumentationExampleIsLaidOutOnItsPage() throws {
        let examples = try BlockCorpus.documentationExamples()
        XCTAssertEqual(examples.count, 30)
        for (index, example) in examples.enumerated() {
            let diagram = try BlockReading.block(example)
            let layout = try BlockLayoutEngine.layout(diagram, typography: typography)
            XCTAssertFalse(layout.nodes.isEmpty, "example \(index)")
            Self.assertOnPage(layout, "example \(index)")
            PlaneMapPictures.write(DiagramScene(layout: layout), named: "block-documentation-\(index)")
            let tight = try BlockLayoutEngine.layout(diagram, typography: typography, availableWidth: 280, isTight: true)
            Self.assertOnPage(tight, "tight example \(index)")
            XCTAssertLessThanOrEqual(tight.size.width, layout.size.width, "example \(index)")
        }
    }

    /// Generated grids of up to 600 blocks, with composites, shapes and labelled edges.
    func testGeneratedGridsAreLaidOutOnTheirPage() throws {
        for count in [12, 60, 600] {
            let layout = try BlockLayoutEngine.layout(try BlockReading.block(BlockCorpus.grid(blockCount: count)), typography: typography)
            Self.assertOnPage(layout, "grid of \(count)")
            if count == 60 { PlaneMapPictures.write(DiagramScene(layout: layout), named: "block-generated-60") }
        }
    }

    static func assertOnPage(_ layout: BlockLayout, _ message: String, file: StaticString = #filePath, line: UInt = #line) {
        let page = CGRect(origin: .zero, size: layout.size).insetBy(dx: -0.5, dy: -0.5)
        XCTAssertTrue(layout.size.width.isFinite && layout.size.height.isFinite, message, file: file, line: line)
        for node in layout.nodes { XCTAssertTrue(page.contains(node.frame), "\(message): \(node.identifier) \(node.frame)", file: file, line: line) }
        for composite in layout.composites {
            XCTAssertTrue(page.contains(composite.frame), "\(message): \(composite.identifier)", file: file, line: line)
        }
        for edge in layout.edges {
            XCTAssertTrue(page.contains(edge.path.start), "\(message): \(edge.identifier)", file: file, line: line)
            if let text = edge.text { XCTAssertTrue(page.contains(text.frame), "\(message): \(edge.identifier) text", file: file, line: line) }
        }
    }
}
