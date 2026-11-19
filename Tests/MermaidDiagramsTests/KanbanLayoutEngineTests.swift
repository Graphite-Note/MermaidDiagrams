/**
 * File: KanbanLayoutEngineTests.swift
 * -----------------------------------
 * Layer: Tests
 * Description: A kanban board is laid out with Pele's measurements: its columns and cards, the rows under a card's text,
 *              a word broken between characters, the board folded into rows of columns; its metadata is read as YAML;
 *              its scene is painted in Pele's colors and order.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 19/11/2026
 */

import XCTest
@testable import MermaidDiagrams
@testable import MermaidDiagramsBenchmark

final class KanbanLayoutEngineTests: XCTestCase {
    private let measurers = DiagramTextMeasurerSet(regular: UniformWidthTextMeasurer(), bold: UniformWidthTextMeasurer(),
                                                   small: UniformWidthTextMeasurer(characterWidth: 7, fontSize: 14, lineHeight: 21))

    private func layout(_ source: String, maximumWidth: CGFloat? = nil) throws -> KanbanLayout {
        KanbanLayoutEngine.layout(try KanbanReading.board(source), measurers: measurers, font: UniformWidthLayout.font, maximumWidth: maximumWidth)
    }

    func testAColumnAndItsCardsArePlacedWithPelesMeasurements() throws {
        let layout = try layout("kanban\n todo[Todo]\n  a[Write docs]\n  b[Fix]@{ ticket: T-1, assigned: knsv, priority: High }")
        XCTAssertEqual(layout.size, CGSize(width: 216, height: 179))
        let column = try XCTUnwrap(layout.columns.first)
        XCTAssertEqual(column.frame, CGRect(x: 8, y: 8, width: 200, height: 163))
        XCTAssertEqual(column.titleLines.map(\.center), [CGPoint(x: 36, y: 28)])
        XCTAssertEqual(column.cardCount.center, CGPoint(x: 192.5, y: 28))
        XCTAssertEqual(column.cards.map(\.frame), [CGRect(x: 16, y: 48, width: 184, height: 41), CGRect(x: 16, y: 97, width: 184, height: 66)])
        let marked = column.cards[1]
        XCTAssertEqual(marked.ticketLines.map(\.center), [CGPoint(x: 36.5, y: 142.5)])
        XCTAssertEqual(marked.assigneeLines.map(\.center), [CGPoint(x: 176, y: 142.5)])
        XCTAssertEqual(marked.priorityMark, DiagramPath(start: CGPoint(x: 18.5, y: 102), segments: [.line(to: CGPoint(x: 18.5, y: 158))]))
        XCTAssertNil(column.cards[0].priorityMark)
    }

    func testATicketAndAnAssigneeTooWideForOneRowTakeTwo() throws {
        let card = try XCTUnwrap(try layout("kanban\n todo\n  a@{ ticket: TICKET-0123456789, assigned: a long assignee name }").columns[0].cards.first)
        // 17 and 20 characters of 7 points and the gap of 8 are wider than the card's 164 points of text.
        XCTAssertEqual(card.frame.height, 20 + 21 + 4 + 21 + 21)
        XCTAssertEqual(card.ticketLines[0].center.y + 21, card.assigneeLines[0].center.y)
        // 12 and 11 characters, 161 points, fit the 164 but not with the gap of 8 Pele keeps between them.
        let close = try XCTUnwrap(try layout("kanban\n todo\n  a@{ ticket: T-0123456789, assigned: abcdefghijk }").columns[0].cards.first)
        XCTAssertEqual(close.frame.height, 20 + 21 + 4 + 21 + 21)
    }

