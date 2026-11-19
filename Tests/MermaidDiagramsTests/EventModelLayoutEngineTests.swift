/**
 * File: EventModelLayoutEngineTests.swift
 * ---------------------------------------
 * Layer: Tests
 * Description: Event models are laid out in Pele's measurements: across, boxes along their lanes staggered under the
 *              frame before, relations straight or in an S; down a narrow column, cards with their lane names and
 *              relations on rails; the cards of notes and specifications; and their scenes in Pele's colors.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 19/11/2026
 */

import XCTest
@testable import MermaidDiagrams
@testable import MermaidDiagramsBenchmark

final class EventModelLayoutEngineTests: XCTestCase {
    private let typography = DiagramTypography(font: DiagramFont(postScriptName: nil, size: 16))

    private func layout(_ source: String) throws -> EventModelLayout {
        EventModelLayoutEngine.layout(try EventModelReading.diagram(source), typography: typography)
    }

    func testBoxesTakePelesMeasurements() throws {
        let laidOut = try layout("eventmodeling\ntf 01 ui A\ntf 02 cmd LongerCommandName\ntf 03 evt B")
        let first = laidOut.frames[0].frame
        // A name of 14 points bold, 21 points a line, 10 points above and below; at least 96 points wide.
        XCTAssertEqual(first.size, CGSize(width: 96, height: 41))
        // Each band 12 points around its tallest box, 8 points apart, the first 8 points from the top.
        XCTAssertEqual(laidOut.laneBands.map(\.height), [65, 65, 65])
        XCTAssertEqual(laidOut.laneBands.map(\.minY), [8, 81, 154])
        XCTAssertEqual(laidOut.laneBands[0].minX, 8)
        let widestLaneName = laidOut.laneNames.map(\.size.width).max() ?? 0
        XCTAssertEqual(first.minX, 8 + widestLaneName + 24, accuracy: 0.001, "The boxes start after the lane names' column")
        XCTAssertEqual(laidOut.frames.map(\.seriesIndex), [nil, 0, 1])
        XCTAssertEqual(laidOut.size.height, (154 + 65 + 8).rounded(.up))
    }

    func testAFrameInAnotherLaneStartsUnderTheEndOfTheOneBeforeAndOneInTheSameLaneFollowsIt() throws {
        let laidOut = try layout("eventmodeling\ntf 01 ui First\ntf 02 cmd SecondWithALongerName\ntf 03 cmd Third\ntf 04 evt Fourth")
        let frames = laidOut.frames.map(\.frame)
        // Under the end of the frame before: halfway along it at least, 80 points back from its end at most.
        XCTAssertEqual(frames[1].minX, frames[0].minX + max(frames[0].width / 2, frames[0].width - 80), accuracy: 0.001)
        XCTAssertEqual(frames[2].minX, frames[1].maxX + 16, accuracy: 0.001)
        XCTAssertEqual(frames[3].minX, frames[2].minX + max(frames[2].width / 2, frames[2].width - 80), accuracy: 0.001)
    }

    func testRelationsDropStraightWhereBoxesOverlapAndRunInAnSElsewhere() throws {
        let laidOut = try layout("eventmodeling\ntf 01 ui A\ntf 02 cmd B\ntf 03 ui C ->> 01\ntf 04 evt D ->> 01")
        let frames = laidOut.frames.map(\.frame)
        let down = laidOut.relations[0]
        XCTAssertEqual(down.path.start, CGPoint(x: (frames[1].minX + frames[0].maxX) / 2, y: frames[0].maxY))
        XCTAssertEqual(down.arrow.tip, CGPoint(x: down.path.start.x, y: frames[1].minY))
        XCTAssertEqual(down.arrow.direction, CGVector(dx: 0, dy: 1))
        // Along a lane: from the side of one box to the side of the other, short of the arrow.
        let along = laidOut.relations[1]
        XCTAssertEqual(along.path.start, CGPoint(x: frames[0].maxX, y: frames[0].midY))
        XCTAssertEqual(along.arrow.tip, CGPoint(x: frames[2].minX, y: frames[2].midY))
        XCTAssertEqual(along.path.segments, [.line(to: CGPoint(x: frames[2].minX - 7, y: frames[2].midY))])
        // Two lanes down without overlap: an S from near the source's end to near the target's start.
        let curve = laidOut.relations[2]
        XCTAssertEqual(curve.path.start, CGPoint(x: frames[0].maxX - 24, y: frames[0].maxY))
        XCTAssertEqual(curve.arrow.tip, CGPoint(x: frames[3].minX + 24, y: frames[3].minY))
        guard case .curve(let end, let first, let second) = curve.path.segments.first else { return XCTFail("An S curve") }
        XCTAssertEqual(end, CGPoint(x: frames[3].minX + 24, y: frames[3].minY - 7))
        XCTAssertEqual(first.y, second.y)
    }

