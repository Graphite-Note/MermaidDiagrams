/**
 * File: KanbanScene.swift
 * -----------------------
 * Layer: Core
 * Description: A laid-out kanban board's scene, back to front in Pele's colors, and its renderer, which paints it.
 *
 * Authors: Bahey Shalash
 * Version: 0.2
 * Date: 23/11/2026
 */

import CoreGraphics

extension DiagramScene {
    /// The board's painting, in Pele's order: the title, then each column's box in the surface color, its bold title and
    /// its muted count, then each card's box in the background color outlined in the border color, its priority mark,
    /// its text, its ticket (muted, or in the accent color when it is a link) and its muted assignee.
    public init(layout: KanbanLayout) {
        var builder = DiagramSceneBuilder()
        builder.title(layout.title)
        for column in layout.columns {
            builder.fill(KanbanScene.roundedBox(column.frame), .surface, part: .cluster)
            for line in column.titleLines { builder.text(line, .foreground, isBold: true, part: .clusterLabel) }
            builder.text(column.cardCount, .muted, part: .count)
            for card in column.cards { KanbanScene.add(card, to: &builder) }
        }
        self = builder.scene(size: layout.size, font: layout.font)
    }
}

enum KanbanScene {
    /// Pele's corner radius (`--pele-radius`).
    static let cornerRadius: CGFloat = 4
    static let cardOutlineWidth: CGFloat = 1
    static let priorityMarkWidth: CGFloat = 3

    static func roundedBox(_ frame: CGRect) -> DiagramScenePath {
        DiagramScenePath(roundedRect: frame, cornerWidth: min(cornerRadius, frame.width / 2), cornerHeight: min(cornerRadius, frame.height / 2))
    }

    /// The paint Pele marks a priority in: the critical color for the high ones, muted for the low ones, the nearer to
    /// `Medium` at half opacity.
    static func paint(of priority: KanbanPriority) -> DiagramPaint {
        switch priority {
        case .veryHigh: .critical
        case .high: DiagramPaint.critical.atOpacity(0.5)
        case .low: DiagramPaint.muted.atOpacity(0.5)
        case .veryLow: .muted
        }
    }

    static func add(_ card: KanbanLayoutCard, to builder: inout DiagramSceneBuilder) {
        builder.fillAndStroke(roundedBox(card.frame), fill: .background, stroke: .border, DiagramStroke(lineWidth: cardOutlineWidth), part: .node)
        if let mark = card.priorityMark, let priority = card.priority {
            builder.stroke(DiagramEdgeDrawing.path(mark), paint(of: priority), DiagramStroke(lineWidth: priorityMarkWidth, lineCap: .round), part: .priority)
        }
        for line in card.textLines { builder.text(line, .foreground, part: .label) }
        for line in card.ticketLines { builder.text(line, card.ticketIsLink ? .accent : .muted, part: .ticket) }
        for line in card.assigneeLines { builder.text(line, .muted, part: .assigned) }
    }
}

/// Draws a laid-out kanban board into a Core Graphics context whose origin is the layout's top left and whose y runs
/// down, by painting its scene with `DiagramSceneRenderer`.
public enum KanbanRenderer {
    public static func draw(_ layout: KanbanLayout, in context: CGContext, palette: DiagramPalette) {
        DiagramSceneRenderer.draw(DiagramScene(layout: layout), in: context, palette: palette)
    }
}
