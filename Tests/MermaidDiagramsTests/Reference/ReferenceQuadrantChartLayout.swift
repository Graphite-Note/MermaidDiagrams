/**
 * File: ReferenceQuadrantChartLayout.swift
 * ----------------------------------------
 * Layer: Tests
 * Description: 0.7.0's quadrant chart layout, frozen as main ba176e5 laid a chart out: its plot, its axes' texts and
 *              its point placement, which tries five places a text against every box taken, which the layout with its
 *              boxes' edges read once is compared with.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 26/11/2026
 */

import CoreGraphics
@testable import MermaidDiagrams

enum ReferenceQuadrantChartLayoutEngine {
    /// Between a quadrant's top and its text, once the chart has points: Pele's `quadrantTextTopPadding`.
    static let quadrantTextTopPadding: CGFloat = 5

    /// `availableWidth`, the width of the column the chart is shown in, narrows the page as Pele narrows it
    /// (`DiagramWidthFitting.capWidth`, not under 280 points) and the height with it; nil keeps the chart's own width.
    /// `sizedText` makes the measurer of a text size the chart's options give; without it those sizes are not applied.
    static func layout<Measurer: DiagramTextMeasuring>(_ chart: QuadrantChart, quadrantText: Measurer, axisText: Measurer, pointText: Measurer,
                                                       titleText: Measurer, font: DiagramFont, availableWidth: CGFloat? = nil,
                                                       sizedText: ((_ size: CGFloat, _ isBold: Bool) -> Measurer)? = nil) -> QuadrantChartLayout {
        let options = chart.options
        let metrics = QuadrantChartMetrics(options: options, hasPoints: !chart.points.isEmpty, availableWidth: availableWidth,
                                           defaultPadding: ReferenceQuadrantChartPlot.padding)
        func measurer(_ size: Double?, _ standard: Measurer, isBold: Bool = false) -> Measurer {
            guard let size, CGFloat(size) != standard.fontSize, let sizedText else { return standard }
            return sizedText(CGFloat(size), isBold)
        }
        let quadrantMeasurer = measurer(options.quadrantLabelFontSize, quadrantText)
        let pointMeasurer = measurer(options.pointLabelFontSize, pointText)
        let plot = ReferenceQuadrantChartPlot(chart: chart, metrics: metrics, xAxisText: measurer(options.xAxisLabelFontSize, axisText),
                                     yAxisText: measurer(options.yAxisLabelFontSize, axisText),
                                     titleText: measurer(options.titleFontSize, titleText, isBold: true))
        var quadrants: [QuadrantChartLayoutQuadrant] = []
        var textBoxes: [CGRect] = []
        for index in 0..<QuadrantChart.quadrantCount {
            let frame = plot.quadrantFrame(index)
            var text = ReferenceQuadrantChartPlot.block(chart.quadrantLabels[index], measurer: quadrantMeasurer,
                                               maximumWidth: plot.quadrantSize.width - ReferenceQuadrantChartPlot.textInset)
            let height = text?.size.height ?? 0
            let center = CGPoint(x: frame.midX, y: chart.points.isEmpty ? frame.midY : frame.minY + metrics.quadrantTextTopPadding + height / 2)
            text?.center = center
            textBoxes.append(text?.frame ?? CGRect(origin: center, size: .zero))
            quadrants.append(QuadrantChartLayoutQuadrant(frame: frame, text: text))
        }
        let pointTextWidth = min(ReferenceQuadrantChartPointPlacement.textWidth, plot.frame.width)
        let pointTexts = chart.points.map { point in
            DiagramTextBlock(label: point.label, measurer: pointMeasurer, maximumWidth: max(pointTextWidth, ReferenceQuadrantChartPlot.narrowestTextWidth))
        }
        let points = ReferenceQuadrantChartPointPlacement(chart: chart, plot: plot, quadrantTextBoxes: textBoxes, pointTexts: pointTexts, metrics: metrics).placed()
        return QuadrantChartLayout(size: metrics.page, font: font, quadrants: quadrants, axisLabels: plot.axisLabels, points: points, title: plot.title)
    }
}

