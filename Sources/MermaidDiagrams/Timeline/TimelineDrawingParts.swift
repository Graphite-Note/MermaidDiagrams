/**
 * File: TimelineDrawingParts.swift
 * --------------------------------
 * Layer: Core
 * Description: A laid-out timeline's geometry grouped by how it is painted, with the paints of its sections' and
 *              periods' text.
 *
 * Authors: felixchvl, Bahey Shalash
 * Version: 0.5
 * Date: 26/11/2026
 */

import CoreGraphics

/// A laid-out timeline's geometry grouped by how it is painted, so that drawing it in any colors is a few fills and
/// strokes per color, by Core Graphics (`TimelineRenderer`) or by a view's own shapes. Back to front: the axis and
/// its arrow, the lines to the events, then per color the section and period boxes, the event boxes and the dots,
/// then the text and the title.
public struct TimelineDrawingParts {
    /// The boxes and dots painted in one color: a series color, the colors taken in turn after
    /// `DiagramPalette.peleSeries.count`, or the muted color.
    public struct ColorGroup {
        public let color: TimelineColor
        /// Section headings and period boxes, filled in the color.
        public let boxes: CGPath
        /// Event boxes, filled with the color at `eventFillOpacity`.
        public let eventBoxes: CGPath
        /// The dots on the axis, filled in the color and outlined `dotOutlineWidth` wide in the background color.
        public let dots: CGPath
    }

    public let colorGroups: [ColorGroup]
    /// The axis, stroked `lineWidth` wide in the line color.
    public let axis: CGPath
    /// The axis's arrow, filled in the line color.
    public let axisArrow: CGPath
    /// The lines from periods to the axis and on to their events, stroked `lineWidth` wide in the border color.
    public let connectors: CGPath
    /// Section headings' text, bold, and periods' text, on their boxes in the background color.
    public let sectionTexts: [DiagramTextBlock]
    public let periodTexts: [DiagramTextBlock]
    /// The paints of `sectionTexts` and `periodTexts`: the background color, or Pele's ink on their box's series color
    /// where the timeline's theme variables set that color (`DiagramSeriesColors.inks`).
    public let sectionTextPaints: [DiagramPaint]
    public let periodTextPaints: [DiagramPaint]
    /// Events' text, in the foreground color.
    public let eventTexts: [DiagramTextBlock]
    /// The title, drawn bold, or nil.
    public let title: DiagramTextBlock?

    public static let lineWidth: CGFloat = 1
    public static let dotOutlineWidth: CGFloat = 2
    /// How much of its period's color an event's box takes, over the background: Pele's tint.
    public static let eventFillOpacity: CGFloat = 0.16
    /// The corner radius of every box: Pele's `--pele-radius`.
    static let boxCornerRadius: CGFloat = 4
    static let dotRadius: CGFloat = 4

    public init(layout: TimelineLayout) {
        let paths = TimelineDrawingPaths(layout: layout, making: DiagramCoreGraphicsPaths())
        colorGroups = paths.colorGroups.map { group in
            ColorGroup(color: group.color, boxes: group.boxes.path, eventBoxes: group.eventBoxes.path, dots: group.dots.path)
        }
        axis = paths.axis.path
        axisArrow = paths.axisArrow.path
        connectors = paths.connectors.path
        let sections = layout.sections
        let periods = layout.periods
        sectionTexts = sections.map(\.text)
        periodTexts = periods.map(\.text)
        sectionTextPaints = sections.map { section in Self.ink(.series(section.sectionIndex), of: layout) }
        periodTextPaints = periods.map { period in Self.ink(period.color, of: layout) }
        eventTexts = periods.flatMap { period in period.events.map(\.text) }
        title = layout.title
    }

    /// The paint of text on a box of `color`: the background color, or the ink the theme sets on that series color.
    static func ink(_ color: TimelineColor, of layout: TimelineLayout) -> DiagramPaint {
        guard case .series(let index) = color, let ink = layout.seriesColors.ink(ofSeries: index) else { return .background }
        return .color(ink)
    }
}

