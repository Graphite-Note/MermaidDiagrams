/**
 * File: TimelineDrawingParts.swift
 * --------------------------------
 * Layer: Core
 * Description: A laid-out timeline's geometry grouped by how it is painted, with the paints of its sections' and
 *              periods' text.
 *
 * Authors: felixchvl, Bahey Shalash
 * Version: 0.3
 * Date: 23/11/2026
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
        public var boxes: CGPath { boxesScenePath.coreGraphicsPath }
        let boxesScenePath: DiagramScenePath
        /// Event boxes, filled with the color at `eventFillOpacity`.
        public var eventBoxes: CGPath { eventBoxesScenePath.coreGraphicsPath }
        let eventBoxesScenePath: DiagramScenePath
        /// The dots on the axis, filled in the color and outlined `dotOutlineWidth` wide in the background color.
        public var dots: CGPath { dotsScenePath.coreGraphicsPath }
        let dotsScenePath: DiagramScenePath
    }

    public let colorGroups: [ColorGroup]
    /// The axis, stroked `lineWidth` wide in the line color.
    public var axis: CGPath { axisScenePath.coreGraphicsPath }
    let axisScenePath: DiagramScenePath
    /// The axis's arrow, filled in the line color.
    public var axisArrow: CGPath { axisArrowScenePath.coreGraphicsPath }
    let axisArrowScenePath: DiagramScenePath
    /// The lines from periods to the axis and on to their events, stroked `lineWidth` wide in the border color.
    public var connectors: CGPath { connectorsScenePath.coreGraphicsPath }
    let connectorsScenePath: DiagramScenePath
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
        let groups = ColorGroups()
        for section in layout.sections { groups.paths(for: .series(section.sectionIndex)).boxes.addPathOfRoundedRect(section.frame, cornerWidth: Self.boxCornerRadius, cornerHeight: Self.boxCornerRadius) }
        var connectors = DiagramScenePath()
        for period in layout.periods {
            let paths = groups.paths(for: period.color)
            paths.boxes.addPathOfRoundedRect(period.frame, cornerWidth: Self.boxCornerRadius, cornerHeight: Self.boxCornerRadius)
            for event in period.events { paths.eventBoxes.addPathOfRoundedRect(event.frame, cornerWidth: Self.boxCornerRadius, cornerHeight: Self.boxCornerRadius) }
            paths.dots.addEllipse(in: CGRect(x: period.dot.x - Self.dotRadius, y: period.dot.y - Self.dotRadius, width: 2 * Self.dotRadius,
                                             height: 2 * Self.dotRadius))
            for connector in period.connectors { connectors.addEdgePath(connector) }
        }
        colorGroups = groups.drawn
        axisScenePath = layout.axis.map(DiagramEdgeDrawing.path) ?? DiagramScenePath()
        var arrow = DiagramScenePath()
        if let axisArrow = layout.axisArrow { DiagramEdgeDrawing.addMark(axisArrow, filled: &arrow) }
        axisArrowScenePath = arrow
        self.connectorsScenePath = connectors
        sectionTexts = layout.sections.map(\.text)
        periodTexts = layout.periods.map(\.text)
        func ink(_ color: TimelineColor) -> DiagramPaint {
            guard case .series(let index) = color, let ink = layout.seriesColors.ink(ofSeries: index) else { return .background }
            return .color(ink)
        }
        sectionTextPaints = layout.sections.map { section in ink(.series(section.sectionIndex)) }
        periodTextPaints = layout.periods.map { period in ink(period.color) }
        eventTexts = layout.periods.flatMap { period in period.events.map(\.text) }
        title = layout.title
    }

    private static func box(_ frame: CGRect) -> DiagramScenePath {
        DiagramScenePath(roundedRect: frame, cornerWidth: boxCornerRadius, cornerHeight: boxCornerRadius)
    }

    /// The paths of each color: one per series color, the series counted again after the eighth, and the muted color.
    private struct ColorGroups {
        private let series = DiagramPalette.peleSeries.indices.map { _ in GroupPaths() }
        private let muted = GroupPaths()

        func paths(for color: TimelineColor) -> GroupPaths {
            switch color {
            case .series(let index): series[index % series.count]
            case .muted: muted
            }
        }

        var drawn: [ColorGroup] {
            let all = series.enumerated().map { index, paths in (TimelineColor.series(index), paths) } + [(TimelineColor.muted, muted)]
            return all.compactMap { color, paths in
                paths.boxes.isEmpty && paths.dots.isEmpty ? nil : ColorGroup(color: color, boxesScenePath: paths.boxes, eventBoxesScenePath: paths.eventBoxes, dotsScenePath: paths.dots)
            }
        }
    }

    /// The paths of one color, which every use of the color adds to.
    private final class GroupPaths {
        var boxes = DiagramScenePath()
        var eventBoxes = DiagramScenePath()
        var dots = DiagramScenePath()
    }
}