struct ReferenceQuadrantChartPlot {
    let title: DiagramTextBlock?
    /// The four quadrants and the gaps between them.
    let frame: CGRect
    let quadrantSize: CGSize
    let axisLabels: [QuadrantChartAxisLabel]

    /// The page's side: Pele's `chartWidth` and `chartHeight`.
    static let pageSide: CGFloat = 500
    /// Around the page's content: Pele's `quadrantPadding`.
    static let padding: CGFloat = 8
    /// Below the title, half of it above: Pele's `titlePadding`.
    static let titlePadding: CGFloat = 10
    /// Between an axis's texts and the quadrants: Pele's `xAxisLabelPadding` and `yAxisLabelPadding`.
    static let axisLabelPadding: CGFloat = 5
    /// Between two quadrants.
    static let quadrantGap: CGFloat = 4
    /// What an axis's text leaves of its half of the axis, and a quadrant's text of its quadrant's width.
    static let textInset: CGFloat = 16
    /// The narrowest a text wraps at.
    static let narrowestTextWidth: CGFloat = 40

    /// The text of the axes is measured in `xAxisText` and `yAxisText`, which are one measurer unless the options give the
    /// two axes different sizes.
    init(chart: QuadrantChart, metrics: QuadrantChartMetrics, xAxisText: some DiagramTextMeasuring, yAxisText: some DiagramTextMeasuring,
         titleText: some DiagramTextMeasuring) {
        let padding = metrics.padding
        let side = metrics.page.width - 2 * padding
        var title = Self.block(chart.title.map { title in DiagramLabelDecoder.label(from: title, form: .plain) }, measurer: titleText, maximumWidth: side)
        let titleSpace = title.map { title in title.size.height + metrics.titlePadding } ?? 0
        let xLow = Self.block(chart.xAxisLowLabel, measurer: xAxisText, maximumWidth: chart.xAxisHighLabel == nil ? side : side / 2 - Self.textInset)
        let xHigh = Self.block(chart.xAxisHighLabel, measurer: xAxisText, maximumWidth: side / 2 - Self.textInset)
        let xHeight = max(xLow?.size.height ?? 0, xHigh?.size.height ?? 0)
        let xSpace = xLow == nil && xHigh == nil ? 0 : xHeight + metrics.xAxisLabelPadding
        let tall = metrics.page.height - 2 * padding - titleSpace - xSpace
        let yLow = Self.block(chart.yAxisLowLabel, measurer: yAxisText, maximumWidth: chart.yAxisHighLabel == nil ? tall : tall / 2 - Self.textInset)
        let yHigh = Self.block(chart.yAxisHighLabel, measurer: yAxisText, maximumWidth: tall / 2 - Self.textInset)
        let yHeight = max(yLow?.size.height ?? 0, yHigh?.size.height ?? 0)
        let ySpace = yLow == nil && yHigh == nil ? 0 : yHeight + metrics.yAxisLabelPadding
        let xAxisIsBelow = metrics.xAxisIsBelowQuadrants
        frame = CGRect(x: padding + (metrics.yAxisIsRight ? 0 : ySpace), y: padding + titleSpace + (xAxisIsBelow ? 0 : xSpace), width: max(0, side - ySpace),
                       height: max(0, tall))
        quadrantSize = CGSize(width: max(0, (frame.width - Self.quadrantGap) / 2), height: max(0, (frame.height - Self.quadrantGap) / 2))
        let xMiddle = xAxisIsBelow ? frame.maxY + metrics.xAxisLabelPadding + xHeight / 2 : frame.minY - metrics.xAxisLabelPadding - xHeight / 2
        let yMiddle = metrics.yAxisIsRight ? frame.maxX + metrics.yAxisLabelPadding + yHeight / 2 : frame.minX - metrics.yAxisLabelPadding - yHeight / 2
        axisLabels = Self.xAxisLabels(low: xLow, high: xHigh, frame: frame, middle: xMiddle)
            + Self.yAxisLabels(low: yLow, high: yHigh, frame: frame, middle: yMiddle)
        // Half the title's padding above it, the other half below it.
        title?.center = CGPoint(x: metrics.page.width / 2, y: titleSpace / 2)
        self.title = title
    }