/// A timeline's paths, grouped as `TimelineDrawingParts` groups them, recorded into the paths a maker makes: Core
/// Graphics paths for the drawing parts, lanes of the thread's scene workspace for the scene. Both record the same
/// elements, bit for bit.
struct TimelineDrawingPaths<Path: DiagramPathRecording> {
    struct ColorGroup {
        let color: TimelineColor
        let boxes: Path
        let eventBoxes: Path
        let dots: Path
    }

    /// The groups with a box or a dot: the series colors in order, then the muted color.
    let colorGroups: [ColorGroup]
    let axis: Path
    let axisArrow: Path
    let connectors: Path

    init<Maker: DiagramPathMaking>(layout: TimelineLayout, making maker: Maker) where Maker.Path == Path {
        let seriesCount = DiagramPalette.peleSeries.count
        // A color's paths are made when its first box is added: a timeline paints a few of the nine colors.
        var groups: [ColorGroup?] = Array(repeating: nil, count: seriesCount + 1)
        func group(for color: TimelineColor) -> ColorGroup {
            let index: Int
            switch color {
            case .series(let series): index = series % seriesCount
            case .muted: index = seriesCount
            }
            if let made = groups[index] { return made }
            let made = ColorGroup(color: index == seriesCount ? .muted : .series(index), boxes: maker.makePath(), eventBoxes: maker.makePath(),
                                  dots: maker.makePath())
            groups[index] = made
            return made
        }
        let radius = TimelineDrawingParts.boxCornerRadius
        let body = layout.body
        for section in body.sections {
            Self.addBox(section.frame, to: group(for: .series(section.sectionIndex)).boxes, radius: radius, making: maker)
        }
        connectors = maker.makePath()
        let dotRadius = TimelineDrawingParts.dotRadius
        for period in body.periods {
            let paths = group(for: period.color)
            Self.addBox(period.frame, to: paths.boxes, radius: radius, making: maker)
            for event in body.events[period.eventIndices] { Self.addBox(event.frame, to: paths.eventBoxes, radius: radius, making: maker) }
            paths.dots.addEllipse(in: CGRect(x: period.dot.x - dotRadius, y: period.dot.y - dotRadius, width: 2 * dotRadius, height: 2 * dotRadius))
            for connector in body.connectors[period.connectorIndices] {
                Self.addConnector(body.connectorPoints[connector.pointIndices], to: connectors, making: maker)
            }
        }
        colorGroups = groups.compactMap { group in group.flatMap { group in group.boxes.isEmpty && group.dots.isEmpty ? nil : group } }
        axis = maker.makePath()
        if let line = layout.axis { DiagramEdgeDrawing.record(line, into: axis) }
        axisArrow = maker.makePath()
        if let mark = layout.axisArrow { DiagramEdgeDrawing.addMark(mark, filled: axisArrow, stroked: maker.makePath()) }
    }

    /// A connector's straight line through `points`, as `addEdgeLineInPlace` adds its path: recorded straight into a lane
    /// that does not end with a move, else through a path of its own.
    private static func addConnector<Maker: DiagramPathMaking>(_ points: ArraySlice<CGPoint>, to path: Path, making maker: Maker) where Maker.Path == Path {
        if let lane = path as? DiagramPathLane, lane.state.pointee.lastVerb != .move {
            lane.move(to: points[points.startIndex])
            for point in points.dropFirst() { lane.addLine(to: point) }
            return
        }
        maker.addEdgeLine(DiagramPath(start: points[points.startIndex], segments: points.dropFirst().map { point in .line(to: point) }), to: path)
    }

    /// Adds `CGPath(roundedRect:)` of `frame` to `paths`, as a box is added.
    private static func addBox<Maker: DiagramPathMaking>(_ frame: CGRect, to paths: Path, radius: CGFloat, making maker: Maker) where Maker.Path == Path {
        let madeCount = maker.madePathCount
        paths.addPath(maker.roundedRectangle(frame, cornerWidth: radius, cornerHeight: radius))
        maker.givePathsBack(downTo: madeCount)
    }
}
