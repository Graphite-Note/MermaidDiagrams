/**
 * File: SequenceCorpusTests.swift
 * -------------------------------
 * Layer: Tests
 * Description: Mermaid's sequence diagram documentation examples, as Pele's benchmark collects them, are all read and
 *              laid out inside their size, and the generated conversation with every message, note and loop.
 *
 * Authors: Félix Chevalier, Bahey Shalash
 * Version: 0.2
 * Date: 19/11/2026
 */

import XCTest
@testable import MermaidDiagrams
@testable import MermaidDiagramsBenchmark

/// Mermaid's sequence diagram documentation examples, as Pele's benchmark collects them: every one is read and laid out,
/// those with shapes, boxes, created and destroyed participants, menus and central connections included.
final class SequenceCorpusTests: XCTestCase {
    private let typography = DiagramTypography(font: DiagramFont(postScriptName: nil, size: 16))

    func testEveryDocumentationExampleIsReadWithNothingLeftOut() throws {
        let examples = try SequenceCorpus.documentationExamples()
        XCTAssertEqual(examples.count, 38)
        for (index, example) in examples.enumerated() {
            let diagram = try SequenceReading.sequence(example)
            XCTAssertFalse(diagram.participants.isEmpty, "Example \(index)")
            XCTAssertTrue(diagram.statementsNotLaidOut.isEmpty, "Example \(index)")
        }
        let kinds = try [5, 6, 7, 8, 9, 10].map { index in try SequenceReading.sequence(examples[index]).participants[0].kind }
        XCTAssertEqual(kinds, [.boundary, .control, .entity, .database, .collections, .queue])
        XCTAssertEqual(try SequenceReading.sequence(examples[13]).participants.map(\.label.lines), [["Public API"], ["Auth Service"], ["User Database"]])
        XCTAssertEqual(try SequenceReading.sequence(examples[14]).participants.map(\.label.lines), [["External Name"], ["External DB"]])
        XCTAssertEqual(try SequenceReading.sequence(examples[16]).boxes.map(\.title), [DiagramLabel("Alice & John"), DiagramLabel("Another Group")])
    }

    func testEveryExampleIsLaidOutInsideItsSizeWithItsParticipantsBoxesAndCrosses() throws {
        for (index, example) in try SequenceCorpus.documentationExamples().enumerated() {
            let diagram = try SequenceReading.sequence(example)
            let layout = try SequenceLayoutEngine.layout(diagram, typography: typography)
            let page = CGRect(origin: .zero, size: layout.size).insetBy(dx: -0.5, dy: -0.5)
            let texts = layout.participants.map(\.text) + layout.notes.map(\.text) + layout.messages.compactMap(\.text)
            let frames = layout.participants.map(\.frame) + layout.notes.map(\.frame) + layout.blocks.map(\.frame) + layout.boxes.map(\.frame) + texts.map(\.frame)
            for frame in frames { XCTAssertTrue(page.contains(frame), "Example \(index): \(frame) inside \(page)") }
            let destroyedCount = diagram.messages.filter { message in message.destroysSource || message.destroysTarget }.count
            XCTAssertEqual(layout.participants.count, 2 * diagram.participants.count - destroyedCount, "Example \(index)")
            XCTAssertEqual(layout.destructions.count, destroyedCount, "Example \(index)")
            let headers = layout.participants.prefix(diagram.participants.count)
            for (first, second) in zip(headers, headers.dropFirst()) {
                XCTAssertLessThanOrEqual(first.frame.maxX, second.frame.minX, "Example \(index): headers side by side without overlap")
            }
        }
    }

    func testTheExampleWithCreatedAndDestroyedParticipantsPlacesThemAtTheirMessages() throws {
        let diagram = try SequenceReading.sequence(try SequenceCorpus.documentationExamples()[15])
        let layout = try SequenceLayoutEngine.layout(diagram, typography: typography)
        XCTAssertEqual(diagram.participantIdentifiers, ["Alice", "Bob", "Carl", "D"])
        let carl = layout.participants[2]
        let creating = layout.messages[2]
        XCTAssertEqual(carl.frame.midY, creating.path.start.y, accuracy: 0.01, "Carl's box is centered on the message that creates it")
        XCTAssertGreaterThan(carl.frame.minY, layout.participants[0].frame.maxY)
        XCTAssertEqual(layout.lifelines[2].top, carl.frame.maxY, accuracy: 0.01)
        XCTAssertEqual(layout.destructions.count, 2)
        XCTAssertEqual(layout.lifelines[2].bottom, layout.destructions[0].y, accuracy: 0.01, "Carl's lifeline ends at its cross")
        XCTAssertEqual(Set(layout.participants.dropFirst(4).map(\.participantIndex)), [0, 3], "Only Alice and Donald are mirrored below")
    }

    func testTheExampleWithBoxesDrawsOneBehindEachGroup() throws {
        let diagram = try SequenceReading.sequence(try SequenceCorpus.documentationExamples()[16])
        let layout = try SequenceLayoutEngine.layout(diagram, typography: typography)
        XCTAssertEqual(layout.boxes.count, 2)
        XCTAssertEqual(layout.boxes[0].color, SequenceHighlightColor(red: 128.0 / 255, green: 0, blue: 128.0 / 255))
        XCTAssertNil(layout.boxes[1].color, "Another is no color: the default shade")
        for (box, participantIndices) in zip(layout.boxes, [[0, 1], [2, 3]]) {
            for index in participantIndices { XCTAssertTrue(box.frame.contains(layout.participants[index].frame)) }
            let title = try XCTUnwrap(box.title)
            XCTAssertTrue(box.frame.contains(title.frame))
            XCTAssertLessThan(title.frame.maxY, layout.participants[participantIndices[0]].frame.minY)
        }
        XCTAssertLessThanOrEqual(layout.boxes[0].frame.maxX, layout.boxes[1].frame.minX, "Boxes side by side")
    }

    func testTheGeneratedConversationIsLaidOutWithEveryMessageNoteAndLoop() throws {
        let diagram = try SequenceReading.sequence(SequenceCorpus.conversation(participantCount: 10, messageCount: 200))
        let layout = try SequenceLayoutEngine.layout(diagram, typography: typography)
        XCTAssertEqual(layout.messages.count, 200)
        XCTAssertEqual(layout.notes.count, 20)
        XCTAssertEqual(layout.blocks.count, 10)
        XCTAssertEqual(layout.messages.last?.number?.text.lines, ["200"])
    }
}
