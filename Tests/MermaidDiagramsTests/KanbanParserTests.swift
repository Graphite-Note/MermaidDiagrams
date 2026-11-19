/**
 * File: KanbanParserTests.swift
 * -----------------------------
 * Layer: Tests
 * Description: A kanban board is read as Mermaid reads it: Mermaid 12.1.0's kanban.spec.ts as Pele ports it (columns and
 *              cards by indentation, shapes, decorations, comments, metadata on one line and several), and its refusals.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 19/11/2026
 */

import XCTest
@testable import MermaidDiagrams

/// Reads a kanban board for a test, from its whole text, through `MermaidDiagramReader`.
enum KanbanReading {
    struct NotAKanbanBoard: Error {}

    static func board(_ source: String, limits: MermaidDiagramLimits = .standard) throws -> KanbanBoard {
        guard case .kanban(let board) = try MermaidDiagramReader.read(source, limits: limits) else { throw NotAKanbanBoard() }
        return board
    }

    static func readError(_ source: String, limits: MermaidDiagramLimits = .standard) -> MermaidDiagramReadError? {
        do {
            _ = try MermaidDiagramReader.read(source, limits: limits)
            return nil
        } catch {
            return error
        }
    }
}

final class KanbanParserTests: XCTestCase {
    private func board(_ source: String) throws -> KanbanBoard {
        try KanbanReading.board(source)
    }

    func testHierarchy() throws {
        // KNBN-1
        XCTAssertEqual(try board("kanban\n    root").columns.map(\.label.spokenText), ["root"])
        // KNBN-2
        let two = try board("kanban\n    root\n      child1\n      child2\n ")
        XCTAssertEqual(two.columns.count, 1)
        XCTAssertEqual(two.columns[0].cards.map(\.label.spokenText), ["child1", "child2"])
        // 3: a shape without an identifier
        XCTAssertEqual(try board("kanban\n    (root)").columns[0].label.spokenText, "root")
        // KNBN-4: deeper levels are not told apart
        let deeper = try board("kanban\n    root\n      child1\n        leaf1\n      child2")
        XCTAssertEqual(deeper.columns.count, 1)
        XCTAssertEqual(deeper.columns[0].cards.count, 3)
        // 5
        XCTAssertEqual(try board("kanban\n    section1\n    section2").columns.map(\.label.spokenText), ["section1", "section2"])
        // KNBN-6: a node indented less than the columns, then another
        XCTAssertEqual(KanbanReading.readError("kanban\n          root\n        fakeRoot\n    realRootWrongPlace"),
                       .invalidSyntax(line: 4, problem: .kanbanCardWithoutColumn(text: "fakeRoot")))
        XCTAssertEqual(try board("kanban\n    root\n  lastAndMisplaced").columns[0].cards.map(\.label.spokenText), ["lastAndMisplaced"],
                       "Mermaid refuses only a node after it")
    }

    func testNodes() throws {
        // KNBN-7
        let identified = try board("kanban\n    root[The root]\n      ")
        XCTAssertEqual(identified.columns[0].identifier, "root")
        XCTAssertEqual(identified.columns[0].label.spokenText, "The root")
        // KNBN-8 and KNBN-9
        for source in ["kanban\n    root\n      theId(child1)", "kanban\nroot\n      theId(child1)"] {
            let card = try XCTUnwrap(try board(source).columns[0].cards.first, source)
            XCTAssertEqual(card.label.spokenText, "child1")
            XCTAssertEqual(card.identifier, "theId")
        }
    }

    func testDecorationsAreReadAndCounted() throws {
        // KNBN-13 to KNBN-16
        for decorations in ["::icon(bomb)", ":::m-4 p-8", ":::m-4 p-8\n    ::icon(bomb)", "::icon(bomb)\n    :::m-4 p-8"] {
            let read = try board("kanban\n    root[The root]\n    \(decorations)\n    ")
            XCTAssertEqual(read.columns[0].identifier, "root")
            XCTAssertEqual(read.columns[0].label.spokenText, "The root")
            XCTAssertEqual(read.unappliedDecorationCount, decorations.components(separatedBy: "\n").count, decorations)
        }
    }

    func testDescriptions() throws {
        // KNBN-17 and KNBN-18
        let quoted = try board("kanban\n    root[\"String containing []\"]\n      child1[\"String containing ()\"]\n")
        XCTAssertEqual(quoted.columns[0].label.spokenText, "String containing []")
        XCTAssertEqual(quoted.columns[0].cards.map(\.label.spokenText), ["String containing ()"])
        // KNBN-19 to KNBN-22: a class, blank lines and comments between cards
        for source in ["kanban\n  root(Root)\n    Child(Child)\n    :::hot\n      a(a)\n      b[New Stuff]",
                       "kanban\n  root(Root)\n    Child(Child)\n      a(a)\n\n      b[New Stuff]",
                       "kanban\n  root(Root)\n    Child(Child)\n      a(a)\n\n      %% This is a comment\n      b[New Stuff]",
                       "kanban\n  root(Root)\n    Child(Child)\n      a(a) %% This is a comment\n      b[New Stuff]"] {
            let read = try board(source)
            XCTAssertEqual(read.columns[0].identifier, "root", source)
            XCTAssertEqual(read.columns[0].label.spokenText, "Root", source)
            XCTAssertEqual(read.columns[0].cards.map(\.identifier), ["Child", "a", "b"], source)
        }
        // KNBN-23 to KNBN-25: rows of spaces, and rows above the keyword
        for source in ["kanban\nroot\n A\n \n\n B", "\n \nkanban\nroot\n A\n \n\n B", "\n\n\nkanban\nroot\n A\n \n\n B"] {
            let read = try board(source)
            XCTAssertEqual(read.columns[0].identifier, "root", source)
            XCTAssertEqual(read.columns[0].cards.map(\.identifier), ["A", "B"], source)
        }
    }

