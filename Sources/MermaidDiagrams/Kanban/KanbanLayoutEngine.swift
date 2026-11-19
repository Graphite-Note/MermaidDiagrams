/**
 * File: KanbanLayoutEngine.swift
 * ------------------------------
 * Layer: Core
 * Description: Lays a kanban board out with Pele's measurements: columns side by side, each a titled box with its cards
 *              stacked, folded into rows when the board is wider than the width it is given.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 19/11/2026
 */

import CoreGraphics

/// Lays a kanban board out as Pele's kanban renderer does: columns of `KanbanOptions.columnWidth` (200 points) 12 apart,
/// each a box padded 8 with its bold title and its count of cards at the top, and its cards 8 apart below, each padded 10
/// with its text at seven eighths of the size, broken between characters where a word is too long, then its ticket from
/// the left and its assignee from the right, on one row when they fit and on two when not. A board wider than
/// `maximumWidth` is folded into rows of columns, which then share the width. Pele's icons, which come from its host, and
/// its math are not drawn.
public enum KanbanLayoutEngine {
    static let columnGap: CGFloat = 12
    static let columnPadding: CGFloat = 8
    static let cardPadding: CGFloat = 10
    static let cardGap: CGFloat = 8
    static let metadataGap: CGFloat = 4
    /// Around the board.
    static let padding: CGFloat = 8
    /// Between the title and the board.
    static let titleGap: CGFloat = 16

    /// The board laid out, folded into rows of columns when it is wider than `maximumWidth` (nil for no limit).
    public static func layout(_ board: KanbanBoard, typography: DiagramTypography, maximumWidth: CGFloat? = nil) -> KanbanLayout {
        layout(board, measurers: DiagramTextMeasurerSet(typography: typography), font: typography.font, maximumWidth: maximumWidth)
    }

    static func layout<Measurer: DiagramTextMeasuring>(_ board: KanbanBoard, measurers: DiagramTextMeasurerSet<Measurer>, font: DiagramFont,
                                                       maximumWidth: CGFloat?) -> KanbanLayout {
        let room = maximumWidth.flatMap { width in width > 0 && width.isFinite ? max(width - 2 * padding, 1) : nil }
        let rows = KanbanRows(columnCount: board.columns.count, ownWidth: CGFloat(board.options.columnWidth), room: room, gap: columnGap)
        let cardWidth = rows.columnWidth - 2 * columnPadding
        let lineHeight = measurers.regular.lineHeight
        let measured = KanbanMeasuredColumns(board, measurers: measurers, cardWidth: cardWidth)
        let (rowTops, rowHeights) = rowExtents(measured, perRow: rows.perRow)
        let boardHeight = (rowTops.last ?? 0) + (rowHeights.last ?? 0)
        let title = board.title.map { title in
            DiagramTextBlock(label: DiagramLabel(title), measurer: measurers.bold, maximumWidth: room.map { room in max(80, room) } ?? 4_000)
        }
        let titleHeight = title.map { title in title.lines.isEmpty ? 0 : title.size.height + titleGap } ?? 0
        let boardWidth = max(CGFloat(min(board.columns.count, rows.perRow)) * (rows.columnWidth + columnGap) - columnGap, 0)
        let width = max(boardWidth, title?.size.width ?? 0)
        let left = padding + (width - boardWidth) / 2
        let size = CGSize(width: (width + 2 * padding).rounded(.up), height: (boardHeight + titleHeight + 2 * padding).rounded(.up))
        let columns = board.columns.indices.map { index in
            let row = index / rows.perRow
            let origin = CGPoint(x: left + CGFloat(index % rows.perRow) * (rows.columnWidth + columnGap), y: padding + titleHeight + rowTops[row])
            return placedColumn(frame: CGRect(origin: origin, size: CGSize(width: rows.columnWidth, height: rowHeights[row])),
                                title: measured.titles[index], count: measured.counts[index], cards: measured.cards[index],
                                headingHeight: measured.headingHeight, lineHeight: lineHeight, linksTickets: board.options.linksTickets)
        }
        var placedTitle = title
        placedTitle?.center = CGPoint(x: size.width / 2, y: padding + (title?.size.height ?? 0) / 2)
        return KanbanLayout(size: size, font: font, columns: columns, title: placedTitle)
    }

    /// Each row's top and height: its columns' heading and its tallest column's cards, rows 12 apart.
    private static func rowExtents(_ measured: KanbanMeasuredColumns, perRow: Int) -> (tops: [CGFloat], heights: [CGFloat]) {
        let bodyHeights = measured.cards.map { cards in cards.reduce(0) { height, card in height + card.height + cardGap } }
        var tops: [CGFloat] = []
        var heights: [CGFloat] = []
        var nextTop: CGFloat = 0
        for first in stride(from: 0, to: bodyHeights.count, by: perRow) {
            let height = measured.headingHeight + bodyHeights[first..<min(first + perRow, bodyHeights.count)].reduce(cardGap, max)
            tops.append(nextTop)
            heights.append(height)
            nextTop += height + columnGap
        }
        return (tops, heights)
    }

