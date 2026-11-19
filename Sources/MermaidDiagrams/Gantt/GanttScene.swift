/**
 * File: GanttScene.swift
 * ----------------------
 * Layer: Core
 * Description: A laid-out Gantt chart's scene: its drawing parts back to front in the colors' roles, as Pele paints
 *              them.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 19/11/2026
 */

import CoreGraphics

extension DiagramScene {
    /// The Gantt chart's painting: the section bands, the excluded days, the grid and the axis' line, today's line, the
    /// tasks' shapes by fill and then by outline, then the tasks' text, the sections' names, the axis' dates and the title.
    public init(layout: GanttLayout) {
        var builder = DiagramSceneBuilder()
        GanttDrawingParts(layout: layout).addScene(to: &builder)
        self = builder.scene(size: layout.size, font: layout.font)
    }
}

extension GanttDrawingParts {
    /// The fills, outlines and text colors in a fixed order, so that a scene is the same each time it is made.
    static let taskFillOrder: [GanttTaskFill] = [.accent, .faintAccent, .critical, .faintCritical, .alternateSurface]
    static let taskStrokeOrder: [GanttTaskStroke] = [.accent, .critical, .border]
    static let labelColorOrder: [GanttLabelColor] = [.background, .foreground, .muted]

    /// Lines have butt caps and round joins.
    func addScene(to builder: inout DiagramSceneBuilder) {
        let line = DiagramStroke(lineWidth: Self.lineWidth, lineJoin: .round)
        builder.fill(sectionBands, .surface, part: .cluster)
        builder.fill(excludedDays, .alternateSurface, part: .axis)
        builder.stroke(gridLines, .border, DiagramStroke(lineWidth: Self.lineWidth, dashLengths: Self.gridDashLengths, lineJoin: .round), part: .axis)
        builder.stroke(axisLines, .border, line, part: .axis)
        builder.stroke(todayLine, .accent, DiagramStroke(lineWidth: Self.todayLineWidth, lineJoin: .round), part: .marker)
        builder.fill(todayMark, .accent, part: .marker)
        for taskFill in Self.taskFillOrder { if let path = taskFills[taskFill] { builder.fill(path, Self.paint(of: taskFill), part: .node) } }
        for taskStroke in Self.taskStrokeOrder {
            if let path = taskOutlines[taskStroke] { builder.stroke(path, Self.paint(of: taskStroke), line, part: .node) }
        }
        for labelColor in Self.labelColorOrder { builder.texts(taskTexts[labelColor] ?? [], Self.paint(of: labelColor), part: .label) }
        builder.texts(sectionNames, .foreground, part: .clusterLabel)
        builder.texts(axisDates, .muted, part: .axisLabel)
        builder.title(title)
    }

    static func paint(of taskFill: GanttTaskFill) -> DiagramPaint {
        switch taskFill {
        case .accent: .accent
        case .faintAccent: DiagramPaint.accent.atOpacity(faintFillOpacity)
        case .critical: .critical
        case .faintCritical: DiagramPaint.critical.atOpacity(faintFillOpacity)
        case .alternateSurface: .alternateSurface
        }
    }

    static func paint(of taskStroke: GanttTaskStroke) -> DiagramPaint {
        switch taskStroke {
        case .accent: .accent
        case .critical: .critical
        case .border: .border
        }
    }

    static func paint(of labelColor: GanttLabelColor) -> DiagramPaint {
        switch labelColor {
        case .background: .background
        case .foreground: .foreground
        case .muted: .muted
        }
    }
}
