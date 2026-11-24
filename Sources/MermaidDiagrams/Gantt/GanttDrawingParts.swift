/**
 * File: GanttDrawingParts.swift
 * -----------------------------
 * Layer: Core
 * Description: A laid-out Gantt chart's geometry grouped by how it is painted.
 *
 * Authors: felixchvl, Bahey Shalash
 * Version: 0.2
 * Date: 23/11/2026
 */

import CoreGraphics

/// A laid-out Gantt chart's geometry grouped by how it is painted, so that drawing it in any colors is a few fills and
/// strokes, by Core Graphics (`GanttRenderer`) or by a view's own shapes. Back to front, as Pele draws: the section
/// bands, the excluded days, the grid and the axis' line, today's line, the tasks' shapes, then the text.
public struct GanttDrawingParts {
    /// The bands behind every other section, filled in the surface color.
    public var sectionBands: CGPath { sectionBandsScenePath.coreGraphicsPath }
    let sectionBandsScenePath: DiagramScenePath
    /// The runs of excluded days, filled in the alternate surface color.
    public var excludedDays: CGPath { excludedDaysScenePath.coreGraphicsPath }
    let excludedDaysScenePath: DiagramScenePath
    /// The grid lines at the axis' dates, stroked one point wide in dots of 1 and gaps of 3, in the border color.
    public var gridLines: CGPath { gridLinesScenePath.coreGraphicsPath }
    let gridLinesScenePath: DiagramScenePath
    /// The axis' line under the rows, and above them with `topAxis`, stroked one point wide in the border color.
    public var axisLines: CGPath { axisLinesScenePath.coreGraphicsPath }
    let axisLinesScenePath: DiagramScenePath
    /// Today's line, stroked two points wide in the accent color (or as `todayLineStyle` says); empty when it is not drawn.
    public var todayLine: CGPath { todayLineScenePath.coreGraphicsPath }
    let todayLineScenePath: DiagramScenePath
    /// How `todayMarker` restyles today's line, or nil for the standard line.
    public let todayLineStyle: GanttTodayLineStyle?
    /// The small triangle on top of today's line, filled in the accent color; empty for a restyled line.
    public var todayMark: CGPath { todayMarkScenePath.coreGraphicsPath }
    let todayMarkScenePath: DiagramScenePath
    /// The vertical markers' lines, stroked 1.5 points wide in dashes of 4 and gaps of 3, in the line color.
    public var verticalMarkerLines: CGPath { verticalMarkerLinesScenePath.coreGraphicsPath }
    let verticalMarkerLinesScenePath: DiagramScenePath
    /// The vertical markers' texts under the axis, in the text color.
    public let verticalMarkerTexts: [DiagramTextBlock]
    /// The tasks' bars and milestones, by fill; a faint fill is its color at a quarter of its opacity.
    public var taskFills: [GanttTaskFill: CGPath] { taskFillsScenePaths.mapValues(\.coreGraphicsPath) }
    let taskFillsScenePaths: [GanttTaskFill: DiagramScenePath]
    /// The tasks' bars and milestones, by outline color, stroked one point wide with round joins.
    public var taskOutlines: [GanttTaskStroke: CGPath] { taskOutlinesScenePaths.mapValues(\.coreGraphicsPath) }
    let taskOutlinesScenePaths: [GanttTaskStroke: DiagramScenePath]
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
        let frame = layout.plot?.frame ?? .zero
        let todayOffsets = layout.plot?.todayOffset.map { offset in [offset] } ?? []
        sectionBandsScenePath = Self.rectangles(layout.plot?.sectionBands ?? [])
        excludedDaysScenePath = Self.rectangles(layout.plot?.excludedDays ?? [])
        let gridTop = layout.plot?.gridTop ?? frame.minY
        gridLinesScenePath = Self.verticalLines(at: layout.plot?.gridLineOffsets ?? [], from: gridTop, to: frame.maxY)
        var axes = DiagramScenePath()
        let axisHeights = layout.plot.map { plot in [frame.maxY] + (plot.showsTopAxis ? [gridTop] : []) } ?? []
        for height in axisHeights {
            axes.move(to: CGPoint(x: frame.minX, y: height))
            axes.addLine(to: CGPoint(x: frame.maxX, y: height))
        }
        axisLinesScenePath = axes
        todayLineScenePath = Self.verticalLines(at: todayOffsets, from: gridTop, to: frame.maxY)
        todayLineStyle = layout.plot?.todayStyle
        var mark = DiagramScenePath()
        if layout.plot?.todayStyle == nil { for offset in todayOffsets { mark.addPath(Self.todayMark(at: offset, top: gridTop)) } }
        todayMarkScenePath = mark
        verticalMarkerLinesScenePath = Self.verticalLines(at: layout.plot?.verticalMarkers.map(\.offset) ?? [], from: gridTop, to: frame.maxY)
        verticalMarkerTexts = layout.plot?.verticalMarkers.map(\.label) ?? []
        let tasks = layout.plot?.tasks ?? []
        (taskFillsScenePaths, taskOutlinesScenePaths) = Self.taskShapes(tasks)
        taskTexts = Dictionary(grouping: tasks, by: \.labelColor).mapValues { grouped in grouped.map(\.label) }
        sectionNames = layout.plot?.sectionNames ?? []
        axisDates = layout.plot?.axisDates ?? []
    }

    /// A task's outline: a bar with Pele's rounded corners, or a milestone's diamond; nil for a task without one.
    static func outline(of shape: GanttTaskShape) -> DiagramScenePath? {
        switch shape {
        case .bar(let frame):
            let radius = min(GanttLayoutEngine.barCornerRadius, frame.width / 2, frame.height / 2)
            return DiagramScenePath(roundedRect: frame, cornerWidth: radius, cornerHeight: radius)
        case .milestone(let frame):
            var diamond = DiagramScenePath()
            diamond.addLines(between: [CGPoint(x: frame.midX, y: frame.minY), CGPoint(x: frame.maxX, y: frame.midY), CGPoint(x: frame.midX, y: frame.maxY),
                                       CGPoint(x: frame.minX, y: frame.midY)])
            diamond.closeSubpath()
            return diamond
        case .unscheduled: return nil
        }
    }

    private static func taskShapes(_ tasks: [GanttLayoutTask]) -> ([GanttTaskFill: DiagramScenePath], [GanttTaskStroke: DiagramScenePath]) {
        var fills: [GanttTaskFill: DiagramScenePath] = [:]
        var outlines: [GanttTaskStroke: DiagramScenePath] = [:]
        for task in tasks {
            guard let outline = outline(of: task.shape) else { continue }
            fills[task.paint.fill, default: DiagramScenePath()].addPath(outline)
            outlines[task.paint.stroke, default: DiagramScenePath()].addPath(outline)
        }
        return (fills, outlines)
    }

    private static func rectangles(_ frames: [CGRect]) -> DiagramScenePath {
        var path = DiagramScenePath()
        path.addRects(frames)
        return path
    }

    private static func verticalLines(at offsets: [CGFloat], from top: CGFloat, to bottom: CGFloat) -> DiagramScenePath {
        var path = DiagramScenePath()
        for offset in offsets {
            path.move(to: CGPoint(x: offset, y: top))
            path.addLine(to: CGPoint(x: offset, y: bottom))
        }
        return path
    }

    /// Pele's triangle pointing down onto the top of today's line.
    private static func todayMark(at offset: CGFloat, top: CGFloat) -> DiagramScenePath {
        var mark = DiagramScenePath()
        let markTop = top - todayMarkRise
        mark.addLines(between: [CGPoint(x: offset - todayMarkHalfWidth, y: markTop), CGPoint(x: offset + todayMarkHalfWidth, y: markTop),
                                CGPoint(x: offset, y: top + todayMarkReach)])
        mark.closeSubpath()
        return mark
    }
}
