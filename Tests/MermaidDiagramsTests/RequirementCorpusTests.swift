/**
 * File: RequirementCorpusTests.swift
 * ----------------------------------
 * Layer: Tests
 * Description: Mermaid's requirement diagram documentation examples and generated diagrams read, laid out with their
 *              boxes apart and on the page, and prepared with a narrow scene where they run across.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 19/11/2026
 */

import XCTest
@testable import MermaidDiagrams
@testable import MermaidDiagramsBenchmark

final class RequirementCorpusTests: XCTestCase {
    private let typography = DiagramTypography(font: DiagramFont(postScriptName: nil, size: 16))

    func testEveryDocumentationExampleIsReadAndLaidOutWithItsBoxesApart() throws {
        let examples = try RequirementCorpus.documentationExamples()
        XCTAssertEqual(examples.count, 9)
        for (index, example) in examples.enumerated() {
            let diagram = try RequirementParserTests.read(example)
            XCTAssertFalse(diagram.requirements.isEmpty, example)
            let layout = try RequirementLayoutEngine.layout(diagram, typography: typography, limits: .standard)
            XCTAssertEqual(layout.boxes.count, diagram.requirements.count + diagram.elements.count)
            Self.assertBoxesApart(layout)
            PlaneMapPictures.write(DiagramScene(layout: layout), named: "requirement-documentation-\(index)")
        }
    }

    func testGeneratedDiagramsAcrossAndDownAreLaidOutWithTheirBoxesApart() throws {
        for direction in ["TB", "LR", "BT", "RL"] {
            let diagram = try RequirementParserTests.read(RequirementCorpus.generated(requirementCount: 12, direction: direction))
            let layout = try RequirementLayoutEngine.layout(diagram, typography: typography, limits: .standard)
            XCTAssertEqual(layout.relations.count, diagram.relations.count, direction)
            Self.assertBoxesApart(layout)
            PlaneMapPictures.write(DiagramScene(layout: layout), named: "requirement-generated-\(direction)")
        }
    }

    func testAnExampleThatRunsAcrossIsPreparedWithANarrowSceneThatRunsDown() throws {
        let example = try RequirementCorpus.documentationExamples()[5]
        let prepared = try MermaidDiagramPreparation.prepare(source: example, typography: typography)
        XCTAssertEqual(prepared.kind, .requirement)
        let narrow = try XCTUnwrap(prepared.narrowScene)
        XCTAssertLessThan(narrow.size.width, prepared.scene.size.width)
        XCTAssertGreaterThan(narrow.size.height, prepared.scene.size.height)
        XCTAssertEqual(prepared.accessibility.summary, ["Requirement test_req", "Element test_entity", "test_entity satisfies test_req"])
        PlaneMapPictures.write(narrow, named: "requirement-documentation-5-narrow")
    }

    /// No two boxes overlap, and every box and relation text is on the page.
    static func assertBoxesApart(_ layout: RequirementLayout, file: StaticString = #filePath, line: UInt = #line) {
        let page = CGRect(origin: .zero, size: layout.size).insetBy(dx: -0.001, dy: -0.001)
        for box in layout.boxes { XCTAssertTrue(page.contains(box.frame), "\(box.frame) on \(layout.size)", file: file, line: line) }
        for relation in layout.relations { XCTAssertTrue(page.contains(relation.text.frame), "\(relation.text.frame) on \(layout.size)", file: file, line: line) }
        for (index, box) in layout.boxes.enumerated() {
            for other in layout.boxes[(index + 1)...] {
                XCTAssertFalse(box.frame.insetBy(dx: 0.5, dy: 0.5).intersects(other.frame.insetBy(dx: 0.5, dy: 0.5)), "\(box.frame) and \(other.frame)",
                               file: file, line: line)
            }
        }
    }
}