    private static func placedColumn(frame: CGRect, title: DiagramTextBlock, count: DiagramTextBlock, cards: [KanbanMeasuredCard],
                                     headingHeight: CGFloat, lineHeight: CGFloat, linksTickets: Bool) -> KanbanLayoutColumn {
        var placedCount = count
        placedCount.center = CGPoint(x: frame.maxX - columnPadding - 4 - count.size.width / 2, y: frame.minY + columnPadding + lineHeight / 2)
        var top = frame.minY + headingHeight
        var placedCards: [KanbanLayoutCard] = []
        for card in cards {
            let cardFrame = CGRect(x: frame.minX + columnPadding, y: top, width: frame.width - 2 * columnPadding, height: card.height)
            placedCards.append(card.placed(in: cardFrame, linksTickets: linksTickets))
            top += card.height + cardGap
        }
        return KanbanLayoutColumn(frame: frame, titleLines: title.placedLines(left: frame.minX + columnPadding + 4, top: frame.minY + columnPadding),
                                  cardCount: placedCount, cards: placedCards)
    }
}

/// Each column's title, count of cards and cards measured for the columns' width, and the heading all columns share:
/// as tall as the tallest title, at least a line, and padded.
struct KanbanMeasuredColumns {
    private(set) var titles: [DiagramTextBlock] = []
    private(set) var counts: [DiagramTextBlock] = []
    private(set) var cards: [[KanbanMeasuredCard]] = []
    private(set) var headingHeight: CGFloat

    init<Measurer: DiagramTextMeasuring>(_ board: KanbanBoard, measurers: DiagramTextMeasurerSet<Measurer>, cardWidth: CGFloat) {
        let textWidth = cardWidth - 2 * KanbanLayoutEngine.cardPadding
        headingHeight = measurers.regular.lineHeight
        for column in board.columns {
            let count = DiagramTextBlock(label: DiagramLabel(String(column.cards.count)), measurer: measurers.small, maximumWidth: .greatestFiniteMagnitude)
            let title = DiagramTextBlock(label: column.label, measurer: measurers.bold, fittingWidth: cardWidth - 8 - (count.size.width + 12))
            headingHeight = max(headingHeight, title.size.height)
            titles.append(title)
            counts.append(count)
            cards.append(column.cards.map { card in KanbanMeasuredCard(card, measurer: measurers.small, textWidth: textWidth) })
        }
        headingHeight += 2 * KanbanLayoutEngine.columnPadding
    }
}

/// How many columns a row holds and how wide each is: all in one row at their own width when they fit `room`, else as
/// many as fit, sharing the row up to twice their own width.
struct KanbanRows {
    let perRow: Int
    let columnWidth: CGFloat

    init(columnCount: Int, ownWidth: CGFloat, room: CGFloat?, gap: CGFloat) {
        guard let room, CGFloat(columnCount) * (ownWidth + gap) - gap > room else {
            perRow = max(columnCount, 1)
            columnWidth = ownWidth
            return
        }
        perRow = max(1, Int(((room + gap) / (ownWidth + gap)).rounded(.down)))
        columnWidth = max(min(ownWidth, room), min(((room + gap) / CGFloat(perRow)).rounded(.down) - gap, ownWidth * 2))
    }
}

/// A card's text, ticket and assignee measured for its column's width, and its height.
struct KanbanMeasuredCard {
    let card: KanbanCard
    let text: DiagramTextBlock
    let ticket: DiagramTextBlock
    let assignee: DiagramTextBlock
    /// The rows under the text that hold the ticket and the assignee: one when both fit side by side, two when not.
    let metadataHeight: CGFloat
    let height: CGFloat

    init(_ card: KanbanCard, measurer: some DiagramTextMeasuring, textWidth: CGFloat) {
        self.card = card
        text = DiagramTextBlock(label: card.label, measurer: measurer, fittingWidth: textWidth)
        ticket = DiagramTextBlock(label: card.ticket.map(DiagramLabel.init) ?? DiagramLabel(lines: []), measurer: measurer, fittingWidth: textWidth)
        assignee = DiagramTextBlock(label: card.assignee.map(DiagramLabel.init) ?? DiagramLabel(lines: []), measurer: measurer, fittingWidth: textWidth)
        metadataHeight = ticket.size.width + assignee.size.width + 8 > textWidth ? ticket.size.height + assignee.size.height
            : max(ticket.size.height, assignee.size.height)
        height = 2 * KanbanLayoutEngine.cardPadding + max(text.size.height, measurer.lineHeight)
            + (metadataHeight > 0 ? KanbanLayoutEngine.metadataGap + metadataHeight : 0)
    }

    func placed(in frame: CGRect, linksTickets: Bool) -> KanbanLayoutCard {
        let padding = KanbanLayoutEngine.cardPadding
        let mark = card.priority.map { _ in
            DiagramPath(start: CGPoint(x: frame.minX + 2.5, y: frame.minY + 5), segments: [.line(to: CGPoint(x: frame.minX + 2.5, y: frame.maxY - 5))])
        }
        let bottom = frame.maxY - padding
        return KanbanLayoutCard(frame: frame, priorityMark: mark, priority: card.priority,
                                textLines: text.placedLines(left: frame.minX + padding, top: frame.minY + padding),
                                ticketLines: ticket.placedLines(left: frame.minX + padding, top: bottom - metadataHeight), ticketIsLink: linksTickets,
                                assigneeLines: assignee.placedLines(right: frame.maxX - padding, top: bottom - assignee.size.height))
    }
}
