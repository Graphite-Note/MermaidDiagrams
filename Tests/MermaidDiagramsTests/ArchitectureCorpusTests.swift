/**
 * File: ArchitectureCorpusTests.swift
 * -----------------------------------
 * Layer: Tests
 * Description: Mermaid's 6 architecture documentation examples read and laid out, tight for a narrow column too, and
 *              generated architectures, every service, group and edge on the page and no two services in one place.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 19/11/2026
 */

import XCTest
@testable import MermaidDiagrams
@testable import MermaidDiagramsBenchmark

final class ArchitectureCorpusTests: XCTestCase {
    private let typography = DiagramTypography(font: DiagramFont(postScriptName: nil, size: 16))

    func testEveryDocumentationExampleIsLaidOutOnItsPage() throws {
        let examples = try ArchitectureCorpus.documentationExamples()
        XCTAssertEqual(examples.count, 6)
        for (index, example) in examples.enumerated() {
            let diagram = try ArchitectureReading.architecture(example)
            let layout = ArchitectureLayoutEngine.layout(diagram, typography: typography)
            XCTAssertEqual(layout.nodes.count, diagram.nodes.count, "example \(index)")
            Self.assertOnPage(layout, "example \(index)")
            PlaneMapPictures.write(DiagramScene(layout: layout), named: "architecture-documentation-\(index)")
            let tight = ArchitectureLayoutEngine.layout(diagram, typography: typography, availableWidth: 280, isTight: true)
            Self.assertOnPage(tight, "tight example \(index)")
            XCTAssertLessThanOrEqual(tight.size.width, layout.size.width, "example \(index)")
        }
    }

    func testGeneratedArchitecturesAreLaidOutOnTheirPage() throws {
        for count in [10, 40, 400] {
            let layout = ArchitectureLayoutEngine.layout(try ArchitectureReading.architecture(ArchitectureCorpus.generated(serviceCount: count)),
                                                         typography: typography)
            Self.assertOnPage(layout, "\(count) services")
            if count == 40 { PlaneMapPictures.write(DiagramScene(layout: layout), named: "architecture-generated-40") }
        }
    }

    static func assertOnPage(_ layout: ArchitectureLayout, _ message: String, file: StaticString = #filePath, line: UInt = #line) {
        let page = CGRect(origin: .zero, size: layout.size).insetBy(dx: -0.5, dy: -0.5)
        let squares = ArchitectureReading.squares(layout)
        for (identifier, square) in squares {
            XCTAssertTrue(page.contains(square), "\(message): \(identifier)", file: file, line: line)
            for (other, otherSquare) in squares where other < identifier && square.width > 0 && otherSquare.width > 0 {
                XCTAssertFalse(square.intersects(otherSquare), "\(message): \(identifier) and \(other)", file: file, line: line)
            }
        }
        for group in layout.groups { XCTAssertTrue(page.contains(group.frame), "\(message): \(group.identifier)", file: file, line: line) }
        for edge in layout.edges { XCTAssertTrue(page.contains(edge.path.start), "\(message): an edge", file: file, line: line) }
        for text in layout.edgeTexts { XCTAssertTrue(page.contains(text.frame), "\(message): an edge's text", file: file, line: line) }
    }
}
