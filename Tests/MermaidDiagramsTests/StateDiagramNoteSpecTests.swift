/**
 * File: StateDiagramNoteSpecTests.swift
 * -------------------------------------
 * Layer: Tests
 * Description: The inputs of Mermaid 12.1.0's state note specs as Pele ports them (tests/compat/state:
 *              stateNoteNode.spec.js, stateNoteEdge.spec.ts), checked on the prepared scene.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 19/11/2026
 */

import CoreGraphics
import XCTest
@testable import MermaidDiagrams

final class StateDiagramNoteSpecTests: XCTestCase {
    private func scene(_ source: String) throws -> DiagramScene {
        try MermaidDiagramPreparation.prepare(source: source, typography: DiagramTypography(font: DiagramFont(postScriptName: nil, size: 16)),
                                              narrowestColumnWidth: nil).scene
    }

    /// stateNoteNode.spec.js: a note on a composite state is a note, not a box holding states, and it is drawn.
    func testANoteOnACompositeStateIsANoteBesideIt() throws {
        let scene = try scene("\n  stateDiagram-v2\n  state Composite {\n    A --> B\n  }\n  note right of Composite : hello\n  ")
        XCTAssertEqual(scene.texts.filter { text in text.part == .note }.map(\.block.lines), [["hello"]])
        let clusterTitles = scene.texts.filter { text in text.part == .clusterLabel || text.part == .label }.flatMap(\.block.lines)
        XCTAssertTrue(clusterTitles.contains("Composite"))
        XCTAssertFalse(clusterTitles.contains("hello"), "The note is not a composite's title")
    }

    /// stateNoteEdge.spec.ts: the line from a state to its note is dashed, and the transitions are solid.
    func testTheLineToANoteIsDashedAndTransitionsAreSolid() throws {
        let scene = try scene("stateDiagram-v2\n    [*] --> Active\n    Active --> Idle\n    note right of Active\n      A note\n    end note\n  ")
        let edgeStrokes = scene.shapes.filter { shape in shape.part == .edge }.compactMap { shape -> DiagramStroke? in
            guard case .stroke(_, let stroke) = shape.painting else { return nil }
            return stroke
        }
        XCTAssertEqual(edgeStrokes.filter { stroke in !stroke.dashLengths.isEmpty }.count, 1, "One dashed line, to the note")
        XCTAssertEqual(edgeStrokes.filter { stroke in stroke.dashLengths.isEmpty }.count, 1, "The transitions, solid, in one path")
    }
}
