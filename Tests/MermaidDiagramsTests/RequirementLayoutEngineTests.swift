/**
 * File: RequirementLayoutEngineTests.swift
 * ----------------------------------------
 * Layer: Tests
 * Description: The requirement diagram's layout in Pele's numbers, worked out by hand from `requirement/render.ts` with
 *              text of uniform widths: boxes, ranks, relations and their marks, ends spread along a side, loops.
 *
 * Authors: Bahey Shalash
 * Version: 0.2
 * Date: 19/11/2026
 */

import XCTest
@testable import MermaidDiagrams

final class RequirementLayoutEngineTests: XCTestCase {
    /// Names 8 points a character on lines of 24; everything else 7 points a character on lines of 21, the size of 14.
    private static func layout(_ source: String) throws -> RequirementLayout {
        let body = UniformWidthTextMeasurer(characterWidth: 7, fontSize: 14, lineHeight: 21)
        return try RequirementLayoutEngine.layout(try RequirementParserTests.read(source),
                                                  measurers: RequirementTextMeasurers(names: UniformWidthTextMeasurer(), body: body),
                                                  titleText: UniformWidthTextMeasurer(), font: DiagramFont(postScriptName: nil, size: 16), limits: .standard)
    }

    /// The documentation's first example: the element above, the relation's text in a rank of its own, the requirement below.
    func testBoxesRanksAndARelationInPelesNumbers() throws {
        let layout = try Self.layout("""
            requirementDiagram
            requirement test_req {
            id: 1
            text: the test text.
            risk: high
            verifymethod: test
            }
            element test_entity {
            type: simulation
            }
            test_entity - satisfies -> test_req
            """)
        XCTAssertEqual(layout.size, CGSize(width: 238, height: 378))
        let requirement = layout.boxes[0]
        let element = layout.boxes[1]
        // 222 wide: 14, the widest field name (Verification, 84), 12, the widest value (98), 14. 175 high: a head of 10, the
        // stereotype's 21, the name's 24 and 10, then four rows of 21 and 2 between 10 and 10.
        XCTAssertEqual(requirement.frame, CGRect(x: 8, y: 195, width: 222, height: 175))
        XCTAssertEqual(element.frame, CGRect(x: 50, y: 8, width: 138, height: 106))
        XCTAssertEqual(requirement.dividerY, 260)
        XCTAssertEqual(requirement.stereotype.center, CGPoint(x: 119, y: 215.5))
        XCTAssertEqual(requirement.name.center, CGPoint(x: 119, y: 238))
        XCTAssertEqual(requirement.fieldNames.map(\.center), [CGPoint(x: 29, y: 280.5), CGPoint(x: 36, y: 303.5), CGPoint(x: 36, y: 326.5), CGPoint(x: 64, y: 349.5)])
        XCTAssertEqual(requirement.fieldValues.first?.center, CGPoint(x: 121.5, y: 280.5), "values start after the widest name and 12 points")
        let relation = try XCTUnwrap(layout.relations.first)
        XCTAssertEqual(relation.path.start, CGPoint(x: 119, y: 114))
        XCTAssertEqual(relation.mark, .arrow(tip: CGPoint(x: 119, y: 195), direction: CGVector(dx: 0, dy: 1)))
        XCTAssertEqual(relation.text.center, CGPoint(x: 119, y: 154.5))
        XCTAssertEqual(relation.text.lines, ["«satisfies»"])
    }

    func testAContainmentStartsPastItsCircleAndALoopWidensItsBoxesPlace() throws {
        let layout = try Self.layout("requirementDiagram\nrequirement a {\n}\na - contains -> a\n")
        // 120 wide, and on each side a loop's 26 and its text's 70 and 12.
        XCTAssertEqual(layout.size, CGSize(width: 352, height: 81))
        let box = layout.boxes[0].frame
        XCTAssertEqual(box, CGRect(x: 116, y: 8, width: 120, height: 65))
        XCTAssertNil(layout.boxes[0].dividerY)
        let loop = try XCTUnwrap(layout.relations.first)
        XCTAssertEqual(loop.mark, .containment(point: CGPoint(x: 236, y: 28.5), towardBox: CGVector(dx: -1, dy: 0)))
        XCTAssertEqual(loop.path.start, CGPoint(x: 248, y: 28.5), "the line starts past the circle, two radii out")
        XCTAssertEqual(loop.text.center, CGPoint(x: 307, y: 40.5))
    }

