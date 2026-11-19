/**
 * File: XYChartFrame.swift
 * ------------------------
 * Layer: Core
 * Description: Where an XY chart's plot goes on its page and what is measured around it.
 *
 * Authors: felixchvl, Bahey Shalash
 * Version: 0.1
 * Date: 19/11/2026
 */

import CoreGraphics

/// Where an XY chart's plot goes on its page and what is measured around it, as Pele arranges them: the title above,
/// room for the tallest point label over the plot, the left axis' title, labels and ticks on its left, the bottom
/// axis' ticks, labels and title below it, and the legend (and a horizontal chart's point labels) on its right. The
/// value axis is the left one of a vertical chart and the bottom one of a horizontal chart.
struct XYChartFrame {
    /// The page the chart is laid out on and the options that shape it.
    let page: CGSize
    let options: XYChartOptions
    let isHorizontal: Bool
    /// The title, measured, not placed yet.
    let title: DiagramTextBlock?
    /// The legend's titles, measured, each with its series' place and kind.
    let legendTexts: [(seriesIndex: Int, kind: XYChartSeriesKind, text: DiagramTextBlock)]
    /// The room right of the plot a horizontal chart keeps for its point labels.
    let pointLabelReach: CGFloat
    let valueScale: XYChartValueScale
    let categoryScale: XYChartCategoryScale
    let leftTitle: DiagramTextBlock?
    let bottomTitle: DiagramTextBlock?
    let leftMarks: [XYChartMark]
    let bottomMarks: [XYChartMark]
    let plot: CGRect
    /// The category axis' options and the value axis', on the left and at the bottom as the chart's orientation puts them.
    let leftAxis: XYChartAxisOptions
    let bottomAxis: XYChartAxisOptions

    /// What the frame's measurements need.
    private struct Measurements {
        let legendSpace: CGFloat
        let categoryLabels: [DiagramTextBlock]
        let categorySize: CGSize
        let pointLabelWidth: CGFloat
        /// The widest value past a horizontal chart's bars, when the options show the bars' values.
        let barValueWidth: CGFloat

        /// The room a horizontal chart keeps right of its plot for what is written past a point or a bar.
        var reachBesideBars: CGFloat {
            max(pointLabelWidth > 0 ? pointLabelWidth + XYChartLayoutEngine.pointLabelReachGap : 0,
                barValueWidth > 0 ? barValueWidth + XYChartLayoutEngine.barValueReachGap : 0)
        }
    }

    /// The title, the legend's titles and the axes' titles, measured as the options show them.
    private struct Texts {
        let title: DiagramTextBlock?
        let legend: [(seriesIndex: Int, kind: XYChartSeriesKind, text: DiagramTextBlock)]
        let leftTitle: DiagramTextBlock?
        let bottomTitle: DiagramTextBlock?

        init(chart: XYChart, text: XYChartText<some DiagramTextMeasuring>, page: CGSize, isHorizontal: Bool) {
            let options = chart.options
            title = options.showsTitle ? chart.title.flatMap { title in
                text.title(DiagramLabelDecoder.label(from: title, form: .plain), maximumWidth: page.width - 2 * XYChartLayoutEngine.padding)
            } : nil
            legend = options.showsLegend ? chart.series.enumerated().compactMap { index, series in
                text.small(series.title, maximumWidth: page.width * XYChartLayoutEngine.legendWidthShare).map { block in (index, series.kind, block) }
            } : []
            let categoryAxisTitle = options.xAxis.showsTitle
                ? text.small(chart.xAxis.title, maximumWidth: (isHorizontal ? page.height : page.width) * XYChartLayoutEngine.axisTitleShare) : nil
            let valueAxisTitle = options.yAxis.showsTitle
                ? text.small(chart.yAxis.title, maximumWidth: (isHorizontal ? page.width : page.height) * XYChartLayoutEngine.axisTitleShare) : nil
            leftTitle = isHorizontal ? categoryAxisTitle : valueAxisTitle
            bottomTitle = isHorizontal ? valueAxisTitle : categoryAxisTitle
        }
    }

