/**
 * File: GanttDrawingParts.swift
 * -----------------------------
 * Layer: Core
 * Description: A laid-out Gantt chart's geometry grouped by how it is painted.
 *
 * Authors: felixchvl, Bahey Shalash
 * Version: 0.2
 * Date: 24/11/2026
 */

import CoreGraphics

/// A laid-out Gantt chart's geometry grouped by how it is painted, so that drawing it in any colors is a few fills and
/// strokes, by Core Graphics (`GanttRenderer`) or by a view's own shapes. Back to front, as Pele draws: the section
/// bands, the excluded days, the grid and the axis' line, today's line, the tasks' shapes, then the text.
public struct GanttDrawingParts {
    /// The bands behind every other section, filled in the surface color.
    public let sectionBands: CGPath
    /// The runs of excluded days, filled in the alternate surface color.
    public let excludedDays: CGPath
    /// The grid lines at the axis' dates, stroked one point wide in dots of 1 and gaps of 3, in the border color.
    public let gridLines: CGPath
    /// The axis' line under the rows, and above them with `topAxis`, stroked one point wide in the border color.
    public let axisLines: CGPath
    /// Today's line, stroked two points wide in the accent color (or as `todayLineStyle` says); empty when it is not drawn.
    public let todayLine: CGPath
    /// How `todayMarker` restyles today's line, or nil for the standard line.
    public let todayLineStyle: GanttTodayLineStyle?
    /// The small triangle on top of today's line, filled in the accent color; empty for a restyled line.
    public let todayMark: CGPath
    /// The vertical markers' lines, stroked 1.5 points wide in dashes of 4 and gaps of 3, in the line color.
    public let verticalMarkerLines: CGPath
    /// The vertical markers' texts under the axis, in the text color.
    public let verticalMarkerTexts: [DiagramTextBlock]
    /// The tasks' bars and milestones, by fill; a faint fill is its color at a quarter of its opacity.
    public let taskFills: [GanttTaskFill: CGPath]
    /// The tasks' bars and milestones, by outline color, stroked one point wide with round joins.
    public let taskOutlines: [GanttTaskStroke: CGPath]
    /// Task text by its color.
    public let taskTexts: [GanttLabelColor: [DiagramTextBlock]]
    /// The sections' names, in the text color.
    public let sectionNames: [DiagramTextBlock]
    /// The axis' dates, in the muted color.
    public let axisDates: [DiagramTextBlock]
    /// The title, drawn bold, or nil.
    public let title: DiagramTextBlock?

    public static let lineWidth: CGFloat = 1
    public static let todayLineWidth: CGFloat = 2
    public static let verticalMarkerLineWidth: CGFloat = 1.5
    public static let verticalMarkerDashLengths: [CGFloat] = [4, 3]
    public static let gridDashLengths: [CGFloat] = [1, 3]
    /// The opacity of an active task's fill.
    public static let faintFillOpacity: CGFloat = 0.25
    /// Half the width of the triangle on top of today's line.
    static let todayMarkHalfWidth: CGFloat = 4
    /// How far above the plot the triangle's top is, and how far into it its point reaches.
    static let todayMarkRise: CGFloat = 5
    static let todayMarkReach: CGFloat = 1

    public init(layout: GanttLayout) {
        title = layout.title
        let paths = GanttDrawingPaths(layout: layout, making: DiagramCoreGraphicsPaths())
        sectionBands = paths.sectionBands.path
        excludedDays = paths.excludedDays.path
        gridLines = paths.gridLines.path
        axisLines = paths.axisLines.path
        todayLine = paths.todayLine.path
        todayLineStyle = layout.plot?.todayStyle
        todayMark = paths.todayMark.path
        verticalMarkerLines = paths.verticalMarkerLines.path
        verticalMarkerTexts = layout.plot?.verticalMarkers.map(\.label) ?? []
        var taskFills: [GanttTaskFill: CGPath] = [:]
        for (index, fill) in Self.taskFillOrder.enumerated() where paths.usedTaskFills[index] { taskFills[fill] = paths.taskFills[index].path }
        self.taskFills = taskFills
        var taskOutlines: [GanttTaskStroke: CGPath] = [:]
        for (index, stroke) in Self.taskStrokeOrder.enumerated() where paths.usedTaskStrokes[index] { taskOutlines[stroke] = paths.taskOutlines[index].path }
        self.taskOutlines = taskOutlines
        let tasks = layout.plot?.tasks ?? []
        taskTexts = Dictionary(grouping: tasks, by: \.labelColor).mapValues { grouped in grouped.map(\.label) }
        sectionNames = layout.plot?.sectionNames ?? []
        axisDates = layout.plot?.axisDates ?? []
    }

    /// A task's outline: a bar with Pele's rounded corners, or a milestone's diamond; nil for a task without one.
    static func outline(of shape: GanttTaskShape) -> CGPath? {
        GanttDrawingPaths.outline(of: shape, making: DiagramCoreGraphicsPaths())?.path
    }
}

