/**
 * File: PieChartDrawingParts.swift
 * --------------------------------
 * Layer: Core
 * Description: A laid-out pie chart's geometry grouped by how it is painted, with the paints of its percentages.
 *
 * Authors: felixchvl, Bahey Shalash
 * Version: 0.4
 * Date: 23/11/2026
 */

import CoreGraphics

/// A laid-out pie chart's geometry grouped by how it is painted, so that drawing it in any colors is a few fills and
/// strokes, by Core Graphics (`PieChartRenderer`) or by a view's own shapes. Back to front, as Pele draws: the slices
/// and their edges, the percentages, the legend, the title.
public struct PieChartDrawingParts {
    /// For each series color, the slices and legend swatches filled in it: entry `k` is filled in
    /// `DiagramPalette.seriesColor(at: k)` and holds the slices and swatches whose index leaves `k` when divided by the
    /// number of series colors. As many entries as the chart has slices, up to that number.
    public var seriesFills: [CGPath] { seriesFillsScenePaths.map(\.coreGraphicsPath) }
    let seriesFillsScenePaths: [DiagramScenePath]
    /// The edges of the slices drawn, stroked one point wide in the background color with round joins, so that
    /// neighbouring slices stand apart.
    public var sliceEdges: CGPath { sliceEdgesScenePath.coreGraphicsPath }
    let sliceEdgesScenePath: DiagramScenePath
    /// The pie's circle when no slice is drawn (no slices, or none with a share), stroked one point wide in the border
    /// color; empty otherwise.
    public var emptyPieOutline: CGPath { emptyPieOutlineScenePath.coreGraphicsPath }
    let emptyPieOutlineScenePath: DiagramScenePath
    /// The percentages inside their slices, drawn in the background color.
    public let insidePercentages: [DiagramTextBlock]
    /// The paint of each of `insidePercentages`: the background color, or Pele's ink on its slice's color where the chart's
    /// theme variables set that color (`DiagramSeriesColors.inks`).
    public let insidePercentagePaints: [DiagramPaint]
    /// The percentages outside the rim, drawn in the text color.
    public let outsidePercentages: [DiagramTextBlock]
    /// The legend's labels, drawn in the text color.
    public let legendTexts: [DiagramTextBlock]
    /// The title, drawn bold, or nil.
    public let title: DiagramTextBlock?

    public static let lineWidth: CGFloat = 1
    /// Pele's eight `--pele-series-*` colors, which the slices take in turn.
    public static let seriesColorCount = DiagramPalette.peleSeries.count
    /// The corner radius of a legend swatch.
    static let swatchCornerRadius: CGFloat = 2

    public init(layout: PieChartLayout) {
        // One fill per series colour in use, counted from the slices and the legend: a pie drawn without a legend
        // (legendPosition: none) still paints its slices.
        let seriesCount = (layout.slices.map(\.seriesIndex) + layout.legend.map(\.seriesIndex)).max().map { $0 + 1 } ?? 0
        var fills = (0..<min(seriesCount, Self.seriesColorCount)).map { _ in DiagramScenePath() }
        var edges = DiagramScenePath()
        for slice in layout.slices {
            let wedge = Self.wedge(slice, center: layout.center, radius: layout.radius, innerRadius: layout.innerRadius)
            fills[slice.seriesIndex % Self.seriesColorCount].addPath(wedge)
            edges.addPath(wedge)
        }
        for entry in layout.legend {
            fills[entry.seriesIndex % Self.seriesColorCount].addRoundedRect(in: entry.swatch, cornerWidth: Self.swatchCornerRadius,
                                                                            cornerHeight: Self.swatchCornerRadius)
        }
        seriesFillsScenePaths = fills
        sliceEdgesScenePath = edges
        let pieFrame = CGRect(x: layout.center.x - layout.radius, y: layout.center.y - layout.radius, width: 2 * layout.radius, height: 2 * layout.radius)
        emptyPieOutlineScenePath = layout.slices.isEmpty ? DiagramScenePath(ellipseIn: pieFrame) : DiagramScenePath()
        let insideSlices = layout.slices.filter { slice in slice.percentagePlacement == .insideSlice }
        insidePercentages = insideSlices.map(\.percentage)
        insidePercentagePaints = insideSlices.map { slice in layout.seriesColors.ink(ofSeries: slice.seriesIndex).map(DiagramPaint.color) ?? .background }
        outsidePercentages = layout.slices.filter { slice in slice.percentagePlacement == .outsideRim }.map(\.percentage)
        legendTexts = layout.legend.map(\.text)
        title = layout.title
    }

    /// A slice from the center (or the hole's rim, for a donut) out to the rim and back, or the whole circle (ring) for a
    /// slice that is the whole pie.
    static func wedge(_ slice: PieChartLayoutSlice, center: CGPoint, radius: CGFloat, innerRadius: CGFloat = 0) -> DiagramScenePath {
        var path = DiagramScenePath()
        // Core Graphics measures angles from the x axis toward the y axis, which runs down here: a quarter turn
        // before the top, and with increasing angles, which turn clockwise on this page.
        let start = slice.startAngle - .pi / 2
        let end = slice.isWholePie ? start + 2 * .pi : slice.endAngle - .pi / 2
        guard innerRadius > 0 else {
            guard !slice.isWholePie else {
                return DiagramScenePath(ellipseIn: CGRect(x: center.x - radius, y: center.y - radius, width: 2 * radius, height: 2 * radius))
            }
            path.move(to: center)
            path.addLine(to: PieChartSlicePlacement.point(at: slice.startAngle, distance: radius, from: center))
            path.addArc(center: center, radius: radius, startAngle: start, endAngle: end, clockwise: false)
            path.closeSubpath()
            return path
        }
        // The outer arc one way and the inner one back, so that the hole is left unfilled by the nonzero rule too.
        path.addArc(center: center, radius: radius, startAngle: start, endAngle: end, clockwise: false)
        if slice.isWholePie {
            path.closeSubpath()
            path.move(to: CGPoint(x: center.x + innerRadius * cos(end), y: center.y + innerRadius * sin(end)))
        }
        path.addArc(center: center, radius: innerRadius, startAngle: end, endAngle: start, clockwise: true)
        path.closeSubpath()
        return path
    }
}
