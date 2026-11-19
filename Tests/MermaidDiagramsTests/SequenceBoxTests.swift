/**
 * File: SequenceBoxTests.swift
 * ----------------------------
 * Layer: Tests
 * Description: A sequence `box … end`: its line split into a color and a title as Pele splits it, its participants,
 *              its place on the page, and the text colors Pele picks on it and on a colored `rect`.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 19/11/2026
 */

import XCTest
@testable import MermaidDiagrams

/// Text is uniform: a participant's 8 points a character (24 high), a message's or a box title's 7 (21 high).
final class SequenceBoxTests: XCTestCase {
    private let accuracy: CGFloat = 0.01

    private func layout(_ body: String) throws -> SequenceLayout {
        try SequenceUniformLayout.layout("sequenceDiagram\n" + body)
    }

    private static func named(_ hexadecimal: UInt32) -> SequenceHighlightColor {
        SequenceHighlightColor(red: Double(hexadecimal >> 16 & 0xFF) / 255, green: Double(hexadecimal >> 8 & 0xFF) / 255, blue: Double(hexadecimal & 0xFF) / 255)
    }

    // MARK: Reading

    func testTheLineSplitsIntoAColorAndATitleAsPeleSplitsIt() {
        let cases: [(String, SequenceHighlightColor?, DiagramLabel?, Bool)] = [
            ("green Group 1", Self.named(0x008000), DiagramLabel("Group 1"), false),
            ("Group 1", nil, DiagramLabel("Group 1"), false),
            ("aqua", Self.named(0x00FFFF), nil, false),
            ("Navy Back end", Self.named(0x000080), DiagramLabel("Back end"), false),
            ("", nil, nil, false),
            ("rgb(255, 0, 0) Red", SequenceHighlightColor(red: 1, green: 0, blue: 0), DiagramLabel("Red"), false),
            ("hsl(120, 100%, 50%) Lime", SequenceHighlightColor(red: 0, green: 1, blue: 0), DiagramLabel("Lime"), false),
            ("rgb(1,2,3) Title (x)", nil, DiagramLabel("rgb(1,2,3) Title (x)"), false),
            ("rgb (1,2,3) Spaced", nil, DiagramLabel("rgb (1,2,3) Spaced"), false),
            ("rgb(1, 2) Short", nil, DiagramLabel("rgb(1, 2) Short"), false),
            ("transparent Clear", nil, DiagramLabel("Clear"), false),
            ("inherit Kept", nil, DiagramLabel("Kept"), false),
            ("wrap: green Group", nil, DiagramLabel("green Group"), true),
            ("green wrap: Group", Self.named(0x008000), DiagramLabel("Group"), true),
        ]
        for (line, color, title, wraps) in cases {
            XCTAssertEqual(SequenceBoxSyntax.box(from: line), SequenceBox(title: title, wrapsTitle: wraps, color: color), line)
        }
    }

    func testAColorFunctionIsCheckedAsPeleChecksIt() {
        for valid in ["rgb(1,2,3)", "rgba(1,2,3,0.5)", "rgb(10% 20% 30%)", "rgb(1 2 3 / 50%)", "hsl(120deg 50% 50%)", "hsla(1turn, 50%, 50%, 1)", "rgb(none 2 3)"] {
            XCTAssertTrue(SequenceBoxSyntax.isCSSColor(valid), valid)
        }
        for invalid in ["rgb(1,2%,3)", "rgb(none,2,3)", "hsl(120, 50, 50%)", "rgb(1 2 3 / 4 / 5)", "RGB(1,2,3)", "rgb(1,2,3", "calc(1)", "rgb(1e,2,3)"] {
            XCTAssertFalse(SequenceBoxSyntax.isCSSColor(invalid), invalid)
        }
    }

    func testABoxGroupsTheParticipantsDeclaredInItAndOneParticipantIsInOneBox() throws {
        let diagram = try SequenceReading.sequence("sequenceDiagram\nA->>B: hi\nbox Front\nparticipant A\nend\nbox Back\nparticipant C\nend")
        XCTAssertEqual(diagram.participants.map(\.boxIndex), [0, nil, 1], "A, named before, joins the box it is declared in")
        XCTAssertEqual(SequenceReading.readError("sequenceDiagram\nbox One\nparticipant A\nend\nbox Two\nparticipant A\nend"),
                       .invalidSyntax(line: 6, problem: .sequence(.participantInTwoBoxes(identifier: "A"))))
        XCTAssertNoThrow(try SequenceReading.sequence("sequenceDiagram\nbox One\nparticipant A\nend\nparticipant A as Alice"))
        XCTAssertEqual(SequenceReading.readError("sequenceDiagram\nbox One\nbox Two\nend\nend"), .invalidSyntax(line: 3, problem: .unexpectedText("box Two")))
    }

    func testTheNumberOfBoxesIsBoundedBeforeOneIsMade() {
        let limits = MermaidDiagramLimits(maximumSourceBytes: 50_000, maximumNodeCount: 2, maximumEdgeCount: 10, maximumLayoutPointCount: 100)
        XCTAssertEqual(SequenceReading.readError("sequenceDiagram\nbox A\nend\nbox B\nend\nbox C\nend", limits: limits), .tooManyParticipants(limit: 2))
    }

    // MARK: Layout

