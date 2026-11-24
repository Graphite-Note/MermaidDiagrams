/**
 * File: XYChartDrawingParts.swift
 * -------------------------------
 * Layer: Core
 * Description: A laid-out XY chart's geometry grouped by how it is painted.
 *
 * Authors: felixchvl, Bahey Shalash
 * Version: 0.2
 * Date: 23/11/2026
 */

import CoreGraphics

/// A laid-out XY chart's geometry grouped by how it is painted, so that drawing it in any colors is a few fills and
/// strokes, by Core Graphics (`XYChartRenderer`) or by a view's own shapes. Back to front, as Pele draws: the grid,
/// the bars, the lines with their dots, the axes, then the text.
public struct XYChartDrawingParts {
    /// The grid lines, stroked `lineWidth` wide in the alternate surface color.
    public var gridLines: CGPath { gridLinesScenePath.coreGraphicsPath }
    let gridLinesScenePath: DiagramScenePath
    /// For each series color, the bars and the legend's bar swatches filled in it: entry `k` is filled in
    /// `DiagramPalette.seriesColor(at: k)` and holds those of the series whose index leaves `k` when divided by the
    /// number of series colors.
    public var barFills: [CGPath] { barFillsScenePaths.map(\.coreGraphicsPath) }
    let barFillsScenePaths: [DiagramScenePath]
    /// Each line series in the order it is written, drawn over the bars.
    public let lines: [XYChartLineDrawing]
    /// The axes, their ticks and the line bars stand on, stroked `lineWidth` wide in the border color.
    public var axisLines: CGPath { axisLinesScenePath.coreGraphicsPath }
    let axisLinesScenePath: DiagramScenePath
    /// The marks' labels, in the muted color.
    public let axisLabels: [DiagramTextBlock]
    /// The bottom axis' title, the bars' values, the point labels and the legend's titles, in the text color.
    public let texts: [DiagramTextBlock]
    /// The left axis' title, in the text color, turned a quarter turn counterclockwise about its center; or nil.
    public let turnedText: DiagramTextBlock?
    /// The chart's title, drawn bold in the text color, or nil.
    public let title: DiagramTextBlock?

    public static let lineWidth: CGFloat = 1
    /// The width of a line series' line and of its legend swatch, drawn with round caps and joins.
    public static let seriesLineWidth: CGFloat = 2
    public static let dotRadius: CGFloat = 3
    /// The corner radius of a bar's legend swatch.
    static let swatchCornerRadius: CGFloat = 2
    /// Pele's eight `--pele-series-*` colors, which the series take in turn.
    public static let seriesColorCount = DiagramPalette.peleSeries.count

    public init(layout: XYChartLayout) {
        gridLinesScenePath = Self.path(of: layout.gridLines)
        axisLinesScenePath = Self.path(of: layout.axisLines)
        let barSwatches = layout.legend.filter { entry in entry.kind == .bar }
        let colorCount = min(Self.seriesColorCount, ((layout.bars.map(\.seriesIndex) + barSwatches.map(\.seriesIndex)).max() ?? -1) + 1)
        var fills = (0..<colorCount).map { _ in DiagramScenePath() }
        for bar in layout.bars { fills[bar.seriesIndex % Self.seriesColorCount].addRect(bar.frame) }
        for entry in barSwatches {
            fills[entry.seriesIndex % Self.seriesColorCount].addRoundedRect(in: entry.swatch, cornerWidth: Self.swatchCornerRadius,
                                                                            cornerHeight: Self.swatchCornerRadius)
        }
        barFillsScenePaths = fills
        lines = layout.lines.map { line in
            XYChartLineDrawing(line: line, swatches: layout.legend.filter { entry in entry.kind == .line && entry.seriesIndex == line.seriesIndex })
        }
        axisLabels = layout.axisLabels
        texts = [layout.bottomAxisTitle].compactMap { title in title } + layout.barValues + layout.pointLabels + layout.legend.map(\.text)
        turnedText = layout.leftAxisTitle
        title = layout.title
    }

    private static func path(of segments: [XYChartSegment]) -> DiagramScenePath {
        var path = DiagramScenePath()
        for segment in segments {
            path.move(to: segment.start)
            path.addLine(to: segment.end)
        }
        return path
    }
}

/// A line series' line, with its legend swatch, stroked `XYChartDrawingParts.seriesLineWidth` wide with round caps
/// and joins in its series color, and its dots filled in the same color.
public struct XYChartLineDrawing {
    public let seriesIndex: Int
    public var stroke: CGPath { strokeScenePath.coreGraphicsPath }
    let strokeScenePath: DiagramScenePath
    public var dots: CGPath { dotsScenePath.coreGraphicsPath }
    let dotsScenePath: DiagramScenePath
    init(line: XYChartLine, swatches: [XYChartLegendEntry]) {
        seriesIndex = line.seriesIndex
        var stroke = DiagramScenePath()
        for run in line.runs where !run.isEmpty { stroke.addLines(between: run) }
        for swatch in swatches {
            stroke.move(to: CGPoint(x: swatch.swatch.minX, y: swatch.swatch.midY))
            stroke.addLine(to: CGPoint(x: swatch.swatch.maxX, y: swatch.swatch.midY))
        }
        self.strokeScenePath = stroke
        var dots = DiagramScenePath()
        let radius = XYChartDrawingParts.dotRadius
        for dot in line.dots { dots.addEllipse(in: CGRect(x: dot.x - radius, y: dot.y - radius, width: 2 * radius, height: 2 * radius)) }
        self.dotsScenePath = dots
    }
}
