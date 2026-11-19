/**
 * File: UserJourneyColumnTests.swift
 * ----------------------------------
 * Layer: Tests
 * Description: A user journey turned to a column of cards for a container too narrow for the cards side by side, as
 *              Pele's vertical journey lays it out.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 19/11/2026
 */

import XCTest
@testable import MermaidDiagrams

/// Pele's journey column, with cards' text 7 points a character in 21-point lines and the title 8 in 24.
final class UserJourneyColumnTests: XCTestCase {
    private let accuracy: CGFloat = 0.01
    private let font = DiagramFont(postScriptName: nil, size: 16)
    private let day = "journey\n  title My day\n  section Work\n    Make tea: 5: Me\n    Do work: 1: Me, Cat\n  section Home\n    Sit down: 3: Me\n    Eat: x"

    private func column(_ source: String, availableWidth: CGFloat?) throws -> UserJourneyColumnLayout? {
        UserJourneyLayoutEngine.columnLayout(try UserJourneyReading.userJourney(source), taskText: UniformWidthTextMeasurer(characterWidth: 7, fontSize: 14, lineHeight: 21),
                                             scaleText: UniformWidthTextMeasurer(characterWidth: 6, fontSize: 12, lineHeight: 18), titleText: UniformWidthTextMeasurer(),
                                             font: font, availableWidth: availableWidth)
    }

    func testTheCardsStaySideBySideWhenTheyFitOrTheColumnIsWideOrNoNarrower() throws {
        XCTAssertNil(try column(day, availableWidth: nil))
        XCTAssertNil(try column(day, availableWidth: 640), "At the breakpoint")
        XCTAssertNil(try column(day, availableWidth: 5_000))
        XCTAssertNil(try column("journey\n  A: 5", availableWidth: 400), "One card fits")
        XCTAssertNotNil(try column(day, availableWidth: 639))
        XCTAssertNotNil(try column(day, availableWidth: 280))
    }

    func testTheColumnIsOneCardPerTaskUnderTheSectionHeadingsAndTheTitle() throws {
        let layout = try XCTUnwrap(try column(day, availableWidth: 280))
        XCTAssertEqual(layout.steps.count, 4)
        XCTAssertEqual(layout.headings.map { heading in heading.lines.joined() }, ["Work", "Home"])
        XCTAssertEqual(layout.connectors.count, 3)
        let title = try XCTUnwrap(layout.title)
        XCTAssertEqual(title.lines, ["My day"])
        // Room 280 - 16 = 264, the cards as wide as the room, 8 points from the left.
        XCTAssertTrue(layout.steps.allSatisfy { step in abs(step.frame.width - 264) < accuracy && abs(step.frame.minX - 8) < accuracy })
        XCTAssertEqual(layout.size.width, 280)
        // The title (24 high) and 16 under it; a heading (24 high) and 8 under it; then the first card.
        XCTAssertEqual(layout.headings[0].center, CGPoint(x: 8 + 8 + 16, y: 48 + 12))
        XCTAssertEqual(layout.steps[0].frame.minY, 80, accuracy: accuracy)
        XCTAssertEqual(title.center.x, 140, accuracy: accuracy)
    }