    func testABoxPadsItsParticipantsAndItsNeighboursAreAPaddingFurther() throws {
        let laidOut = try layout("box Group\nparticipant A\nparticipant B\nend\nparticipant C")
        XCTAssertEqual(laidOut.lifelineXs[1] - laidOut.lifelineXs[0], 104, accuracy: accuracy, "In one box, the usual gap")
        XCTAssertEqual(laidOut.lifelineXs[2] - laidOut.lifelineXs[1], 114, accuracy: accuracy, "Out of the box, a padding more")
        let box = try XCTUnwrap(laidOut.boxes.first)
        XCTAssertEqual(box.frame.minX, laidOut.headers[0].frame.minX - 10, accuracy: accuracy)
        XCTAssertEqual(box.frame.maxX, laidOut.headers[1].frame.maxX + 10, accuracy: accuracy)
        XCTAssertEqual(box.frame.minY, 8, accuracy: accuracy, "From the page's top")
        XCTAssertEqual(laidOut.headers[0].frame.minY - box.frame.minY, 10 + 21 + 4, accuracy: accuracy, "A padding, the title and its gap")
        XCTAssertEqual(box.frame.maxY, laidOut.footers[0].frame.maxY + 10, accuracy: accuracy)
        XCTAssertEqual(laidOut.size.height, box.frame.maxY + 8, accuracy: 1, "The page ends a padding under the boxes")
        let title = try XCTUnwrap(box.title)
        XCTAssertEqual(title.center, CGPoint(x: box.frame.midX, y: box.frame.minY + 5 + 2 + 10.5))
    }

    func testABoxWiderTitleGrowsTheBoxAndPushesItsNeighbours() throws {
        let laidOut = try layout("participant Z\nbox A box with a long title\nparticipant A\nend\nparticipant B")
        let box = try XCTUnwrap(laidOut.boxes.first)
        let titleWidth = CGFloat("A box with a long title".count) * 7
        let growth = (titleWidth - 64) / 2
        XCTAssertEqual(box.frame.width, titleWidth + 20, accuracy: accuracy)
        XCTAssertEqual(laidOut.lifelineXs[1] - laidOut.lifelineXs[0], 104 + 10 + growth, accuracy: accuracy)
        XCTAssertEqual(laidOut.lifelineXs[2] - laidOut.lifelineXs[1], 104 + 10 + growth, accuracy: accuracy)
    }

    func testABoxWhoseParticipantsAreApartIsDrawnOncePerRun() throws {
        let laidOut = try layout("A->>B: x\nA->>C: y\nbox Split\nparticipant A\nparticipant C\nend")
        XCTAssertEqual(laidOut.boxes.count, 2, "A and C are not neighbours: two runs, each with the title")
        XCTAssertEqual(laidOut.boxes.compactMap(\.title).count, 2)
    }

    func testWithoutBoxesTheLayoutIsAsBefore() throws {
        let laidOut = try layout("participant A\nparticipant B")
        XCTAssertTrue(laidOut.boxes.isEmpty)
        XCTAssertEqual(laidOut.size, CGSize(width: 184, height: 8 + 44 + 6 + 20 + 44 + 8))
    }

    // MARK: Colors on boxes and highlights

    func testATitleAFiguresTextAndMessagesOnAColoredBoxTakeTheContrastingColor() throws {
        let parts = SequenceDrawingParts(layout: try layout("box navy Dark\nactor B\nparticipant C\nend\nbox aqua Light\nparticipant D\nend\nbox Plain\nparticipant E\nend\nB->>C: inside"))
        XCTAssertEqual(parts.boxes.map(\.titleInk), [SequenceTextInk.onDark, SequenceTextInk.onLight, nil])
        XCTAssertEqual(parts.participantTextInks.prefix(4), [SequenceTextInk.onDark, nil, nil, nil], "A figure's text sits on the box; a box holds its own")
        XCTAssertEqual(parts.inkedMessageLines.map(\.ink), [SequenceTextInk.onDark])
        XCTAssertTrue(parts.solidMessageLines.isEmpty)
        XCTAssertEqual(parts.messageTextInks, [SequenceTextInk.onDark])
    }

    func testAMessageAcrossABoxEdgeOrOnAFaintHighlightKeepsItsColors() throws {
        let across = SequenceDrawingParts(layout: try layout("box navy Dark\nparticipant A\nend\nparticipant B\nA->>B: out"))
        XCTAssertTrue(across.inkedMessageLines.isEmpty)
        XCTAssertEqual(across.messageTextInks, [nil])
        let faint = SequenceDrawingParts(layout: try layout("rect rgba(0, 0, 0, 0.1)\nA->>B: faint\nend"))
        XCTAssertTrue(faint.inkedMessageLines.isEmpty)
        let dark = SequenceDrawingParts(layout: try layout("rect rgb(0, 0, 0)\nloop Each\nA->>B: dark\nend\nend"))
        XCTAssertEqual(dark.inkedMessageLines.map(\.ink), [SequenceTextInk.onDark])
        XCTAssertEqual(dark.blockTextInks, [SequenceTextInk.onDark], "The loop's title sits on the black highlight")
        let innermost = SequenceDrawingParts(layout: try layout("box navy Dark\nparticipant A\nparticipant B\nend\nrect\nA->>B: plain\nend"))
        XCTAssertTrue(innermost.inkedMessageLines.isEmpty, "The innermost rect, without a color, wins over the box")
    }
}
