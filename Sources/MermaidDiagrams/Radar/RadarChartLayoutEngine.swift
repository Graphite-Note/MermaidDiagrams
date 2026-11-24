/**
 * File: RadarChartLayoutEngine.swift
 * ----------------------------------
 * Layer: Core
 * Description: Lays a radar chart out with Pele's measurements, and narrower, its legend below it, for a container too
 *              narrow for it, as Pele fits one to its width.
 *
 * Authors: Bahey Shalash
 * Version: 0.3
 * Date: 24/11/2026
 */

import CoreGraphics

/// Lays a radar chart out in Pele's style: a circle 320 points across (`width` and `height`), its axes evenly spaced from
/// the top clockwise, five rings, each curve a closed curve through its values scaled between `min` and `max`, each axis's
/// label hanging off its spoke away from the center at 1.05 times the radius and six points more, the legend of 12-point
/// swatches in rows of 26 points 24 points right of everything else, the title in bold above, 16 points of margin around
/// the chart and 8 of page. Labels and the legend are in seven eighths of the text's size.
public enum RadarChartLayoutEngine {
    /// Around the whole diagram.
    static let padding: CGFloat = 8
    /// Between the title and the chart.
    static let titleGap: CGFloat = 8
    static let swatchSide: CGFloat = 12
    static let legendRowHeight: CGFloat = 26
    /// Between the chart and the legend.
    static let legendGap: CGFloat = 24
    /// Between a swatch and its label.
    static let swatchTextGap: CGFloat = 8
    /// Between a label and its spoke's end, on top of the factor.
    static let labelOffset: CGFloat = 6
    /// A label is moved over by half its size on the side its spoke leans to, beyond this much of a lean.
    static let leanThreshold: CGFloat = 0.01
    static let wrappingWidth: CGFloat = 4_000

    /// The narrowest a radar chart's circle is made for a narrow container (Pele's `least`).
    static let narrowestChartWidth: CGFloat = 160

    public static func layout(_ chart: RadarChart, typography: DiagramTypography) -> RadarChartLayout {
        layout(chart, typography: typography, availableWidth: nil)
    }

    /// The chart for a container `availableWidth` wide (nil for none), as Pele's `fitWidth` draws it: at its own size when
    /// it fits; else with its legend below the chart and its circle's box narrower by what the page overflows (its height
    /// in proportion), drawn again up to three times, not under 160 points; the title wrapped to the container.
    public static func layout(_ chart: RadarChart, typography: DiagramTypography, availableWidth: CGFloat?) -> RadarChartLayout {
        let natural = chart.appearance.width
        return DiagramWidthFitting.fitWidth(availableWidth: availableWidth, natural: natural, least: narrowestChartWidth,
                                            width: { (layout: RadarChartLayout) in layout.size.width }) { width, isTight in
            let geometry = RadarChartGeometry(chart: chart, width: width, height: chart.appearance.height * width / natural)
            return layout(chart, geometry: geometry, text: typography.nodeText, smallText: typography.edgeText, boldText: typography.boldNodeText,
                          font: typography.font, isTight: isTight, titleRoom: DiagramWidthFitting.titleRoom(availableWidth: availableWidth))
        }
    }

    static func layout<Measurer: DiagramTextMeasuring>(_ chart: RadarChart, text: Measurer, smallText: Measurer, boldText: Measurer,
                                                       font: DiagramFont) -> RadarChartLayout {
        layout(chart, geometry: RadarChartGeometry(chart: chart), text: text, smallText: smallText, boldText: boldText, font: font, isTight: false,
               titleRoom: wrappingWidth)
    }