    init(chart: XYChart, text: XYChartText<some DiagramTextMeasuring>, page: CGSize) {
        let padding = XYChartLayoutEngine.padding
        let options = chart.options
        self.page = page
        self.options = options
        isHorizontal = chart.orientation == .horizontal
        leftAxis = isHorizontal ? options.xAxis : options.yAxis
        bottomAxis = isHorizontal ? options.yAxis : options.xAxis
        let texts = Texts(chart: chart, text: text, page: page, isHorizontal: isHorizontal)
        (title, legendTexts, leftTitle, bottomTitle) = (texts.title, texts.legend, texts.leftTitle, texts.bottomTitle)
        var valueScale = XYChartValueScale(chart: chart)
        categoryScale = XYChartCategoryScale(chart: chart)
        let measurements = Self.measurements(chart: chart, legendTexts: legendTexts, categoryScale: categoryScale, isHorizontal: isHorizontal, text: text,
                                             page: page)
        let top = padding + (title.map { title in title.size.height + XYChartLayoutEngine.titleGap } ?? 0)
            + Self.headroom(isHorizontal: isHorizontal, pointLabelWidth: measurements.pointLabelWidth, showsBarValues: options.showsDataLabels,
                            showsLeftLabels: leftAxis.showsLabels, text: text)
        let bottomLabelHeight = !bottomAxis.showsLabels ? 0
            : isHorizontal || !categoryScale.isCategorical ? text.smallText.lineHeight : measurements.categorySize.height
        let plotHeight = max(1, page.height - padding - Self.bottomSpace(tick: bottomAxis.tickLength, labelHeight: bottomLabelHeight, title: bottomTitle) - top)
        leftMarks = isHorizontal
            ? Self.categoryMarks(categoryScale, length: plotHeight, measurements: measurements, isHorizontal: isHorizontal, text: text)
            : valueScale.marks(length: plotHeight, spacing: XYChartLayoutEngine.leftValueMarkSpacing, text: text.smallText)
        let leftLabelWidth = leftAxis.showsLabels ? leftMarks.map(\.label.size.width).max() ?? 0 : 0
        let left = padding + (leftTitle.map { title in title.size.height + XYChartLayoutEngine.leftLabelGap } ?? 0)
            + (leftLabelWidth > 0 ? leftLabelWidth + XYChartLayoutEngine.leftLabelGap : 0) + leftAxis.tickLength
        pointLabelReach = isHorizontal ? min(page.width * XYChartLayoutEngine.pointLabelReachShare, measurements.reachBesideBars) : 0
        var plotWidth = max(1, page.width - padding - left - measurements.legendSpace - pointLabelReach)
        bottomMarks = isHorizontal
            ? valueScale.marks(length: plotWidth, spacing: XYChartLayoutEngine.bottomValueMarkSpacing, text: text.smallText)
            : Self.categoryMarks(categoryScale, length: plotWidth, measurements: measurements, isHorizontal: isHorizontal, text: text)
        if bottomAxis.showsLabels, measurements.legendSpace + pointLabelReach == 0 {
            let overhang = bottomMarks.map { mark in CGFloat(mark.fraction) * plotWidth + mark.label.size.width / 2 - plotWidth }.max() ?? 0
            plotWidth = max(1, plotWidth - max(0, overhang))
        }
        self.valueScale = valueScale
        plot = CGRect(x: left, y: top, width: plotWidth, height: plotHeight)
    }

    /// The room below the plot: the ticks, the labels and the axis' title, each with its gap.
    private static func bottomSpace(tick: CGFloat, labelHeight: CGFloat, title: DiagramTextBlock?) -> CGFloat {
        tick + (labelHeight > 0 ? labelHeight + XYChartLayoutEngine.bottomLabelGap : 0)
            + (title.map { title in title.size.height + XYChartLayoutEngine.bottomLabelGap } ?? 0)
    }

