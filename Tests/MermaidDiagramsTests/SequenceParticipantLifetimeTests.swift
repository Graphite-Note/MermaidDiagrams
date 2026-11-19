/**
 * File: SequenceParticipantLifetimeTests.swift
 * --------------------------------------------
 * Layer: Tests
 * Description: Participants created by `create` and destroyed by `destroy`: Mermaid's checks of the message after
 *              them, and where Pele draws the created participant, the cross and the lifeline between them.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 19/11/2026
 */

import XCTest
@testable import MermaidDiagrams

/// Text is uniform: a participant's 8 points a character (24 high, boxes 44 high), a message's 7 (21 high).
final class SequenceParticipantLifetimeTests: XCTestCase {
    private let accuracy: CGFloat = 0.01

    private func layout(_ body: String) throws -> SequenceLayout {
        try SequenceUniformLayout.layout("sequenceDiagram\n" + body)
    }

    private func readError(_ body: String) -> MermaidDiagramReadError? {
        SequenceReading.readError("sequenceDiagram\n" + body)
    }

    // MARK: Reading

    func testTheMessageAfterCreateMustBeToTheParticipantCreated() {
        XCTAssertEqual(readError("A->>B: x\ncreate participant A\nB->>A: y"),
                       .invalidSyntax(line: 3, problem: .sequence(.createdParticipantAlreadyNamed(identifier: "A"))))
        XCTAssertEqual(readError("create participant C\nA->>B: x"),
                       .invalidSyntax(line: 3, problem: .sequence(.createdParticipantWithoutCreatingMessage(identifier: "C"))))
        XCTAssertNil(readError("create participant C\nNote over A: first\nA->>C: x"), "Only messages are checked")
        XCTAssertNil(readError("A->>B: x\ncreate participant C"), "No message after it: nothing is checked")
    }

    func testTheMessageAfterDestroyMustBeFromOrToTheParticipantDestroyed() {
        XCTAssertEqual(readError("A->>B: x\ndestroy B\nA->>C: y"),
                       .invalidSyntax(line: 4, problem: .sequence(.destroyedParticipantWithoutDestroyingMessage(identifier: "B"))))
        XCTAssertNil(readError("A->>B: x\ndestroy B\nB->>A: y"))
        XCTAssertNil(readError("A->>B: x\ndestroy A\nB->>A: y"))
    }

    func testOnlyTheLastDestroyOfAParticipantEndsItsLifeline() throws {
        let diagram = try SequenceReading.sequence("sequenceDiagram\nA->>B: x\ndestroy B\nA->>B: y\ndestroy B\nB->>A: z")
        XCTAssertEqual(diagram.messages.map(\.destroysTarget), [false, false, false])
        XCTAssertEqual(diagram.messages.map(\.destroysSource), [false, false, true])
    }

    func testCreateWithDestroyCreatesAPlainParticipantAndCreateTakesAttributes() throws {
        let diagram = try SequenceReading.sequence("sequenceDiagram\ncreate destroy C\nA->>C: x\ncreate actor D@{ \"type\": \"queue\" } as Dee\nC->>D: y")
        XCTAssertEqual(diagram.participants.map(\.kind), [.participant, .participant, .queue])
        XCTAssertEqual(diagram.participants[2].label, DiagramLabel("Dee"))
        XCTAssertEqual(diagram.messages.map(\.createsTarget), [true, true])
    }

    // MARK: Layout

    func testACreatedParticipantStandsOnTheMessageThatCreatesIt() throws {
        let laidOut = try layout("A->>B: hi\ncreate participant C\nB->>C: make")
        let creating = laidOut.messages[1]
        let lineY = creating.path.start.y
        let created = laidOut.headers[2]
        XCTAssertEqual(created.frame.midY, lineY, accuracy: accuracy)
        XCTAssertEqual(lineY - laidOut.messages[0].path.start.y, 14 + 21 + 2, accuracy: accuracy, "The text's height wins over half the box")
        XCTAssertEqual(laidOut.lifelines[2].top, created.frame.maxY, accuracy: accuracy)
        XCTAssertEqual(creating.heads.first?.tip.x ?? 0, created.frame.minX - 1, accuracy: accuracy, "The arrow stops a point short of the box")
        XCTAssertEqual(laidOut.headers[0].frame.minY, laidOut.headers[1].frame.minY, accuracy: accuracy)
        XCTAssertEqual(laidOut.lifelines[0].bottom - (lineY + 22 - 6), 20, accuracy: accuracy, "The next row starts under the created box")
    }

    func testACreatedFigureIsReachedEighteenPointsFromItsCenterAndAnyCreatedOneLeavesRoom() throws {
        let laidOut = try layout("participant A\ncreate actor D\nA->>D: hi")
        XCTAssertEqual(laidOut.messages[0].heads.first?.tip.x ?? 0, laidOut.lifelineXs[1] - 18, accuracy: accuracy)
        let text = "a message long enough to need its own room"
        let wide = try layout("participant A\ncreate participant C as A participant with a long name\nA->>C: \(text)")
        let widthOfC = wide.headers[1].frame.width
        XCTAssertEqual(wide.lifelineXs[1] - wide.lifelineXs[0], CGFloat(text.count) * 7 + 24 + 10 + widthOfC / 2, accuracy: accuracy,
                       "The text, its padding, an activation and half the created box")
    }

    func testADestroyedParticipantEndsInACrossAndIsNotMirrored() throws {
        let laidOut = try layout("A->>B: hi\ndestroy B\nA-xB: bye\nA->>A: after")
        let lineY = laidOut.messages[1].path.start.y
        XCTAssertEqual(laidOut.destructions.count, 1)
        XCTAssertEqual(laidOut.destructions[0].x, laidOut.lifelineXs[1], accuracy: accuracy)
        XCTAssertEqual(laidOut.destructions[0].y, lineY + 16, accuracy: accuracy)
        XCTAssertEqual(laidOut.lifelines[1].bottom, lineY + 16, accuracy: accuracy)
        XCTAssertEqual(laidOut.footers.map(\.participantIndex), [0])
        XCTAssertGreaterThanOrEqual(laidOut.messages[2].path.start.y - 14, lineY + 16 + 6 - accuracy, "The next row starts under the cross")
        let crossBounds = SequenceDrawingParts(layout: laidOut).destructions.boundingBox
        XCTAssertEqual(crossBounds.midX, laidOut.lifelineXs[1], accuracy: accuracy)
        XCTAssertEqual(crossBounds.midY, lineY + 16, accuracy: accuracy)
        XCTAssertEqual(crossBounds.width, 12, accuracy: accuracy)
    }

    func testAParticipantCreatedAndDestroyedHasALifelineBetweenItsBoxAndItsCross() throws {
        let laidOut = try layout("A->>B: x\ncreate participant C\nB->>C: hi\ndestroy C\nC->>B: bye")
        XCTAssertEqual(laidOut.lifelines[2].top, laidOut.headers[2].frame.maxY, accuracy: accuracy)
        XCTAssertEqual(laidOut.lifelines[2].bottom, laidOut.destructions[0].y, accuracy: accuracy)
        XCTAssertEqual(laidOut.participants.count, 5)
    }
}