    func testACardHoldsItsTextItsFaceAndScoreAtTheRightAndARowPerActor() throws {
        let layout = try XCTUnwrap(try column(day, availableWidth: 280))
        let first = layout.steps[0]
        // Padding above and below, the text at least 42 high, and an actor's row of 21 with 4 below it.
        XCTAssertEqual(first.frame.height, 2 * 8 + 42 + (21 + 4), accuracy: accuracy)
        XCTAssertEqual(first.text.center.x, 8 + 10 + first.text.size.width / 2, accuracy: accuracy, "Its text starts 10 points in")
        XCTAssertEqual(first.text.center.y, first.frame.minY + 8 + first.text.size.height / 2, accuracy: accuracy)
        XCTAssertEqual(first.faceCenter, CGPoint(x: first.frame.maxX - 28, y: first.frame.minY + 8 + 11))
        XCTAssertEqual(first.mood, .happy)
        let score = try XCTUnwrap(first.score)
        XCTAssertEqual(score.lines, ["5"])
        XCTAssertEqual(score.center.x, first.faceCenter.x)
        XCTAssertEqual(score.center.y, first.frame.minY + 8 + 22 + 14 - 14 * 0.35, accuracy: accuracy, "Its baseline a line below the face")
        XCTAssertEqual(first.actors.map { actor in actor.text.lines.joined() }, ["Me"])
        XCTAssertEqual(first.actors[0].dot.center.x, first.frame.minX + 16, accuracy: accuracy)
        XCTAssertEqual(first.actors[0].dot.center.y, first.frame.minY + 8 + 42 + 4 + 21 / 2, accuracy: accuracy)
        XCTAssertEqual(first.actors[0].text.center.x - first.actors[0].text.size.width / 2, first.frame.minX + 28, accuracy: accuracy)
        let second = layout.steps[1]
        XCTAssertEqual(second.actors.map { actor in actor.text.lines.joined() }, ["Me", "Cat"], "The actors in the order they are written")
        XCTAssertEqual(second.mood, .sad)
        XCTAssertEqual(second.frame.height, 2 * 8 + 42 + 2 * (21 + 4), accuracy: accuracy)
        XCTAssertEqual(layout.steps[3].mood, .neutral)
        XCTAssertNil(layout.steps[3].score, "No score, no number")
        XCTAssertTrue(layout.steps[3].actors.isEmpty)
        XCTAssertEqual(layout.steps[3].frame.height, 2 * 8 + 42, accuracy: accuracy)
    }

    func testTheActorsDotsKeepTheirSeriesColorsOfTheJourneysActorOrder() throws {
        let layout = try XCTUnwrap(try column(day, availableWidth: 280))
        // Actors by name: Cat is 0, Me is 1.
        XCTAssertEqual(layout.steps[1].actors.map(\.dot.seriesIndex), [1, 0], "Me then Cat, as written")
        XCTAssertEqual(layout.steps[0].actors.map(\.dot.seriesIndex), [1])
    }

    func testACardsLinesAreSixteenPointsApartAndCenteredOnTheCards() throws {
        let layout = try XCTUnwrap(try column(day, availableWidth: 280))
        for (index, connector) in layout.connectors.enumerated() {
            let card = layout.steps[index].frame
            XCTAssertEqual(connector.start, CGPoint(x: card.midX, y: card.maxY))
            guard case .line(let end) = connector.segments[0] else { return XCTFail("A line") }
            XCTAssertEqual(end, CGPoint(x: card.midX, y: card.maxY + 16))
            XCTAssertEqual(layout.steps[index + 1].frame.minY, card.maxY + 16 + (index == 1 ? 24 + 8 : 0), accuracy: accuracy, "A heading between sections")
        }
        let page = CGRect(origin: .zero, size: layout.size)
        XCTAssertEqual(layout.size.height, (layout.steps[3].frame.maxY + 8).rounded(.up))
        XCTAssertTrue(page.contains(layout.steps[3].frame))
    }

    func testTheRoomIsAtLeastAHundredAndFortyPointsAndAWordTooLongIsCutToIt() throws {
        let tiny = try XCTUnwrap(try column(day, availableWidth: 100))
        XCTAssertEqual(tiny.steps[0].frame.width, 140, "Never under 140")
        let long = try XCTUnwrap(try column("journey\n  A: 5\n  Antidisestablishmentarianismoverlongword: 3", availableWidth: 200))
        XCTAssertEqual(long.steps[1].frame.width, 184, "The word is cut, so the card stays as wide as the room")
        XCTAssertGreaterThan(long.steps[1].text.lines.count, 1)
        XCTAssertEqual(long.size.width, (long.steps[1].frame.maxX + 8).rounded(.up))
        XCTAssertLessThanOrEqual(long.steps[1].text.size.width, 184 - 72 + accuracy, "The text keeps 72 points of the card for the face")
    }

