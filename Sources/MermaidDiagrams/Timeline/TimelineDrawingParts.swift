/**
 * File: TimelineDrawingParts.swift
 * --------------------------------
 * Layer: Core
 * Description: A laid-out timeline's geometry grouped by how it is painted, with the paints of its sections' and
 *              periods' text.
 *
 * Authors: felixchvl, Bahey Shalash
 * Version: 0.4
 * Date: 25/11/2026
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
        sectionTexts = layout.sections.map(\.text)
        periodTexts = layout.periods.map(\.text)
        sectionTextPaints = layout.sections.map { section in Self.ink(.series(section.sectionIndex), of: layout) }
        periodTextPaints = layout.periods.map { period in Self.ink(period.color, of: layout) }
        eventTexts = layout.periods.flatMap { period in period.events.map(\.text) }
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
        var groups: [ColorGroup] = []
        groups.reserveCapacity(seriesCount + 1)
        for index in 0..<seriesCount {
            groups.append(ColorGroup(color: .series(index), boxes: maker.makePath(), eventBoxes: maker.makePath(), dots: maker.makePath()))
        }
        groups.append(ColorGroup(color: .muted, boxes: maker.makePath(), eventBoxes: maker.makePath(), dots: maker.makePath()))
        func group(for color: TimelineColor) -> ColorGroup {
            switch color {
            case .series(let index): groups[index % seriesCount]
            case .muted: groups[seriesCount]
            }
        }
        let radius = TimelineDrawingParts.boxCornerRadius
        for section in layout.sections {
            Self.addBox(section.frame, to: group(for: .series(section.sectionIndex)).boxes, radius: radius, making: maker)
        }
        connectors = maker.makePath()
        let dotRadius = TimelineDrawingParts.dotRadius
        for period in layout.periods {
            let paths = group(for: period.color)
            Self.addBox(period.frame, to: paths.boxes, radius: radius, making: maker)
            for event in period.events { Self.addBox(event.frame, to: paths.eventBoxes, radius: radius, making: maker) }
            paths.dots.addEllipse(in: CGRect(x: period.dot.x - dotRadius, y: period.dot.y - dotRadius, width: 2 * dotRadius, height: 2 * dotRadius))
            for connector in period.connectors { maker.addEdgeLineInPlace(connector, to: connectors) }
        }
        colorGroups = groups.filter { group in !(group.boxes.isEmpty && group.dots.isEmpty) }
        axis = maker.makePath()
        if let line = layout.axis { DiagramEdgeDrawing.record(line, into: axis) }
        axisArrow = maker.makePath()
        if let mark = layout.axisArrow { DiagramEdgeDrawing.addMark(mark, filled: axisArrow, stroked: maker.makePath()) }
    }

    /// Adds `CGPath(roundedRect:)` of `frame` to `paths`, as a box is added.
    private static func addBox<Maker: DiagramPathMaking>(_ frame: CGRect, to paths: Path, radius: CGFloat, making maker: Maker) where Maker.Path == Path {
        let madeCount = maker.madePathCount
        paths.addPath(maker.roundedRectangle(frame, cornerWidth: radius, cornerHeight: radius))
        maker.givePathsBack(downTo: madeCount)
    }
}