    /// The box of quadrant `index + 1`: 1 at the top right, then anticlockwise.
    func quadrantFrame(_ index: Int) -> CGRect {
        let isRight = index == 0 || index == 3
        let isTop = index < 2
        return CGRect(x: isRight ? frame.maxX - quadrantSize.width : frame.minX, y: isTop ? frame.minY : frame.maxY - quadrantSize.height,
                      width: quadrantSize.width, height: quadrantSize.height)
    }

    /// `label` measured and wrapped at `maximumWidth`, never narrower than 40 points; nil without a label.
    static func block(_ label: DiagramLabel?, measurer: some DiagramTextMeasuring, maximumWidth: CGFloat) -> DiagramTextBlock? {
        label.map { label in DiagramTextBlock(label: label, measurer: measurer, maximumWidth: max(maximumWidth, narrowestTextWidth)) }
    }

    /// The x axis's texts on the line through `middle`: the low end's in the left half's middle, or from the left edge
    /// without a high end; the high end's in the right half's middle.
    private static func xAxisLabels(low: DiagramTextBlock?, high: DiagramTextBlock?, frame: CGRect, middle: CGFloat) -> [QuadrantChartAxisLabel] {
        var labels: [QuadrantChartAxisLabel] = []
        if let low {
            let center = high == nil ? frame.minX + low.size.width / 2 : frame.minX + frame.width / 4
            labels.append(placed(low, at: CGPoint(x: center, y: middle)))
        }
        if let high { labels.append(placed(high, at: CGPoint(x: frame.minX + frame.width * 3 / 4, y: middle))) }
        return labels
    }

    /// The y axis's texts turned on the line through `middle`: the low end's in the lower half's middle, or from the
    /// bottom edge without a high end; the high end's in the upper half's middle.
    private static func yAxisLabels(low: DiagramTextBlock?, high: DiagramTextBlock?, frame: CGRect, middle: CGFloat) -> [QuadrantChartAxisLabel] {
        var labels: [QuadrantChartAxisLabel] = []
        if let low {
            let center = high == nil ? frame.maxY - low.size.width / 2 : frame.minY + frame.height * 3 / 4
            labels.append(placed(low, at: CGPoint(x: middle, y: center), isTurned: true))
        }
        if let high { labels.append(placed(high, at: CGPoint(x: middle, y: frame.minY + frame.height / 4), isTurned: true)) }
        return labels
    }

    private static func placed(_ text: DiagramTextBlock, at center: CGPoint, isTurned: Bool = false) -> QuadrantChartAxisLabel {
        var placed = text
        placed.center = center
        return QuadrantChartAxisLabel(text: placed, isTurned: isTurned)
    }
}

struct ReferenceQuadrantChartPointPlacement {
    let chart: QuadrantChart
    let plot: ReferenceQuadrantChartPlot
    /// The boxes of the quadrants' texts, quadrant 1 first; a quadrant without text has an empty box where its text's
    /// middle would be.
    let quadrantTextBoxes: [CGRect]
    /// Each point's text measured, in the order the points are written.
    let pointTexts: [DiagramTextBlock]
    /// The radius a point has unless its styles give one, and the distance between a point and its text: the options'.
    let metrics: QuadrantChartMetrics

