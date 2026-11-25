/**
 * File: KanbanScene.swift
 * -----------------------
 * Layer: Core
 * Description: A laid-out kanban board's scene, back to front in Pele's colors, and its renderer, which paints it.
 *
 * Authors: Bahey Shalash
 * Version: 0.3
 * Date: 25/11/2026
 */

import CoreGraphics

extension DiagramScene {
    /// The board's painting, in Pele's order: the title, then each column's box in the surface color, its bold title and
    /// its muted count, then each card's box in the background color outlined in the border color, its priority mark,
    /// its text, its ticket (muted, or in the accent color when it is a link) and its muted assignee.
    /// The boxes and priority marks are recorded into lanes of the thread's scene workspace, each given back once the
    /// builder has copied it.
    public init(layout: KanbanLayout) {
        self.init(layout: layout, limits: .standard)
    }

    /// The scene with each of its lanes bounded as `limits` bound them (`DiagramSceneWorkspace.elementLimit(for:)`): a
    /// lane past its limit is emptied and the scene says so (`exceededPathElementLimit`), which the preparation refuses.
    public init(layout: KanbanLayout, limits: MermaidDiagramLimits) {
        self = DiagramSceneWorkspace.withRecording(limits: limits) { workspace in
            var builder = DiagramSceneBuilder(workspace: workspace)
            builder.title(layout.title)
            for column in layout.columns {
                let madeCount = workspace.madePathCount
                builder.fill(KanbanScene.roundedBox(column.frame, making: workspace), .surface, part: .cluster)
                workspace.givePathsBack(downTo: madeCount)
                for line in column.titleLines { builder.text(line, .foreground, isBold: true, part: .clusterLabel) }
                builder.text(column.cardCount, .muted, part: .count)
                for card in column.cards { KanbanScene.add(card, to: &builder, making: workspace) }
            }
            return builder.scene(size: layout.size, font: layout.font)
        }
    }
}

enum KanbanScene {
    /// Pele's corner radius (`--pele-radius`).
    static let cornerRadius: CGFloat = 4
    static let cardOutlineWidth: CGFloat = 1
    static let priorityMarkWidth: CGFloat = 3

    /// A rounded box with Pele's corners, no larger than half its sides, for the tree view's and Ishikawa diagram's
    /// scenes, which draw Core Graphics paths.
    static func roundedBox(_ frame: CGRect) -> CGPath {
        CGPath(roundedRect: frame, cornerWidth: min(cornerRadius, frame.width / 2), cornerHeight: min(cornerRadius, frame.height / 2), transform: nil)
    }

    /// `roundedBox(_:)` as a lane of `workspace`.
    static func roundedBox(_ frame: CGRect, making workspace: DiagramSceneWorkspace) -> DiagramPathLane {
        workspace.roundedRectangle(frame, cornerWidth: min(cornerRadius, frame.width / 2), cornerHeight: min(cornerRadius, frame.height / 2))
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

    static func add(_ card: KanbanLayoutCard, to builder: inout DiagramSceneBuilder, making workspace: DiagramSceneWorkspace) {
        let madeCount = workspace.madePathCount
        defer { workspace.givePathsBack(downTo: madeCount) }
        builder.fillAndStroke(roundedBox(card.frame, making: workspace), fill: .background, stroke: .border, DiagramStroke(lineWidth: cardOutlineWidth),
                              part: .node)
        if let mark = card.priorityMark, let priority = card.priority {
            let drawn = workspace.makeLane()
            DiagramEdgeDrawing.record(mark, into: drawn)
            builder.stroke(drawn, paint(of: priority), DiagramStroke(lineWidth: priorityMarkWidth, lineCap: .round), part: .priority)
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