    /// The room over the plot of a vertical chart: a line of point labels when a line has them, else half a line for
    /// the top mark's label.
    private static func headroom(isHorizontal: Bool, pointLabelWidth: CGFloat, showsBarValues: Bool, showsLeftLabels: Bool,
                                 text: XYChartText<some DiagramTextMeasuring>) -> CGFloat {
        guard !isHorizontal else { return 0 }
        if pointLabelWidth > 0 || showsBarValues { return text.tinyText.lineHeight + XYChartLayoutEngine.pointLabelGap }
        return showsLeftLabels ? text.smallText.lineHeight / 2 : 0
    }

    private static func measurements(chart: XYChart, legendTexts: [(seriesIndex: Int, kind: XYChartSeriesKind, text: DiagramTextBlock)],
                                     categoryScale: XYChartCategoryScale,
                                     isHorizontal: Bool, text: XYChartText<some DiagramTextMeasuring>, page: CGSize) -> Measurements {
        let legendWidth = legendTexts.map { entry in entry.text.size.width + XYChartLayoutEngine.swatchSide + XYChartLayoutEngine.swatchTextGap }.max()
        let legendSpace = legendWidth.map { width in width + XYChartLayoutEngine.legendGap } ?? 0
        var categoryLabels: [DiagramTextBlock] = []
        if case .categories(let categories) = categoryScale.kind, chart.options.xAxis.showsLabels {
            let wrappingWidth = isHorizontal ? page.width * XYChartLayoutEngine.legendWidthShare
                : max(XYChartLayoutEngine.narrowestCategoryWrap, (page.width - 2 * XYChartLayoutEngine.padding - XYChartLayoutEngine.categoryWrapAllowance
                    - legendSpace) * CGFloat(categoryScale.slot) - XYChartLayoutEngine.categoryWrapMargin)
            categoryLabels = categories.map { category in text.smallBlock(category, maximumWidth: wrappingWidth) }
        }
        let pointLabelWidth = chart.series.flatMap(\.pointLabels).map { label in text.tinyBlock(label).size.width }.max() ?? 0
        let showsBarValuesBesideBars = chart.options.showsDataLabels && isHorizontal
        let barValueWidth = showsBarValuesBesideBars ? chart.series.filter { series in series.kind == .bar }.flatMap(\.values).map { value in
            XYChartValueScale.drawable(value ?? .nan).map { drawable in text.tinyBlock(DiagramLabel(JavaScriptNumberText.text(drawable))).size.width } ?? 0
        }.max() ?? 0 : 0
        return Measurements(legendSpace: legendSpace, categoryLabels: categoryLabels,
                            categorySize: CGSize(width: categoryLabels.map(\.size.width).max() ?? 0, height: categoryLabels.map(\.size.height).max() ?? 0),
                            pointLabelWidth: pointLabelWidth, barValueWidth: barValueWidth)
    }

    /// The category axis' marks, spaced so that labels along it, or the round numbers of its range, do not run into
    /// each other.
    private static func categoryMarks(_ scale: XYChartCategoryScale, length: CGFloat, measurements: Measurements, isHorizontal: Bool,
                                      text: XYChartText<some DiagramTextMeasuring>) -> [XYChartMark] {
        let labelExtent = measurements.categoryLabels.isEmpty ? XYChartLayoutEngine.emptyCategoryExtent
            : isHorizontal ? measurements.categorySize.height : measurements.categorySize.width + XYChartLayoutEngine.categoryLabelSpacing
        return scale.marks(length: length, categoryLabels: measurements.categoryLabels, labelExtent: labelExtent,
                           rangeSpacing: isHorizontal ? XYChartLayoutEngine.leftRangeMarkSpacing : XYChartLayoutEngine.bottomRangeMarkSpacing,
                           text: text.smallText)
    }
}