    func testItemData() throws {
        // KNBN-30 to KNBN-37, on a card as the spec writes them on a column
        func card(_ metadata: String) throws -> KanbanCard {
            try XCTUnwrap(try board("kanban\n  todo\n        root\(metadata)\n    ").columns[0].cards.first)
        }
        XCTAssertEqual(try card("@{ priority: high }").priority, .high)
        XCTAssertEqual(try card("@{ assigned: knsv }").assignee, "knsv")
        XCTAssertEqual(try card("@{ icon: star }").identifier, "root")
        let lines = try card("@{\n          icon: star\n          assigned: knsv\n        }")
        XCTAssertEqual(lines.assignee, "knsv")
        XCTAssertEqual(try card("@{ icon: star, assigned: knsv }").assignee, "knsv")
        XCTAssertEqual(try card("@{ icon: star, label: 'fix things' }").label.spokenText, "fix things")
        XCTAssertEqual(try card("@{ ticket: MC-1234 }").ticket, "MC-1234")
        XCTAssertEqual(try board("kanban\n  todo@{ label: 'To do' }").columns[0].label.spokenText, "To do", "A column's label too")
        XCTAssertEqual(try board("kanban\n  todo@{ icon: star }").unappliedDecorationCount, 1)
    }

    func testPrioritiesAreMermaidsFiveNamesInAnyCase() throws {
        let board = try board("kanban\n todo\n  a@{ priority: 'Very High' }\n  b@{ priority: ' very low ' }\n  c@{ priority: Medium }\n  d@{ priority: LOW }\n"
                              + "  e@{ priority: urgent }\n  f@{ priority: [High] }")
        XCTAssertEqual(board.columns[0].cards.map(\.priority), [.veryHigh, .veryLow, nil, .low, nil, .high], "[High] is written High, as Pele's String writes it")
    }

    func testMetadataThatIsNotYAMLOrNamesAShapeInCapitalsIsRefused() {
        XCTAssertEqual(KanbanReading.readError("kanban\n todo\n  a@{ ticket: 'open }"), .invalidSyntax(line: 3, problem: .kanbanMetadataNotYAML(identifier: "a")))
        XCTAssertEqual(KanbanReading.readError("kanban\n todo\n  a@{ x: 1 y: 2, }"), nil, "A plain value runs to the comma")
        XCTAssertEqual(KanbanReading.readError("kanban\n todo\n  a@{ x: 1,, y: 2 }"), .invalidSyntax(line: 3, problem: .kanbanMetadataNotYAML(identifier: "a")))
        XCTAssertEqual(KanbanReading.readError("kanban\n todo\n  a@{ shape: Rounded }"), .invalidSyntax(line: 3, problem: .kanbanShapeNameNotLowercase("Rounded")))
        XCTAssertEqual(KanbanReading.readError("kanban\n todo\n  a@{ shape: round_rect }"),
                       .invalidSyntax(line: 3, problem: .kanbanShapeNameNotLowercase("round_rect")))
        XCTAssertEqual(KanbanReading.readError("kanban\n todo\n  a@{ ticket: 1"), .invalidSyntax(line: 3, problem: .unclosedAttributes))
        XCTAssertEqual(KanbanReading.readError("kanban\n todo\n  a@{ x: ^ }"), .invalidSyntax(line: 3, problem: .unexpectedText("^ }")))
        XCTAssertEqual(KanbanReading.readError("kanban\n todo\n  a[Card] @{ ticket: 1 }"), .invalidSyntax(line: 3, problem: .unexpectedText("@{ ticket: 1 }")),
                       "Metadata follows its node straight away")
        XCTAssertEqual(KanbanReading.readError("kanban\n todo\n  a@b"), .invalidSyntax(line: 3, problem: .unexpectedText("@b")))
        XCTAssertEqual(KanbanReading.readError("kanban"), .invalidSyntax(line: 1, problem: .expectedNode))
    }

    func testTheFrontMatterSetsTheColumnsWidthAndTicketLinks() throws {
        let configured = try board("---\nconfig:\n  kanban:\n    sectionWidth: 50\n    ticketBaseUrl: 'https://example.com/#TICKET#'\n---\nkanban\n todo")
        XCTAssertEqual(configured.options.columnWidth, 80, "At least 80")
        XCTAssertTrue(configured.options.linksTickets)
        XCTAssertEqual(try board("---\nconfig:\n  kanban:\n    sectionWidth: 5000\n---\nkanban\n todo").options.columnWidth, 2_000)
        XCTAssertEqual(try board("---\nconfig:\n  kanban:\n    sectionWidth: -1\n---\nkanban\n todo").options.columnWidth, 200)
        XCTAssertEqual(try board("---\ntitle: Sprint\n---\nkanban\n todo").title, "Sprint")
    }

    func testTheCountOfColumnsAndCardsIsBoundedBeforeTheyAreMade() {
        var limits = MermaidDiagramLimits.standard
        limits.maximumNodeCount = 3
        XCTAssertEqual(KanbanReading.readError("kanban\n todo\n  a\n  b\n  c", limits: limits), .tooManyNodes(limit: 3))
        XCTAssertNil(KanbanReading.readError("kanban\n todo\n  a\n  b", limits: limits))
    }
}
