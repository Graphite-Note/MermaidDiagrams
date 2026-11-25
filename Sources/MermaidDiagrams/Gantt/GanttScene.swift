/**
 * File: GanttScene.swift
 * ----------------------
 * Layer: Core
 * Description: A laid-out Gantt chart's scene: its drawing parts back to front in the colors' roles, as Pele paints
 *              them.
 *
 * Authors: Bahey Shalash
 * Version: 0.3
 * Date: 25/11/2026
 */

import CoreGraphics

extension DiagramScene {
    /// The Gantt chart's painting: the section bands, the excluded days, the grid and the axis' line, today's line, the
    /// tasks' shapes by fill and then by outline, then the tasks' text, the sections' names, the axis' dates and the title.
    /// The paths are recorded into lanes of the thread's scene workspace.
    public init(layout: GanttLayout) {
        self.init(layout: layout, limits: .standard)
    }

    /// The scene with each of its lanes bounded as `limits` bound them (`DiagramSceneWorkspace.elementLimit(for:)`): a
    /// lane past its limit is emptied and the scene says so (`exceededPathElementLimit`), which the preparation refuses.
    public init(layout: GanttLayout, limits: MermaidDiagramLimits) {
        self = DiagramSceneWorkspace.withRecording(limits: limits) { workspace in
            var builder = DiagramSceneBuilder(workspace: workspace)
            GanttDrawingParts.addScene(of: layout, paths: GanttDrawingPaths(layout: layout, making: workspace), to: &builder)
            return builder.scene(size: layout.size, font: layout.font)
        }
    }
}

extension GanttDrawingParts {
    /// The fills, outlines and text colors in a fixed order, so that a scene is the same each time it is made.
    static let taskFillOrder: [GanttTaskFill] = [.accent, .faintAccent, .critical, .faintCritical, .alternateSurface]
    static let taskStrokeOrder: [GanttTaskStroke] = [.accent, .critical, .border]
    static let labelColorOrder: [GanttLabelColor] = [.background, .foreground, .muted]

    /// Lines have butt caps and round joins.
    static func addScene(of layout: GanttLayout, paths: GanttDrawingPaths<DiagramPathLane>, to builder: inout DiagramSceneBuilder) {
        let line = DiagramStroke(lineWidth: lineWidth, lineJoin: .round)
        builder.fill(paths.sectionBands, .surface, part: .cluster)
        builder.fill(paths.excludedDays, .alternateSurface, part: .axis)
        builder.stroke(paths.gridLines, .border, DiagramStroke(lineWidth: lineWidth, dashLengths: gridDashLengths, lineJoin: .round), part: .axis)
        builder.stroke(paths.axisLines, .border, line, part: .axis)
        builder.stroke(paths.verticalMarkerLines, .line, DiagramStroke(lineWidth: verticalMarkerLineWidth, dashLengths: verticalMarkerDashLengths),
                       part: .marker)
        let todayStyle = layout.plot?.todayStyle
        builder.stroke(paths.todayLine, todayLinePaint(todayStyle), todayLineStroke(todayStyle), part: .marker)
        builder.fill(paths.todayMark, .accent, part: .marker)
        for (index, taskFill) in taskFillOrder.enumerated() { builder.fill(paths.taskFills[index], paint(of: taskFill), part: .node) }
        for (index, taskStroke) in taskStrokeOrder.enumerated() { builder.stroke(paths.taskOutlines[index], paint(of: taskStroke), line, part: .node) }
        let tasks = layout.plot?.tasks ?? []
        for labelColor in labelColorOrder {
            for task in tasks where task.labelColor == labelColor { builder.text(task.label, paint(of: labelColor), part: .label) }
        }
        builder.texts(layout.plot?.sectionNames ?? [], .foreground, part: .clusterLabel)
        builder.texts(layout.plot?.axisDates ?? [], .muted, part: .axisLabel)
        for marker in layout.plot?.verticalMarkers ?? [] { builder.text(marker.label, .foreground, part: .label) }
        builder.title(layout.title)
    }

    /// Today's line in the accent color, or the color and opacity `todayMarker` writes.
    static func todayLinePaint(_ todayLineStyle: GanttTodayLineStyle?) -> DiagramPaint {
        let paint = todayLineStyle?.color.map(DiagramPaint.color) ?? .accent
        return todayLineStyle?.opacity.map { opacity in paint.atOpacity(opacity) } ?? paint
    }

    /// Two points wide with round joins, or as `todayMarker` writes it.
    static func todayLineStroke(_ todayLineStyle: GanttTodayLineStyle?) -> DiagramStroke {
        DiagramStroke(lineWidth: todayLineStyle?.lineWidth ?? todayLineWidth, dashLengths: todayLineStyle?.dashLengths ?? [],
                      lineCap: todayLineStyle?.lineCap ?? .butt, lineJoin: todayLineStyle?.lineJoin ?? .round)
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