    func testTheTitleAndTheHeadingsAreFittedToTheRoom() throws {
        let source = "journey\n  title A rather long title that will need to wrap in a column\n  section A heading that is rather long for a column of this width\n    Task: 3"
        let layout = try XCTUnwrap(try column(source, availableWidth: 200))
        XCTAssertGreaterThan(layout.title?.lines.count ?? 0, 1)
        XCTAssertLessThanOrEqual(layout.title?.size.width ?? 0, 184 + accuracy)
        XCTAssertGreaterThan(layout.headings[0].lines.count, 1)
        XCTAssertLessThanOrEqual(layout.headings[0].size.width, 168 + accuracy)
    }

    func testAJourneyWithoutTasksAndTasksBeforeAnySectionLayOutToo() throws {
        XCTAssertNil(try column("journey", availableWidth: 200), "Nothing to turn")
        let plain = try XCTUnwrap(try column("journey\n  A: 5\n  B: 4\n  C: 2\n  D: 1\n  E: 3", availableWidth: 200))
        XCTAssertTrue(plain.headings.isEmpty)
        XCTAssertEqual(plain.steps.count, 5)
        XCTAssertEqual(plain.steps[0].frame.minY, 8, "No title and no heading above the first card")
    }

    func testTheColumnSceneIsPaintedInPelesOrder() throws {
        let layout = try XCTUnwrap(try column(day, availableWidth: 280))
        let scene = DiagramScene(layout: layout)
        XCTAssertEqual(scene.size, layout.size)
        XCTAssertEqual(scene.shapes.first?.part, .edge, "The lines between the cards come first")
        XCTAssertTrue(scene.shapes.contains { shape in shape.part == .node })
        XCTAssertEqual(scene.texts.last?.part, .title)
        XCTAssertEqual(scene.texts.filter { text in text.part == .clusterLabel }.map { text in text.block.lines.joined() }, ["Work", "Home"])
        XCTAssertTrue(scene.texts.filter { text in text.part == .clusterLabel }.allSatisfy(\.isBold))
        let svg = DiagramSVGWriter(colors: .peleVariables).document(of: scene, diagramType: "journey", title: "T", description: "D")
        XCTAssertNotNil(DiagramSVGDocumentReading.read(svg))
        let bitmap = try pixels(scene)
        XCTAssertGreaterThan(bitmap.inkedPixelCount, 500)
    }

    func testAPreparedJourneyHasAColumnSceneForTheNarrowestColumn() throws {
        let typography = DiagramTypography(font: font)
        let prepared = try MermaidDiagramPreparation.prepare(source: day, typography: typography)
        let narrow = try XCTUnwrap(prepared.narrowScene)
        XCTAssertLessThan(narrow.size.width, prepared.scene.size.width)
        XCTAssertLessThanOrEqual(narrow.size.width, 400)
        XCTAssertGreaterThan(narrow.size.height, 300)
        XCTAssertTrue(prepared.showsNarrowScene(inColumnWidth: 350))
        XCTAssertNil(try MermaidDiagramPreparation.prepare(source: "journey\n  A: 5", typography: typography).narrowScene, "No wider than the narrowest column")
    }

    // MARK: Helpers

    private func pixels(_ scene: DiagramScene) throws -> (inkedPixelCount: Int, width: Int) {
        let width = Int(scene.size.width), height = Int(scene.size.height)
        let context = try XCTUnwrap(CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.translateBy(x: 0, y: CGFloat(height))
        context.scaleBy(x: 1, y: -1)
        context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        context.fill(CGRect(origin: .zero, size: scene.size))
        DiagramSceneRenderer.draw(scene, in: context, palette: .peleLight)
        let data = try XCTUnwrap(context.data).assumingMemoryBound(to: UInt8.self)
        var inked = 0
        for offset in stride(from: 0, to: context.bytesPerRow * height, by: 4) where data[offset] < 200 { inked += 1 }
        return (inked, width)
    }
}
