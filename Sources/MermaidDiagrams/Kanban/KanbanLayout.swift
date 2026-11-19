/**
 * File: KanbanLayout.swift
 * ------------------------
 * Layer: Core
 * Description: A kanban board laid out: each column's box, title and count of cards, each card's box, priority mark,
 *              text, ticket and assignee, and the title, on a page whose y runs down.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 19/11/2026
 */

import CoreGraphics

/// A kanban board laid out on a page whose origin is the top left corner and whose y runs down, in points. Drawing it
/// needs only colors: every position and text measurement is here. Texts written from their start or end are a block per
/// line, placed where Pele starts or ends it.
public struct KanbanLayout: Equatable, Sendable {
    public let size: CGSize
    /// The font the text was measured in.
    public let font: DiagramFont
    /// The columns in the board's order, a row of them after another when the board was folded to fit a width.
    public let columns: [KanbanLayoutColumn]
    /// The board's title, centered above it, or nil.
    public let title: DiagramTextBlock?
}

public struct KanbanLayoutColumn: Equatable, Sendable {
    /// The column's box, as tall as the tallest column of its row.
    public let frame: CGRect
    /// The title's lines, bold, from the top left of the box.
    public let titleLines: [DiagramTextBlock]
    /// How many cards it holds, at the top right of the box.
    public let cardCount: DiagramTextBlock
    public let cards: [KanbanLayoutCard]
}

public struct KanbanLayoutCard: Equatable, Sendable {
    public let frame: CGRect
    /// The mark along the card's left side, from its top end down, or nil for a card without a marked priority.
    public let priorityMark: DiagramPath?
    public let priority: KanbanPriority?
    public let textLines: [DiagramTextBlock]
    /// The ticket's lines from the card's left, under the text.
    public let ticketLines: [DiagramTextBlock]
    /// Whether the ticket is a link (`ticketBaseUrl`), drawn in the accent color rather than muted.
    public let ticketIsLink: Bool
    /// The assignee's lines, ending at the card's right.
    public let assigneeLines: [DiagramTextBlock]
}
