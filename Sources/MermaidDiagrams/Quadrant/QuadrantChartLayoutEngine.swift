/**
 * File: QuadrantChartLayoutEngine.swift
 * -------------------------------------
 * Layer: Core
 * Description: Lays a quadrant chart out in Pele's style on a page its options and a narrow column size.
 *
 * Authors: felixchvl, Bahey Shalash
 * Version: 0.1
 * Date: 19/11/2026
 */

import CoreGraphics

/// Lays a quadrant chart out in Pele's style on a page of 500 by 500 points (the chart's options and a narrow column
/// change it): the bold title at the top, the four
/// quadrants filling the plot 4 points apart with their texts in the middle (at their top once the chart has points),
/// the axes' texts in the smaller size at the left and below (above before the chart has points), and the points at
/// their coordinates with their texts where they overlap nothing (`QuadrantChartPointPlacement`).
public enum QuadrantChartLayoutEngine {
    /// Between a quadrant's top and its text, once the chart has points: Pele's `quadrantTextTopPadding`.
    static let quadrantTextTopPadding: CGFloat = 5

    /// `availableWidth`, the width of the column the chart is shown in, narrows the page as Pele narrows it
    /// (`DiagramWidthFitting.capWidth`, not under 280 points) and the height with it; nil keeps the chart's own width.
    public static func layout(_ chart: QuadrantChart, typography: DiagramTypography, availableWidth: CGFloat? = nil) -> QuadrantChartLayout {
        layout(chart, quadrantText: typography.nodeText, axisText: typography.edgeText, pointText: typography.axisText,
               titleText: typography.boldNodeText, font: typography.font, availableWidth: availableWidth,
               sizedText: { size, isBold in typography.measurer(ofSize: size, isBold: isBold) })
    }

    /// `sizedText` makes the measurer of a text size the chart's options give; without it those sizes are not applied.
    static func layout<Measurer: DiagramTextMeasuring>(_ chart: QuadrantChart, quadrantText: Measurer, axisText: Measurer, pointText: Measurer,
                                                       titleText: Measurer, font: DiagramFont, availableWidth: CGFloat? = nil,
                                                       sizedText: ((_ size: CGFloat, _ isBold: Bool) -> Measurer)? = nil) -> QuadrantChartLayout {
        let options = chart.options
        let metrics = QuadrantChartMetrics(options: options, hasPoints: !chart.points.isEmpty, availableWidth: availableWidth,
                                           defaultPadding: QuadrantChartPlot.padding)
        func measurer(_ size: Double?, _ standard: Measurer, isBold: Bool = false) -> Measurer {
            guard let size, CGFloat(size) != standard.fontSize, let sizedText else { return standard }
            return sizedText(CGFloat(size), isBold)
        }
        let quadrantMeasurer = measurer(options.quadrantLabelFontSize, quadrantText)
        let pointMeasurer = measurer(options.pointLabelFontSize, pointText)
        let plot = QuadrantChartPlot(chart: chart, metrics: metrics, xAxisText: measurer(options.xAxisLabelFontSize, axisText),
                                     yAxisText: measurer(options.yAxisLabelFontSize, axisText),
                                     titleText: measurer(options.titleFontSize, titleText, isBold: true))
        var quadrants: [QuadrantChartLayoutQuadrant] = []
        var textBoxes: [CGRect] = []
        for index in 0..<QuadrantChart.quadrantCount {
            let frame = plot.quadrantFrame(index)
            var text = QuadrantChartPlot.block(chart.quadrantLabels[index], measurer: quadrantMeasurer,
                                               maximumWidth: plot.quadrantSize.width - QuadrantChartPlot.textInset)
            let height = text?.size.height ?? 0
            let center = CGPoint(x: frame.midX, y: chart.points.isEmpty ? frame.midY : frame.minY + metrics.quadrantTextTopPadding + height / 2)
            text?.center = center
            textBoxes.append(text?.frame ?? CGRect(origin: center, size: .zero))
            quadrants.append(QuadrantChartLayoutQuadrant(frame: frame, text: text))
        }
        let pointTextWidth = min(QuadrantChartPointPlacement.textWidth, plot.frame.width)
        let pointTexts = chart.points.map { point in
            DiagramTextBlock(label: point.label, measurer: pointMeasurer, maximumWidth: max(pointTextWidth, QuadrantChartPlot.narrowestTextWidth))
        }
        let points = QuadrantChartPointPlacement(chart: chart, plot: plot, quadrantTextBoxes: textBoxes, pointTexts: pointTexts, metrics: metrics).placed()
        return QuadrantChartLayout(size: metrics.page, font: font, quadrants: quadrants, axisLabels: plot.axisLabels, points: points, title: plot.title)
    }
}