    func testDataLinesAreCutAtFortyEightCharactersInTheMonospacedFont() throws {
        let laidOut = try layout("eventmodeling\ntf 01 cmd A { " + String(repeating: "x", count: 100) + " }")
        let frame = laidOut.frames[0]
        XCTAssertEqual(frame.dataLines.map { line in line.lines[0].count }, [48, 48, 4])
        XCTAssertEqual(frame.dataLines[1].center.y - frame.dataLines[0].center.y, 17, "Lines 1.4 times 12 points apart")
        XCTAssertEqual(frame.frame.height, 20 + 21 + 6 + 3 * 17)
        XCTAssertEqual(frame.dataLines[0].center.x - frame.dataLines[0].size.width / 2, frame.frame.minX + 12, accuracy: 0.001)
        let scene = DiagramScene(layout: laidOut)
        XCTAssertEqual(scene.texts.filter(\.isMonospaced).count, 3)
    }

    func testNotesAndSpecificationsAreCardsBelowTheLanes() throws {
        let laidOut = try layout("eventmodeling\ntf 01 ui A\ntf 02 cmd AddItem\nnote 02 {\n  First line\n  second line\n}\ngwt 02 given evt A then evt B evt C\ngwt 09 given evt A when cmd D then evt E")
        XCTAssertEqual(laidOut.cards.map { card in card.heading.lines.joined() }, ["Note · 02 AddItem", "Given / When / Then · 02 AddItem", "Given / When / Then · 09"])
        XCTAssertEqual(laidOut.cards.map { card in card.lines.map { line in line.lines.joined() } }, [
            ["First line", "second line"], ["Given  A", "Then  B, C"], ["Given  A", "When  D", "Then  E"],
        ])
        XCTAssertEqual(laidOut.cards[0].frame.minY, (laidOut.laneBands.last?.maxY ?? 0) + 8)
        XCTAssertEqual(laidOut.cards[1].frame.minY, laidOut.cards[0].frame.maxY + 8)
        XCTAssertEqual(laidOut.cards[0].frame.height, 20 + 20 + 2 * 20, "A 13-point heading and rows 20 points apart")
        let alone = try layout("eventmodeling\nnote 01 {\n  Only a note\n}")
        XCTAssertEqual(alone.cards[0].frame.minY, 8, "The first card with no lanes above it starts at the top")
    }

    func testDownAColumnEachFrameIsACardUnderItsLaneNameAndSkippingRelationsRunOnRails() throws {
        let diagram = try EventModelReading.diagram("eventmodeling\ntf 01 ui A\ntf 02 cmd B\ntf 03 evt C\ntf 04 rmo D ->> 01\ntf 05 ui E ->> 02")
        let laidOut = EventModelLayoutEngine.layout(diagram, typography: typography, columnWidth: 280)
        XCTAssertTrue(laidOut.runsDown)
        XCTAssertTrue(laidOut.laneBands.isEmpty)
        // Two relations skip cards with overlapping spans: two rails, the gutter 24 and 8 points.
        let cardWidth = max(120, 280 - 16 - 32)
        XCTAssertEqual(laidOut.frames[0].frame, CGRect(x: 8, y: laidOut.frames[0].frame.minY, width: CGFloat(cardWidth), height: 41))
        XCTAssertEqual(laidOut.frames.map(\.number).compactMap { number in number?.lines.first }, ["01", "02", "03", "04", "05"])
        XCTAssertEqual(laidOut.frames[1].frame.minY - laidOut.frames[0].frame.maxY, 28 + 21 + 12, "28 points, the lane's name and 12 points")
        let skipping = laidOut.relations.filter { relation in relation.path.segments.count == 3 }
        XCTAssertEqual(skipping.count, 2)
        let rails = skipping.map { relation in relation.path.segments.first.map { segment -> CGFloat in
            guard case .line(let point) = segment else { return 0 }
            return point.x
        } ?? 0 }
        XCTAssertEqual(rails[1] - rails[0], 8, "The second relation takes the next rail out")
        XCTAssertEqual(rails[0], 8 + CGFloat(cardWidth) + 32 - 32 + 12)
        XCTAssertEqual(skipping[0].arrow.direction, CGVector(dx: -1, dy: 0))
        XCTAssertTrue(laidOut.frames.allSatisfy(\.isOutlinedInBorder))
    }

