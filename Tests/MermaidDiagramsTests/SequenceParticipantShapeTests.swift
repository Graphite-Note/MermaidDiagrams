/**
 * File: SequenceParticipantShapeTests.swift
 * -----------------------------------------
 * Layer: Tests
 * Description: The sizes, text positions and paths of Pele's participant shapes: boundary, control, entity, database,
 *              collections and queue.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 19/11/2026
 */

import XCTest
@testable import MermaidDiagrams

/// Text is uniform: a participant's 8 points a character, 24 high; a box is 44 high.
final class SequenceParticipantShapeTests: XCTestCase {
    private let accuracy: CGFloat = 0.01

    private func layout(_ type: String) throws -> SequenceLayout {
        try SequenceUniformLayout.layout("sequenceDiagram\nparticipant A@{ \"type\": \"\(type)\" }")
    }

    func testFiguresStandAboveTheirTextAndShapesHoldIt() throws {
        for figure in ["boundary", "control", "entity", "database"] {
            let header = try layout(figure).headers[0]
            XCTAssertEqual(header.frame.size, CGSize(width: 40, height: 34 + 4 + 24), figure)
            XCTAssertEqual(header.text.center.y, header.frame.minY + 34 + 4 + 12, accuracy: accuracy, figure)
        }
        let collections = try layout("collections").headers[0]
        XCTAssertEqual(collections.frame.size, CGSize(width: 64 + 5, height: 44 + 5))
        XCTAssertEqual(collections.text.center.x, collections.frame.minX + 32, accuracy: accuracy, "Centered on the front card")
        XCTAssertEqual(collections.text.center.y, collections.frame.minY + 5 + 22, accuracy: accuracy)
        let queue = try layout("queue").headers[0]
        XCTAssertEqual(queue.frame.size, CGSize(width: 64 + 12, height: 44))
        XCTAssertEqual(queue.text.center.x, queue.frame.midX - 3, accuracy: accuracy)
    }

    func testEachShapeIsDrawnInsideItsFrameWithPelesGeometry() throws {
        let expected: [(String, CGRect)] = [
            ("boundary", CGRect(x: -19, y: 6, width: 33, height: 22)), ("control", CGRect(x: -11, y: 5, width: 22, height: 27)),
            ("entity", CGRect(x: -11, y: 4, width: 22, height: 26)), ("database", CGRect(x: -14, y: 2, width: 28, height: 30)),
        ]
        for (figure, bounds) in expected {
            let laidOut = try layout(figure)
            let header = laidOut.headers[0]
            let parts = SequenceDrawingParts(layout: SequenceLayout(size: laidOut.size, font: laidOut.font, boxes: [], participants: [header], lifelines: [],
                                                                    highlights: [], activations: [], blocks: [], messages: [], destructions: [], notes: [],
                                                                    title: nil))
            let drawn = parts.participantShapes.boundingBoxOfPath.union(parts.participantFigureLines.boundingBoxOfPath)
            let relative = drawn.offsetBy(dx: -header.frame.midX, dy: -header.frame.minY)
            XCTAssertEqual(relative.minX, bounds.minX, accuracy: 0.05, figure)
            XCTAssertEqual(relative.minY, bounds.minY, accuracy: 0.05, figure)
            XCTAssertEqual(relative.width, bounds.width, accuracy: 0.05, figure)
            XCTAssertEqual(relative.height, bounds.height, accuracy: 0.05, figure)
        }
    }

    func testCollectionsDrawTheirFrontCardOverTheBackOneAndAQueueItsEnds() throws {
        let collections = try layout("collections")
        let parts = SequenceDrawingParts(layout: collections)
        let frame = collections.headers[0].frame
        let front = parts.participantFrontShapes.boundingBox
        XCTAssertEqual(front.minX, frame.minX, accuracy: accuracy)
        XCTAssertEqual(front.width, frame.width - 5, accuracy: accuracy, "The header's card and the footer's")
        XCTAssertEqual(front.minY, frame.minY + 5, accuracy: accuracy)
        let queue = try layout("queue")
        let queueFrame = queue.headers[0].frame
        let queueParts = SequenceDrawingParts(layout: queue)
        XCTAssertEqual(queueParts.participantShapes.boundingBoxOfPath.insetBy(dx: -0.01, dy: -0.01).contains(queueFrame), true)
        XCTAssertEqual(queueParts.participantFigureLines.boundingBoxOfPath.minX, queueFrame.maxX - 12, accuracy: 0.05, "The inner edge of the right end")
    }

    func testTheSceneDrawsEveryShapeExampleOfTheDocumentation() throws {
        for kind in ["boundary", "control", "entity", "database", "collections", "queue"] {
            let scene = DiagramScene(layout: try layout(kind))
            XCTAssertGreaterThan(scene.items.count, 3, kind)
        }
    }
}