    /// Pele's `pointRadius`.
    static let standardRadius: CGFloat = 5
    /// The largest radius and outline width drawn, as Pele bounds them.
    static let largestRadius: CGFloat = 2_000
    static let largestStrokeWidth: CGFloat = 400
    /// Between a point and its text: Pele's `pointTextPadding`.
    static let textPadding: CGFloat = 5
    /// The width a point's text wraps at.
    static let textWidth: CGFloat = 200
    /// Above this many points, texts are not kept apart.
    static let largestCarefulPointCount = 300
    /// Half the height a line of a point's text keeps clear, as a share of its font size: Pele's.
    static let lineHalfHeightRatio: CGFloat = 0.6

    /// A point drawn, before its text is placed.
    private struct DrawnPoint {
        let center: CGPoint
        let radius: CGFloat
        let fill: QuadrantChartPaint
        let stroke: QuadrantChartStroke?
        let text: DiagramTextBlock
        /// How far the point reaches from its center, its outline included.
        var reach: CGFloat { radius + (stroke?.width ?? 0) / 2 }
    }

    func placed() -> [QuadrantChartLayoutPoint] {
        let drawn = zip(chart.points, pointTexts).compactMap(drawnPoint)
        let isCareful = drawn.count <= Self.largestCarefulPointCount
        var taken = gapBoxes + quadrantTextBoxes
        if isCareful { taken += drawn.map { point in point.center.referenceBox(halfWidth: point.reach, halfHeight: point.reach) } }
        var points: [QuadrantChartLayoutPoint] = []
        points.reserveCapacity(drawn.count)
        for point in drawn {
            let halfSize = halfSize(of: point.text)
            let center = textCenter(point, halfSize: halfSize, taken: isCareful ? taken : nil)
            if isCareful { taken.append(center.referenceBox(halfWidth: halfSize.width, halfHeight: halfSize.height)) }
            var text = point.text
            text.center = center
            points.append(QuadrantChartLayoutPoint(center: point.center, radius: point.radius, fill: point.fill, stroke: point.stroke, text: text))
        }
        return points
    }

    /// The point drawn at its coordinates in its styles, or nil when either coordinate is not a number from 0 to 1.
    private func drawnPoint(_ point: QuadrantChartPoint, text: DiagramTextBlock) -> DrawnPoint? {
        guard let xCoordinate = point.xCoordinate, let yCoordinate = point.yCoordinate, (0...1).contains(xCoordinate),
              (0...1).contains(yCoordinate) else { return nil }
        let style = point.style.overriding(point.className.flatMap { name in chart.classStyles[name] })
        let stroke = style.strokeWidth.map { width in
            QuadrantChartStroke(paint: style.strokeColor.map(QuadrantChartPaint.written) ?? .firstSeries, width: min(CGFloat(width), Self.largestStrokeWidth))
        }
        let frame = plot.frame
        return DrawnPoint(center: CGPoint(x: frame.minX + CGFloat(xCoordinate) * frame.width, y: frame.minY + CGFloat(1 - yCoordinate) * frame.height),
                          radius: min(CGFloat(style.radius ?? Double(metrics.pointRadius)), Self.largestRadius),
                          fill: style.color.map(QuadrantChartPaint.written) ?? .firstSeries, stroke: stroke, text: text)
    }

    /// The half width and the half height a text keeps clear: its widest line's half, and Pele's line height.
    private func halfSize(of text: DiagramTextBlock) -> CGSize {
        CGSize(width: text.size.width / 2,
               height: text.fontSize * Self.lineHalfHeightRatio + (text.size.height - text.lineHeight) / 2)
    }