    /// Pele writes a card's number (`pele-em-frame`) at the data's size in the text's font, not the data's monospaced
    /// one, and draws the relations before the lanes' names, which belong to the cards' groups.
    func testDownAColumnTheNumbersAreInTheTextsFontAndTheRelationsUnderTheLaneNames() throws {
        let diagram = try EventModelReading.diagram("eventmodeling\ntf 01 ui A\ntf 02 cmd B\ntf 03 evt C ->> 01")
        let laidOut = EventModelLayoutEngine.layout(diagram, typography: typography, columnWidth: 280)
        let regular = typography.measurer(size: 12)
        for frame in laidOut.frames {
            let number = try XCTUnwrap(frame.number)
            XCTAssertEqual(number.size.width, regular.width(of: number.lines[0]), accuracy: 0.001)
            XCTAssertEqual(number.center.x + number.size.width / 2, frame.frame.maxX - 12, accuracy: 0.001)
        }
        let scene = DiagramScene(layout: laidOut)
        let numbers = scene.texts.filter { text in text.paint == .muted && text.part == .label }
        XCTAssertEqual(numbers.count, 3)
        XCTAssertFalse(numbers.contains(where: \.isMonospaced))
        func firstIndex(of part: DiagramScenePart) -> Int? {
            scene.items.firstIndex { item in
                switch item {
                case .shape(let shape): shape.part == part
                case .text(let text): text.part == part
                }
            }
        }
        XCTAssertLessThan(try XCTUnwrap(firstIndex(of: .edge)), try XCTUnwrap(firstIndex(of: .clusterLabel)))
        let across = DiagramScene(layout: EventModelLayoutEngine.layout(diagram, typography: typography))
        XCTAssertLessThan(across.items.firstIndex { item in if case .text(let text) = item { text.part == .clusterLabel } else { false } } ?? .max,
                          across.items.firstIndex { item in if case .shape(let shape) = item { shape.part == .edge } else { false } } ?? -1,
                          "Across, the lanes and their names come before the relations")
    }

    func testTheRailsOfRelationsIntoOneCardAreShared() {
        let relations = [(0, 3), (1, 3), (2, 5), (4, 6), (0, 1)].map { pair in EventModelRelation(sourceFrameIndex: pair.0, targetFrameIndex: pair.1) }
        let rails = EventModelRelationRails(relations: relations)
        XCTAssertEqual(rails.railByTarget, [3: 0, 5: 1, 6: 0])
        XCTAssertEqual(rails.railCount, 2)
        XCTAssertEqual(rails.passedFrames, [1])
    }

    func testTheSceneIsPaintedInPelesColorsAndOrder() throws {
        let scene = DiagramScene(layout: try layout("eventmodeling title Shop\ntf 01 ui A\ntf 02 cmd B\ntf 03 pcr C\nnote 01 {\n n\n}"))
        let shapes = scene.shapes
        XCTAssertEqual(shapes.first?.painting, .fill(.surface), "The bands first, in the surface color")
        XCTAssertTrue(shapes.contains { shape in shape.painting == .fillAndStroke(.background, .border, DiagramStroke(lineWidth: 1)) && shape.part == .node })
        XCTAssertTrue(shapes.contains { shape in shape.painting == .fillAndStroke(DiagramPaint.series(0).atOpacity(0.22), .series(0), DiagramStroke(lineWidth: 1)) })
        XCTAssertTrue(shapes.contains { shape in shape.painting == .fillAndStroke(DiagramPaint.series(6).atOpacity(0.22), .series(6), DiagramStroke(lineWidth: 1)) })
        XCTAssertEqual(scene.texts.first?.part, .title)
        XCTAssertEqual(scene.texts.filter { text in text.part == .clusterLabel }.map(\.paint), [.muted, .muted], "A processor shares the lane of a user interface")
        XCTAssertEqual(shapes.last?.part, .note)
    }

    func testTheGeneratedModelsAreLaidOutWithTheirBoxesApartInEachLane() throws {
        for frameCount in [30, 300] {
            let diagram = try EventModelReading.diagram(EventModelCorpus.generated(frameCount: frameCount))
            let laidOut = EventModelLayoutEngine.layout(diagram, typography: typography)
            XCTAssertEqual(laidOut.frames.count, frameCount)
            EventModelCorpusTests.assertBoxesApart(laidOut, diagram: diagram)
        }
    }
}