    func testAWordTooLongForACardIsBrokenBetweenCharacters() throws {
        let card = try XCTUnwrap(try layout("kanban\n todo\n  a[" + String(repeating: "w", count: 60) + "]").columns[0].cards.first)
        XCTAssertEqual(card.textLines.map { line in line.lines[0].count }, [23, 23, 14])
        XCTAssertTrue(card.textLines.allSatisfy { line in line.frame.maxX <= card.frame.maxX - 10 })
        let typography = DiagramTypography(font: DiagramFont(postScriptName: nil, size: 16))
        let board = try KanbanReading.board("kanban\ntodo\n a[" + String(repeating: "w", count: 40_000) + "]")
        XCTAssertEqual(KanbanLayoutEngine.layout(board, typography: typography).size.width, 216, "Pele's stress test: the card keeps its width")
    }

    func testABoardWiderThanItsWidthIsFoldedIntoRowsThatShareIt() throws {
        let source = "kanban\n one\n  a\n two\n  b\n  c\n three\n  d"
        XCTAssertEqual(try layout(source).size.width, 3 * 212 - 12 + 16)
        let two = try layout(source, maximumWidth: 500)
        XCTAssertEqual(two.size.width, 500)
        XCTAssertEqual(two.columns.map(\.frame.width), [236, 236, 236])
        XCTAssertEqual(two.columns.map(\.frame.minY), [8, 8, two.columns[0].frame.maxY + 12])
        XCTAssertEqual(two.columns[0].frame.height, two.columns[1].frame.height, "A row's columns are as tall as its tallest")
        let one = try layout(source, maximumWidth: 300)
        XCTAssertEqual(one.size.width, 300)
        XCTAssertEqual(one.columns.map(\.frame.width), [284, 284, 284])
        let capped = try layout("kanban\n one\n  a\n two\n  b", maximumWidth: 421)
        XCTAssertEqual(capped.columns.map(\.frame.width), [400, 400], "A column of a row of one takes the row, up to twice its own width")
    }

    func testTheTitleIsCenteredAboveTheBoard() throws {
        let layout = try layout("---\ntitle: A title much wider than the board's one column\n---\nkanban\n todo")
        let title = try XCTUnwrap(layout.title)
        XCTAssertEqual(layout.size.width, (title.size.width + 16).rounded(.up))
        XCTAssertEqual(layout.columns[0].frame.minY, 8 + 24 + 16)
        XCTAssertEqual(layout.columns[0].frame.midX, layout.size.width / 2, accuracy: 0.5)
    }

    func testTheSceneIsPaintedInPelesColorsAndOrder() throws {
        let linked = "---\nconfig:\n  kanban:\n    ticketBaseUrl: 'https://example.com/#TICKET#'\n---\n"
        let scene = DiagramScene(layout: try layout(linked + "kanban\n todo[Todo]\n  a[Card]@{ ticket: T-1, assigned: k, priority: 'Very Low' }"))
        XCTAssertEqual(scene.items.map(Self.part), [.cluster, .clusterLabel, .count, .node, .priority, .label, .ticket, .assigned])
        XCTAssertEqual(scene.shapes.map(\.painting), [.fill(.surface), .fillAndStroke(.background, .border, DiagramStroke(lineWidth: 1)),
                                                      .stroke(.muted, DiagramStroke(lineWidth: 3, lineCap: .round))])
        XCTAssertEqual(scene.texts.map(\.paint), [.foreground, .muted, .foreground, .accent, .muted])
        XCTAssertEqual(scene.texts.map(\.isBold), [true, false, false, false, false])
        XCTAssertEqual(KanbanPriority.allCases.map(KanbanScene.paint(of:)),
                       [.critical, DiagramPaint.critical.atOpacity(0.5), DiagramPaint.muted.atOpacity(0.5), .muted])
    }

