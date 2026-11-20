/**
 * File: ClassDiagramEmptyMembersBoxTests.swift
 * --------------------------------------------
 * Layer: Tests
 * Description: `class: hideEmptyMembersBox: true` draws a class without members as its title alone, as Pele does; found
 *              by comparing the package's documentation examples with Pele's drawings.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 19/11/2026
 */

import XCTest
@testable import MermaidDiagrams

final class ClassDiagramEmptyMembersBoxTests: XCTestCase {
    /// Names 8 points a character on 24-point lines, members 7 on 21, marks 6 at 13 points (rows of 18).
    private let measurers = ClassDiagramTextMeasurers(names: UniformWidthTextMeasurer(),
                                                      members: UniformWidthTextMeasurer(characterWidth: 7, fontSize: 14, lineHeight: 21),
                                                      marks: UniformWidthTextMeasurer(characterWidth: 6, fontSize: 13, lineHeight: 20))
    private let hiding = "---\nconfig:\n  class:\n    hideEmptyMembersBox: true\n---\n"

    private func layout(_ source: String) throws -> ClassDiagramLayout {
        try ClassDiagramLayoutEngine.layout(ClassDiagramReading.classDiagram(source), measurers: measurers, font: UniformWidthLayout.font,
                                            limits: .standard)
    }

    /// Pele's class/render.ts: with `sections` false a box is its title, 8 + 24 + 8 points, and draws no divider; a class
    /// with a member keeps both compartments (6 + 21 + 6 for the method, 10 for the empty attributes).
    func testAClassWithoutMembersIsItsTitleAlone() throws {
        let classes = try layout(hiding + "classDiagram\n  class Duck\n  class Goose {\n    +honk()\n  }").classes
        XCTAssertEqual(classes[0].frame.height, 40)
        XCTAssertEqual(classes[0].dividerYs, [])
        XCTAssertEqual(classes[1].frame.height, 40 + 10 + 33)
        XCTAssertEqual(classes[1].dividerYs.count, 2)
    }

    func testWithoutTheOptionAnEmptyClassKeepsItsEmptyCompartments() throws {
        let duck = try XCTUnwrap(try layout("classDiagram\n  class Duck").classes.first)
        XCTAssertEqual(duck.frame.height, 40 + 10 + 10)
        XCTAssertEqual(duck.dividerYs.count, 2)
        XCTAssertFalse(try ClassDiagramReading.classDiagram("classDiagram\n  class Duck").hidesEmptyMemberBoxes)
    }
}
