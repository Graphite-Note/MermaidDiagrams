/**
 * File: StateDiagramCompositeSurroundingsTests.swift
 * --------------------------------------------------
 * Layer: Tests
 * Description: Transitions between a composite state and the states inside it, notes beside a composite and loops on
 *              one, laid out as Pele's state renderer lays them out.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 19/11/2026
 */

import XCTest
@testable import MermaidDiagrams

final class StateDiagramCompositeSurroundingsTests: XCTestCase {
    private let accuracy: CGFloat = 0.01

    private func layout(_ source: String) throws -> StateDiagramLayout {
        try StateDiagramUniformLayout.layout(source)
    }

    private func frame(of name: String, in layout: StateDiagramLayout) throws -> CGRect {
        try XCTUnwrap(layout.states.first { state in state.name?.lines == [name] }, name).frame
    }

    func testATransitionFromACompositeToAStateInsideItStartsBelowItsTitle() throws {
        let laidOut = try layout("stateDiagram-v2\nstate Moving {\n  slow --> fast\n}\nMoving --> slow")
        let box = try XCTUnwrap(laidOut.composites.first)
        let title = try XCTUnwrap(box.title)
        let transition = laidOut.transitions[1]
        XCTAssertEqual(transition.path.start.y, box.frame.minY + title.size.height + 12, accuracy: accuracy)
        XCTAssertTrue(box.frame.contains(transition.path.start))
        let slow = try frame(of: "slow", in: laidOut)
        XCTAssertEqual(transition.arrow.tip.y, slow.minY, accuracy: accuracy)
        XCTAssertLessThan(transition.path.start.y, slow.minY)
    }

    func testATransitionFromAStateInsideToItsCompositeEndsOnTheCompositesFarSide() throws {
        let laidOut = try layout("stateDiagram-v2\nstate Moving {\n  slow --> fast\n}\nfast --> Moving")
        let box = try XCTUnwrap(laidOut.composites.first).frame
        let arrow = laidOut.transitions[1].arrow
        XCTAssertEqual(arrow.tip.y, box.maxY, accuracy: accuracy)
        XCTAssertGreaterThan(arrow.tip.y, try frame(of: "fast", in: laidOut).maxY)
    }

    func testANoteBesideACompositeIsLaidOutBesideItsBox() throws {
        let laidOut = try layout("stateDiagram-v2\nstate Moving {\n  slow --> fast\n}\nnote right of Moving : busy\n[*] --> Moving")
        let box = try XCTUnwrap(laidOut.composites.first).frame
        let note = try XCTUnwrap(laidOut.notes.first)
        XCTAssertGreaterThan(note.frame.minX, box.maxX)
        XCTAssertGreaterThan(note.frame.maxY, box.minY)
        XCTAssertLessThan(note.frame.minY, box.maxY)
        XCTAssertEqual(note.connector.allPoints.map(\.x).min() ?? 0, box.maxX, accuracy: 0.5)
        let left = try layout("stateDiagram-v2\nstate Moving {\n  slow --> fast\n}\nnote left of Moving : idle")
        XCTAssertLessThan(try XCTUnwrap(left.notes.first).frame.maxX, try XCTUnwrap(left.composites.first).frame.minX)
    }

    func testALoopOnACompositeHangsOffItsBoxWithRoomBesideIt() throws {
        let laidOut = try layout("stateDiagram-v2\nstate Moving {\n  slow --> fast\n}\n[*] --> Moving\nMoving --> Moving : again")
        let box = try XCTUnwrap(laidOut.composites.first).frame
        let loop = laidOut.transitions[2]
        XCTAssertEqual(loop.path.start.x, box.maxX, accuracy: accuracy)
        XCTAssertGreaterThan(loop.path.allPoints.map(\.x).max() ?? 0, box.maxX)
        XCTAssertLessThanOrEqual(loop.path.allPoints.map(\.x).max() ?? 0, laidOut.size.width)
        let text = try XCTUnwrap(loop.text)
        XCTAssertGreaterThan(text.frame.minX, box.maxX)
        XCTAssertLessThanOrEqual(text.frame.maxX, laidOut.size.width)
    }

    func testMermaidsCompositeDocumentationExamplesStillDraw() throws {
        _ = try layout("stateDiagram-v2\n[*] --> First\nstate First {\n  [*] --> second\n  second --> [*]\n}\nFirst --> First : retry\nnote right of First : a note")
    }
}