    func testEveryDocumentationExampleIsDrawnWithItsCardsInsideTheirColumnsApart() throws {
        let examples = try KanbanCorpus.documentationExamples()
        XCTAssertEqual(examples.count, 3)
        let typography = DiagramTypography(font: DiagramFont(postScriptName: nil, size: 16))
        for source in examples + [KanbanCorpus.board(columnCount: 10, cardsPerColumn: 50)] {
            let layout = KanbanLayoutEngine.layout(try KanbanReading.board(source), typography: typography)
            XCTAssertFalse(layout.columns.isEmpty)
            for (index, column) in layout.columns.enumerated() {
                for other in layout.columns[(index + 1)...] { XCTAssertFalse(column.frame.intersects(other.frame)) }
                for (cardIndex, card) in column.cards.enumerated() {
                    XCTAssertTrue(column.frame.contains(card.frame))
                    if cardIndex > 0 { XCTAssertGreaterThanOrEqual(card.frame.minY, column.cards[cardIndex - 1].frame.maxY + 8) }
                    for line in card.textLines + card.ticketLines + card.assigneeLines { XCTAssertLessThanOrEqual(line.frame.maxX, card.frame.maxX - 9.99) }
                }
            }
        }
        let documented = try KanbanReading.board(examples[2])
        XCTAssertEqual(documented.columns.map(\.cards.count), [2, 1, 1, 2, 3, 1])
        XCTAssertTrue(documented.options.linksTickets)
        XCTAssertEqual(documented.columns[4].cards[1].priority, .veryHigh)
    }

    private static func part(_ item: DiagramSceneItem) -> DiagramScenePart {
        switch item {
        case .shape(let shape): shape.part
        case .text(let text): text.part
        }
    }
}

final class KanbanCardMetadataTests: XCTestCase {
    private func fields(_ text: String) throws -> [String: String] {
        try KanbanCardMetadata(text: text).fields
    }

    func testFlowAndBlockMappingsAreReadAsJavaScriptWritesTheirValues() throws {
        XCTAssertEqual(try fields(" ticket: MC-2037, assigned: 'knsv', priority: \"High\" "), ["ticket": "MC-2037", "assigned": "knsv", "priority": "High"])
        XCTAssertEqual(try fields("\n  icon: star\n  assigned: knsv # a comment\n"), ["icon": "star", "assigned": "knsv"])
        XCTAssertEqual(try fields(" ticket: 1234, a: 1.50, b: 0x1F, c: 1e3 "), ["ticket": "1234", "a": "1.5", "b": "31", "c": "1000"])
        XCTAssertEqual(try fields(" a: 0, b: false, c: null, d: '', e: ~, f: true "), ["f": "true"], "JavaScript holds the others false")
        XCTAssertEqual(try fields(" label: 'it''s', other: \"tab\\there\" "), ["label": "it's", "other": "tab\there"])
        XCTAssertEqual(try fields(" url: https://example.com/x "), ["url": "https://example.com/x"], "A colon not followed by a blank is text")
        XCTAssertEqual(try fields(" nested: { a: 1 }, list: [1, 2], kept: yes "), ["nested": "[object Object]", "list": "1,2", "kept": "yes"],
                       "A flow collection is written as JavaScript's String writes it")
        XCTAssertEqual(try fields(" priority: [High], assigned: [~, 1.50, [a, b], {c: d}, true], ticket: [] "),
                       ["priority": "High", "assigned": ",1.5,a,b,[object Object],true"])
        XCTAssertEqual(try fields("\n  label: [two, words]\n  ticket: {a: 1}\n"), ["label": "two,words", "ticket": "[object Object]"])
        XCTAssertEqual(try fields("\n  label: two\n    words\n  ticket: T\n"), ["label": "two words", "ticket": "T"])
        XCTAssertEqual(try fields("\n {ticket: T-1}\n"), ["ticket": "T-1"])
        XCTAssertEqual(try fields(" [1, 2] "), [:], "Metadata that is not a mapping is ignored")
    }

    func testTextThatIsNotYAMLIsRefusedAndNestingIsBounded() {
        for text in [" a: 'open", " a: \"open", " a: 1,, b: 2", " a: [1 2", " a: \"\\q\"", "\n  a: 1\n b: 2\n", "\n\ta: 1\n",
                     " a: " + String(repeating: "[", count: 20_000)] {
            XCTAssertThrowsError(try fields(text), text)
        }
    }
}
