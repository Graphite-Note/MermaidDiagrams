/**
 * File: SequenceHalfArrowAndConnectionTests.swift
 * -----------------------------------------------
 * Layer: Tests
 * Description: Half arrows (their side, their reverses, their numbers at the tail) and central connections (their
 *              circles, where lines stop, the room they take), laid out and drawn as Pele draws them.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 19/11/2026
 */

import XCTest
@testable import MermaidDiagrams

/// Text is uniform: a message's 7 points a character, a number's 6.
final class SequenceHalfArrowAndConnectionTests: XCTestCase {
    private let accuracy: CGFloat = 0.01

    private func layout(_ body: String) throws -> SequenceLayout {
        try SequenceUniformLayout.layout("sequenceDiagram\n" + body)
    }

    private func onlyHead(_ message: SequenceLayoutMessage) throws -> SequenceLayoutArrowhead {
        XCTAssertEqual(message.heads.count, 1)
        return try XCTUnwrap(message.heads.first)
    }

    func testEveryHalfArrowAndItsDottedFormIsRead() throws {
        for (written, head, side, isBackwards) in [("-|\\", SequenceArrowhead.solidHalf, SequenceHalfHeadSide.top, false), ("-|/", .solidHalf, .bottom, false),
                                                   ("-\\\\", .stickHalf, .top, false), ("-//", .stickHalf, .bottom, false), ("/|-", .solidHalf, .top, true),
                                                   ("\\|-", .solidHalf, .bottom, true), ("//-", .stickHalf, .top, true), ("\\\\-", .stickHalf, .bottom, true)] {
            for isDotted in [false, true] {
                let arrow = isDotted ? (isBackwards ? written + "-" : "-" + written) : written
                let message = try XCTUnwrap(SequenceReading.sequence("sequenceDiagram\nA\(arrow)B: x").messages.first, arrow)
                XCTAssertEqual(message.arrow, SequenceArrow(stroke: isDotted ? .dotted : .solid, head: head, pointsBackwards: isBackwards, halfHeadSide: side), arrow)
            }
        }
    }

    func testAHalfHeadsBarbIsOnTheTopOfTheMessageSeenAlongIt() throws {
        let laidOut = try layout("A-|\\B: right\nB-|\\A: left\nA-//B: bottom\nA/|-B: back\nA-|\\A: loop")
        let (left, right) = (laidOut.lifelineXs[0], laidOut.lifelineXs[1])
        let toTheRight = try onlyHead(laidOut.messages[0])
        XCTAssertEqual(toTheRight.tip.x, right, accuracy: accuracy)
        XCTAssertEqual(toTheRight.barbDirection, CGVector(dx: 0, dy: -1), "Above a message to the right")
        XCTAssertEqual(laidOut.messages[0].path.end.x, right, accuracy: accuracy, "A half head takes none of the line")
        XCTAssertEqual(try onlyHead(laidOut.messages[1]).barbDirection, CGVector(dx: 0, dy: 1), "Below a message to the left")
        XCTAssertEqual(try onlyHead(laidOut.messages[2]).barbDirection, CGVector(dx: 0, dy: 1))
        let backwards = try onlyHead(laidOut.messages[3])
        XCTAssertEqual(backwards.tip.x, left, accuracy: accuracy, "Written backwards, the head is at the source")
        XCTAssertEqual(backwards.direction, CGVector(dx: -1, dy: 0))
        XCTAssertEqual(backwards.barbDirection, CGVector(dx: 0, dy: -1))
        XCTAssertEqual(try onlyHead(laidOut.messages[4]).barbDirection, CGVector(dx: 0, dy: 1), "The loop comes back heading left: turned over")
    }

    func testHalfHeadsAreDrawnAsHalfAnArrowheadOrOneBarb() throws {
        let solid = SequenceDrawingParts(layout: try layout("A-|\\B: x"))
        let tip = try onlyHead(try layout("A-|\\B: x").messages[0]).tip
        XCTAssertEqual(solid.filledHeads.boundingBox.minX, tip.x - 8, accuracy: accuracy)
        XCTAssertEqual(solid.filledHeads.boundingBox.minY, tip.y - 4.5, accuracy: accuracy)
        XCTAssertEqual(solid.filledHeads.boundingBox.maxY, tip.y, accuracy: accuracy)
        let stick = SequenceDrawingParts(layout: try layout("A-//B: x"))
        XCTAssertTrue(stick.filledHeads.isEmpty)
        XCTAssertEqual(stick.strokedHeads.boundingBox.height, 5, accuracy: accuracy)
    }

    func testABackwardArrowsNumberSitsAtItsTail() throws {
        let laidOut = try layout("autonumber\nA/|-B: x")
        let message = laidOut.messages[0]
        let number = try XCTUnwrap(message.number)
        XCTAssertEqual(number.frame.midX, laidOut.lifelineXs[1], accuracy: accuracy, "At the target, where the line has no head")
        XCTAssertEqual(message.path.end.x, laidOut.lifelineXs[1] - number.frame.width / 2, accuracy: accuracy)
        XCTAssertEqual(message.path.start.x, laidOut.lifelineXs[0], accuracy: accuracy)
    }

    func testCentralConnectionsSitOnTheLifelinesAndTheLineStopsAtThem() throws {
        let laidOut = try layout("A()->>()B: both\nB()-->>A: source\nA->>()A: loop")
        let (left, right) = (laidOut.lifelineXs[0], laidOut.lifelineXs[1])
        let both = laidOut.messages[0]
        XCTAssertEqual(both.centralConnections.map(\.x), [left, right])
        XCTAssertEqual(both.path.start.x, left + 4, accuracy: accuracy)
        XCTAssertEqual(try onlyHead(both).tip.x, right - 4, accuracy: accuracy)
        XCTAssertEqual(laidOut.messages[1].centralConnections.map(\.x), [right])
        XCTAssertEqual(laidOut.messages[1].path.start.x, right - 4, accuracy: accuracy)
        let loop = laidOut.messages[2]
        XCTAssertEqual(loop.centralConnections.count, 1)
        XCTAssertEqual(loop.centralConnections[0].x, left, accuracy: accuracy)
        XCTAssertEqual(loop.centralConnections[0].y, loop.path.end.y, accuracy: accuracy, "At the loop's bottom")
        XCTAssertEqual(try onlyHead(loop).tip.x, left + 4, accuracy: accuracy)
        let parts = SequenceDrawingParts(layout: laidOut)
        XCTAssertEqual(parts.centralConnections.boundingBox.height, loop.centralConnections[0].y + 4 - both.centralConnections[0].y + 4, accuracy: accuracy)
    }

    func testACentralConnectionTakesFourRadiiOfRoomAndANumberSitsPastItsCircle() throws {
        let text = String(repeating: "x", count: 20)
        let plain = try layout("A->>B: \(text)")
        let connected = try layout("A()->>B: \(text)")
        XCTAssertEqual(connected.lifelineXs[1] - connected.lifelineXs[0] - (plain.lifelineXs[1] - plain.lifelineXs[0]), 16, accuracy: accuracy)
        let numbered = try layout("autonumber\nA()->>B: x")
        let number = try XCTUnwrap(numbered.messages[0].number)
        XCTAssertEqual(number.frame.midX, numbered.lifelineXs[0] + 4 + number.frame.width / 2 + 2, accuracy: accuracy)
        XCTAssertEqual(numbered.messages[0].path.start.x, number.frame.maxX, accuracy: accuracy)
    }
}