    /// The chart with `geometry`; `isTight` (it did not fit its container with its legend beside it) puts the legend
    /// below the chart, centered on it, half the legend's gap under everything else; the title wraps at `titleRoom`.
    static func layout<Measurer: DiagramTextMeasuring>(_ chart: RadarChart, geometry: RadarChartGeometry, text: Measurer, smallText: Measurer,
                                                       boldText: Measurer, font: DiagramFont, isTight: Bool, titleRoom: CGFloat) -> RadarChartLayout {
        // The chart is laid out around its own origin, and put on the page at the end.
        var extent = geometry.frameWithMargins
        let labels = zip(chart.axes, geometry.axisDirections).map { axis, direction in
            axisLabel(axis.label, direction: direction, distance: geometry.labelDistance, measurer: smallText)
        }
        for label in labels { extent = extent.union(label.frame) }
        let legendTexts = chart.options.showsLegend
            ? chart.curves.map { curve in DiagramTextBlock(label: curve.label, measurer: smallText, maximumWidth: wrappingWidth) } : []
        let legendWidth = swatchSide + swatchTextGap + (legendTexts.map(\.size.width).max() ?? 0)
        let legendOrigin = isTight ? CGPoint(x: -legendWidth / 2, y: extent.maxY + legendGap / 2)
            : CGPoint(x: extent.maxX + legendGap, y: -CGFloat(legendTexts.count) * legendRowHeight / 2)
        // Below the chart the legend is centered on the origin, so it widens the page evenly on both sides, as Pele's does.
        if !legendTexts.isEmpty { extent = extent.union(legendFrame(of: legendTexts, at: legendOrigin)) }
        let title = chart.title.map { title in
            DiagramTextBlock(label: DiagramLabelDecoder.label(from: title, form: .plain), measurer: boldText, maximumWidth: titleRoom)
        }.flatMap { block in block.lineCount == 0 ? nil : block }
        let titleHeight = title.map { title in title.size.height + titleGap } ?? 0
        let bodyWidth = max(extent.width, title?.size.width ?? 0)
        let pageSize = CGSize(width: (bodyWidth + 2 * padding).rounded(.up), height: (extent.height + titleHeight + 2 * padding).rounded(.up))
        let shift = CGVector(dx: padding + (bodyWidth - extent.width) / 2 - extent.minX, dy: padding + titleHeight - extent.minY)
        var placedTitle = title
        placedTitle?.center = CGPoint(x: pageSize.width / 2, y: padding + (title?.size.height ?? 0) / 2)
        var layout = RadarChartLayout(size: pageSize, font: font, center: CGPoint(x: shift.dx, y: shift.dy), radius: geometry.radius, ringRadii: geometry.ringRadii,
                                      graticule: chart.options.graticule, axisDirections: geometry.axisDirections, spokeLength: geometry.spokeLength,
                                      axisLabels: labels.map { label in label.translated(by: shift) },
                                      curves: geometry.curves.map { curve in curve.translated(by: shift) },
                                      legend: legend(legendTexts, at: legendOrigin.applying(CGAffineTransform(translationX: shift.dx, y: shift.dy))),
                                      title: placedTitle)
        layout.seriesColors = chart.seriesColors
        return layout
    }

    /// An axis's label centered on the point `distance` from the origin along `direction`, then moved out by half its size
    /// on the side the direction leans to, so that it hangs off the spoke away from the center.
    private static func axisLabel(_ label: DiagramLabel, direction: CGPoint, distance: CGFloat, measurer: some DiagramTextMeasuring) -> DiagramTextBlock {
        var block = DiagramTextBlock(label: label, measurer: measurer, maximumWidth: wrappingWidth)
        let size = block.size
        func lean(_ component: CGFloat, _ extent: CGFloat) -> CGFloat {
            component > leanThreshold ? extent / 2 : (component < -leanThreshold ? -extent / 2 : 0)
        }
        block.center = CGPoint(x: direction.x * distance + lean(direction.x, size.width), y: direction.y * distance + lean(direction.y, size.height))
        return block
    }

    /// The legend's frame: its swatches and the widest of its labels, one row of `legendRowHeight` per entry.
    private static func legendFrame(of texts: [DiagramTextBlock], at origin: CGPoint) -> CGRect {
        CGRect(x: origin.x, y: origin.y, width: swatchSide + swatchTextGap + (texts.map(\.size.width).max() ?? 0),
               height: CGFloat(texts.count) * legendRowHeight)
    }

    /// One row per text from `origin` down, each swatch centered on its row and the label after it.
    private static func legend(_ texts: [DiagramTextBlock], at origin: CGPoint) -> [RadarLegendEntry] {
        texts.enumerated().map { index, text in
            let rowMiddle = origin.y + CGFloat(index) * legendRowHeight + legendRowHeight / 2
            var placed = text
            placed.center = CGPoint(x: origin.x + swatchSide + swatchTextGap + text.size.width / 2, y: rowMiddle)
            return RadarLegendEntry(seriesIndex: index, swatch: CGRect(x: origin.x, y: rowMiddle - swatchSide / 2, width: swatchSide, height: swatchSide),
                                    text: placed)
        }
    }
}

extension RadarLayoutCurve {
    func translated(by shift: CGVector) -> RadarLayoutCurve {
        RadarLayoutCurve(seriesIndex: seriesIndex, points: points.map { point in point.translated(by: shift) }, tension: tension, isRounded: isRounded)
    }
}