    func testEndsThatShareASideSpreadAlongItInTheOrderTheyHead() throws {
        let layout = try Self.layout("""
            requirementDiagram
            element e {
            }
            requirement r1 {
            }
            requirement r2 {
            }
            requirement r3 {
            }
            e - satisfies -> r1
            e - satisfies -> r2
            e - satisfies -> r3
            """)
        let element = layout.boxes[3].frame
        let starts = layout.relations.map(\.path.start)
        XCTAssertTrue(starts.allSatisfy { start in start.y == element.maxY })
        let offsets = starts.map { start in start.x - element.midX }.sorted()
        XCTAssertEqual(offsets, [-28, 0, 28], "28 points apart, as the side less 14 at each end has room for")
        let tips = layout.relations.map { relation -> CGFloat in
            guard case .arrow(let tip, _) = relation.mark else { return 0 }
            return tip.x
        }
        XCTAssertEqual(zip(starts, tips).sorted { $0.0.x < $1.0.x }.map(\.1), tips.sorted(), "the ends keep the order of where they head")
    }

    func testARelationToANameDeclaredAsBothGoesToTheRequirementAndOneToNothingIsNotDrawn() throws {
        let layout = try Self.layout("requirementDiagram\nrequirement a {\n}\nelement a {\n}\nelement b {\n}\nb - traces -> a\nb - traces -> nowhere\n")
        XCTAssertEqual(layout.boxes.count, 3)
        XCTAssertEqual(layout.relations.count, 1)
        guard case .arrow(let tip, _) = layout.relations[0].mark else { return XCTFail("an arrow") }
        XCTAssertEqual(tip.y, layout.boxes[0].frame.minY, accuracy: 0.001)
    }

    /// Pele's `inkFill`: on a fill a style sets, every text of the box takes the ink that contrasts more with it, white on a
    /// dark fill and #1f1f1f on a light one, unless the style sets a text color.
    func testTextOnAStyledFillTakesTheInkThatContrastsMore() throws {
        let layout = try Self.layout("""
            requirementDiagram
            requirement dark {
            id: 1
            }
            element light {
            type: t
            }
            element colored {
            }
            style dark fill:#000
            style light fill:#ffeeaa
            style colored fill:#000,color:#f00
            """)
        let scene = DiagramScene(layout: layout)
        func paints(ofBoxAt frame: CGRect) -> Set<DiagramPaint> {
            Set(scene.texts.filter { text in frame.contains(text.block.center) && [.label, .stereotype, .field, .value].contains(text.part) }.map(\.paint))
        }
        XCTAssertEqual(paints(ofBoxAt: layout.boxes[0].frame), [.color(DiagramColor(red: 1, green: 1, blue: 1))])
        XCTAssertEqual(paints(ofBoxAt: layout.boxes[1].frame), [.color(DiagramColor(red: 31.0 / 255, green: 31.0 / 255, blue: 31.0 / 255))])
        XCTAssertEqual(paints(ofBoxAt: layout.boxes[2].frame), [.color(DiagramColor(red: 1, green: 0, blue: 0))])
    }

    func testADiagramThatRunsAcrossTurnsToRunDownFromTheTop() throws {
        let diagram = try RequirementParserTests.read("requirementDiagram\ndirection RL\nelement a {\n}\nelement b {\n}\na - copies -> b\n")
        XCTAssertEqual(diagram.turnedToRunDown?.direction, .topToBottom)
        XCTAssertNil(try RequirementParserTests.read("requirementDiagram\ndirection BT\n").turnedToRunDown)
    }
}