/// A Gantt chart's paths, grouped as `GanttDrawingParts` groups them, recorded into the paths a maker makes: Core
/// Graphics paths for the drawing parts, lanes of the thread's scene workspace for the scene, the same elements.
struct GanttDrawingPaths<Path: DiagramPathRecording> {
    let sectionBands: Path
    let excludedDays: Path
    let gridLines: Path
    let axisLines: Path
    let todayLine: Path
    let todayMark: Path
    let verticalMarkerLines: Path
    /// The tasks' shapes by fill, in `GanttDrawingParts.taskFillOrder`, and by outline, in `taskStrokeOrder`, with
    /// whether a task has each.
    let taskFills: [Path]
    let taskOutlines: [Path]
    let usedTaskFills: [Bool]
    let usedTaskStrokes: [Bool]

    init<Maker: DiagramPathMaking>(layout: GanttLayout, making maker: Maker) where Maker.Path == Path {
        let plot = layout.plot
        let frame = plot?.frame ?? .zero
        let gridTop = plot?.gridTop ?? frame.minY
        sectionBands = maker.makePath()
        for band in plot?.sectionBands ?? [] { sectionBands.addRect(band) }
        excludedDays = maker.makePath()
        for days in plot?.excludedDays ?? [] { excludedDays.addRect(days) }
        gridLines = Self.verticalLines(at: plot?.gridLineOffsets ?? [], from: gridTop, to: frame.maxY, making: maker)
        axisLines = maker.makePath()
        if let plot {
            axisLines.move(to: CGPoint(x: frame.minX, y: frame.maxY))
            axisLines.addLine(to: CGPoint(x: frame.maxX, y: frame.maxY))
            if plot.showsTopAxis {
                axisLines.move(to: CGPoint(x: frame.minX, y: gridTop))
                axisLines.addLine(to: CGPoint(x: frame.maxX, y: gridTop))
            }
        }
        let todayOffsets = plot?.todayOffset.map { offset in [offset] } ?? []
        todayLine = Self.verticalLines(at: todayOffsets, from: gridTop, to: frame.maxY, making: maker)
        todayMark = maker.makePath()
        if plot?.todayStyle == nil { for offset in todayOffsets { Self.addTodayMark(at: offset, top: gridTop, to: todayMark, making: maker) } }
        verticalMarkerLines = Self.verticalLines(at: plot?.verticalMarkers.map(\.offset) ?? [], from: gridTop, to: frame.maxY, making: maker)
        let fills = GanttDrawingParts.taskFillOrder.map { _ in maker.makePath() }
        let strokes = GanttDrawingParts.taskStrokeOrder.map { _ in maker.makePath() }
        var usedFills = fills.map { _ in false }
        var usedStrokes = strokes.map { _ in false }
        for task in plot?.tasks ?? [] {
            let madeCount = maker.madePathCount
            defer { maker.givePathsBack(downTo: madeCount) }
            guard let outline = Self.outline(of: task.shape, making: maker),
                  let fillIndex = GanttDrawingParts.taskFillOrder.firstIndex(of: task.paint.fill),
                  let strokeIndex = GanttDrawingParts.taskStrokeOrder.firstIndex(of: task.paint.stroke) else { continue }
            fills[fillIndex].addPath(outline, alsoTo: strokes[strokeIndex])
            usedFills[fillIndex] = true
            usedStrokes[strokeIndex] = true
        }
        (taskFills, taskOutlines, usedTaskFills, usedTaskStrokes) = (fills, strokes, usedFills, usedStrokes)
    }

    /// A task's outline: a bar with Pele's rounded corners, made whole, or a milestone's diamond; nil for a task
    /// without one.
    static func outline<Maker: DiagramPathMaking>(of shape: GanttTaskShape, making maker: Maker) -> Path? where Maker.Path == Path {
        switch shape {
        case .bar(let frame):
            let radius = min(GanttLayoutEngine.barCornerRadius, frame.width / 2, frame.height / 2)
            return maker.roundedRectangle(frame, cornerWidth: radius, cornerHeight: radius)
        case .milestone(let frame):
            let diamond = maker.makePath()
            diamond.addLines(between: [CGPoint(x: frame.midX, y: frame.minY), CGPoint(x: frame.maxX, y: frame.midY), CGPoint(x: frame.midX, y: frame.maxY),
                                       CGPoint(x: frame.minX, y: frame.midY)])
            diamond.closeSubpath()
            return diamond
        case .unscheduled: return nil
        }
    }

    private static func verticalLines<Maker: DiagramPathMaking>(at offsets: [CGFloat], from top: CGFloat, to bottom: CGFloat,
                                                                 making maker: Maker) -> Path where Maker.Path == Path {
        let path = maker.makePath()
        for offset in offsets {
            path.move(to: CGPoint(x: offset, y: top))
            path.addLine(to: CGPoint(x: offset, y: bottom))
        }
        return path
    }

    /// Pele's triangle pointing down onto the top of today's line, added as a path of its own is added.
    private static func addTodayMark<Maker: DiagramPathMaking>(at offset: CGFloat, top: CGFloat, to marks: Path, making maker: Maker)
        where Maker.Path == Path {
        let madeCount = maker.madePathCount
        let mark = maker.makePath()
        let markTop = top - GanttDrawingParts.todayMarkRise
        let halfWidth = GanttDrawingParts.todayMarkHalfWidth
        mark.addLines(between: [CGPoint(x: offset - halfWidth, y: markTop), CGPoint(x: offset + halfWidth, y: markTop),
                                CGPoint(x: offset, y: top + GanttDrawingParts.todayMarkReach)])
        mark.closeSubpath()
        marks.addPath(mark)
        maker.givePathsBack(downTo: madeCount)
    }
}
