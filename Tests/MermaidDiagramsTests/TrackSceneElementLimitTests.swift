/**
 * File: TrackSceneElementLimitTests.swift
 * ---------------------------------------
 * Layer: Tests
 * Description: The sequence, user journey, timeline, Gantt, kanban, railroad and event modeling preparations record
 *              their scenes within the element limit of the limits they are given: a diagram whose scene goes past it is
 *              refused as too many path elements, and the same diagram under limits with room for it is drawn.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 25/11/2026
 */

import CoreGraphics
import XCTest
@testable import MermaidDiagrams

final class TrackSceneElementLimitTests: XCTestCase {
    /// Limits that let every test diagram be read and drawn: their lanes may hold millions of elements.
    private static let roomyLimits = MermaidDiagramLimits(maximumSourceBytes: 10_000_000, maximumNodeCount: 1_000_000, maximumEdgeCount: 1_000_000,
                                                          maximumLayoutPointCount: 1_000_000, maximumDrawingSideLength: 1e12)
    /// Limits whose lanes hold the fewest elements a lane ever may (`DiagramSceneWorkspace.elementLimit(for:)`, 65,536),
    /// and which still let any size be drawn, so that only the element limit refuses.
    private static let smallLimits = MermaidDiagramLimits(maximumSourceBytes: 10_000_000, maximumNodeCount: 1, maximumEdgeCount: 1,
                                                          maximumLayoutPointCount: 1, maximumDrawingSideLength: 1e12)

    /// Reads `source` within the roomy limits, then prepares it within the small ones, which must refuse it for its
    /// path elements, and within the roomy ones, which must draw it.
    private func assertRefusedPastItsElementLimit(_ source: String, file: StaticString = #filePath, line: UInt = #line) throws {
        let diagram = try MermaidDiagramReader.read(source, limits: Self.roomyLimits)
        let limit = DiagramSceneWorkspace.elementLimit(for: Self.smallLimits)
        XCTAssertEqual(limit, 1 << 16, file: file, line: line)
        let typography = DiagramSceneSamples.typography
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        XCTAssertThrowsError(try MermaidDiagramPreparation.prepare(diagram, typography: typography, limits: Self.smallLimits, narrowestColumnWidth: nil,
                                                                   now: now, timeZone: TimeZone(identifier: "UTC")!), file: file, line: line) { error in
            XCTAssertEqual(error as? MermaidDiagramPreparationFailure, .tooManyPathElements(limit: limit), file: file, line: line)
        }
        let drawn = try MermaidDiagramPreparation.prepare(diagram, typography: typography, limits: Self.roomyLimits, narrowestColumnWidth: nil,
                                                          now: now, timeZone: TimeZone(identifier: "UTC")!)
        XCTAssertNil(drawn.scene.exceededPathElementLimit, file: file, line: line)
    }

    /// 24,000 messages: their arrowheads are one lane.
    func testASequencePastItsElementLimitIsRefused() throws {
        try assertRefusedPastItsElementLimit("sequenceDiagram\n" + String(repeating: "A->>B: m\n", count: 24_000))
    }

    /// 6,000 tasks: their eyes, two circles each, are one lane.
    func testAUserJourneyPastItsElementLimitIsRefused() throws {
        try assertRefusedPastItsElementLimit("journey\nsection S\n" + String(repeating: "t: 5: A\n", count: 6_000))
    }

    /// 7,000 events of one period: their boxes are one lane.
    func testATimelinePastItsElementLimitIsRefused() throws {
        try assertRefusedPastItsElementLimit("timeline\np : " + Array(repeating: "e", count: 7_000).joined(separator: " : ") + "\n")
    }

    /// 14,000 tasks: their bars are one lane.
    func testAGanttChartPastItsElementLimitIsRefused() throws {
        try assertRefusedPastItsElementLimit("gantt\ndateFormat YYYY-MM-DD\nsection S\n" + String(repeating: "t :2024-01-01, 1d\n", count: 14_000))
    }

    /// 7,000 cards of one column, blank: with no text between them, their boxes are merged into one lane.
    func testAKanbanBoardPastItsElementLimitIsRefused() throws {
        try assertRefusedPastItsElementLimit("kanban\n  c[Column]\n" + String(repeating: "    k[\" \"]\n", count: 7_000))
    }

    /// A rule of 7,000 terminals: their boxes are one lane.
    func testARailroadDiagramPastItsElementLimitIsRefused() throws {
        try assertRefusedPastItsElementLimit("railroad-ebnf-beta\nrule = " + Array(repeating: "\"a\"", count: 7_000).joined(separator: " ") + " ;\n")
    }

    /// 999 frames, the most an event model numbers, each fed by the thirty before it: their relations are one lane.
    func testAnEventModelPastItsElementLimitIsRefused() throws {
        let frames = (1...999).map { frame in
            "tf \(frame) evt E\(frame)" + (max(1, frame - 30)..<frame).map { source in " ->> \(source)" }.joined() + "\n"
        }.joined()
        try assertRefusedPastItsElementLimit("eventmodeling\n" + frames)
    }
}