    /// Where the point's text goes: the first free place of the two rounds, else the first place inside the plot, else
    /// below the point. Every place is free when `taken` is nil.
    private func textCenter(_ point: DrawnPoint, halfSize: CGSize, taken: [CGRect]?) -> CGPoint {
        let places = candidatePlaces(point, halfSize: halfSize)
        var chosen: CGPoint?
        for round in 0..<2 {
            for (place, isClamped, margin) in places {
                let center = isClamped && point.text.size.width < plot.frame.width ? clamped(place, halfWidth: halfSize.width, margin: margin) : place
                let box = center.referenceBox(halfWidth: halfSize.width, halfHeight: halfSize.height)
                guard isInsidePlot(box) else { continue }
                let isFree = taken.map { boxes in Self.isClear(box, of: boxes.dropFirst(round == 0 ? 0 : gapBoxes.count)) } ?? true
                if chosen == nil || isFree { chosen = center }
                if isFree { return center }
            }
        }
        return chosen ?? places[0].place
    }

    /// Below the point, above it, right of it, left of it, and below its quadrant's text, each with whether it is moved
    /// across to stay inside the plot, and how far from the plot's edges it then stays.
    private func candidatePlaces(_ point: DrawnPoint, halfSize: CGSize) -> [(place: CGPoint, isClamped: Bool, margin: CGFloat)] {
        let away = point.reach + metrics.pointTextPadding
        let inset = min(away, max(0, (plot.quadrantSize.width - point.text.size.width) / 2))
        let quadrantText = quadrantTextBoxes[quadrantIndex(of: point.center)]
        let belowQuadrantText = max(point.center.y + away, quadrantText.maxY + metrics.pointTextPadding) + halfSize.height
        let center = point.center
        return [
            (CGPoint(x: center.x, y: center.y + away + halfSize.height), true, 0),
            (CGPoint(x: center.x, y: center.y - away - halfSize.height), true, 0),
            (CGPoint(x: center.x + away + halfSize.width, y: center.y), false, 0),
            (CGPoint(x: center.x - away - halfSize.width, y: center.y), false, 0),
            (CGPoint(x: center.x, y: belowQuadrantText), true, inset),
        ]
    }

    /// `place` moved across, as little as it takes, to keep the text `margin` inside the plot's edges.
    private func clamped(_ place: CGPoint, halfWidth: CGFloat, margin: CGFloat) -> CGPoint {
        let frame = plot.frame
        return CGPoint(x: min(max(place.x, frame.minX + halfWidth + margin), frame.maxX - halfWidth - margin), y: place.y)
    }

    /// Whether `box` is inside the plot, its edges on the plot's edges included.
    private func isInsidePlot(_ box: CGRect) -> Bool {
        let frame = plot.frame
        return box.minX >= frame.minX && box.maxX <= frame.maxX && box.minY >= frame.minY && box.maxY <= frame.maxY
    }

    /// The quadrant a point is in, by index: 0 at the top right, then anticlockwise.
    private func quadrantIndex(of center: CGPoint) -> Int {
        let isLeft = center.x < plot.frame.midX
        let isTop = center.y < plot.frame.midY
        if isLeft { return isTop ? 1 : 2 }
        return isTop ? 0 : 3
    }

    /// The gaps between the quadrants: the one down the middle and the one across it.
    private var gapBoxes: [CGRect] {
        let frame = plot.frame
        let size = plot.quadrantSize
        return [CGRect(x: frame.minX + size.width, y: frame.minY, width: frame.width - 2 * size.width, height: frame.height),
                CGRect(x: frame.minX, y: frame.minY + size.height, width: frame.width, height: frame.height - 2 * size.height)]
    }

    /// Whether `box` overlaps none of `boxes`, edges that only touch apart; an empty box is a point that a box overlaps
    /// when the point is strictly inside it.
    private static func isClear(_ box: CGRect, of boxes: ArraySlice<CGRect>) -> Bool {
        !boxes.contains { other in box.minX < other.maxX && box.maxX > other.minX && box.minY < other.maxY && box.maxY > other.minY }
    }
}

private extension CGPoint {
    func referenceBox(halfWidth: CGFloat, halfHeight: CGFloat) -> CGRect {
        CGRect(x: x - halfWidth, y: y - halfHeight, width: 2 * halfWidth, height: 2 * halfHeight)
    }
}
