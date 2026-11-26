/**
 * File: QuadrantChartOptions.swift
 * --------------------------------
 * Layer: Core
 * Description: The options of quadrant charts a diagram's front matter and directives set, as Pele's quadrant renderer
 *              reads them.
 *
 * Authors: Bahey Shalash
 * Version: 0.2
 * Date: 26/11/2026
 */

import CoreGraphics

/// The options of quadrant charts a diagram's front matter (`config:`, then `quadrantChart:`, in block or flow form) and
/// its `%%{init: …}%%` directives set, a directive's over the front matter's, as Pele's quadrant renderer reads them: the
/// chart's size, its text sizes, the paddings, the points' radius and text distance, and which side the axes' texts
/// stand. A length is a number from 0 up, cut to its most; a text size a finite number, kept from 4 to 72 points; any
/// other value, an option Pele does not read and a name it does not know leave the default. Nil is the default: a
/// length of Pele's, or a text size that follows the diagram's font size.
public struct QuadrantChartOptions: Equatable, Sendable {
    /// `chartWidth` and `chartHeight`: the page's side before a narrow column shrinks it, from 100 points.
    public internal(set) var chartWidth: Double?
    public internal(set) var chartHeight: Double?
    /// `titleFontSize`, `quadrantLabelFontSize`, `xAxisLabelFontSize`, `yAxisLabelFontSize` and `pointLabelFontSize`.
    public internal(set) var titleFontSize: Double?
    public internal(set) var quadrantLabelFontSize: Double?
    public internal(set) var xAxisLabelFontSize: Double?
    public internal(set) var yAxisLabelFontSize: Double?
    public internal(set) var pointLabelFontSize: Double?
    /// `quadrantPadding`: around the page's content.
    public internal(set) var quadrantPadding: Double?
    /// `xAxisLabelPadding` and `yAxisLabelPadding`: between an axis's texts and the quadrants.
    public internal(set) var xAxisLabelPadding: Double?
    public internal(set) var yAxisLabelPadding: Double?
    /// `titlePadding`: below the title.
    public internal(set) var titlePadding: Double?
    /// `quadrantTextTopPadding`: between a quadrant's top and its text, once the chart has points.
    public internal(set) var quadrantTextTopPadding: Double?
    /// `pointRadius` and `pointTextPadding`.
    public internal(set) var pointRadius: Double?
    public internal(set) var pointTextPadding: Double?
    /// `xAxisPosition: bottom` puts the x axis's texts below the quadrants even before the chart has points.
    public internal(set) var xAxisIsBelow = false
    /// `yAxisPosition: right` puts the y axis's texts at the quadrants' right.
    public internal(set) var yAxisIsRight = false

    /// The most a length may be, and the least and most a text size may be, and the least a page's side may be.
    static let largestLength = 200.0
    static let largestPageSide = 4_000.0
    static let smallestPageSide = 100.0
    static let smallestTextSize = 4.0
    static let largestTextSize = 72.0

    /// Options that set nothing: Pele's defaults.
    public init() {}

    init(_ options: MermaidConfigurationOptions) {
        // Most diagrams set no option: every value keeps its default, which is what each option read from nothing gives.
        guard !options.values.isEmpty else { return }
        let values = options.values
        chartWidth = Self.length(values["chartWidth"], most: Self.largestPageSide)
        chartHeight = Self.length(values["chartHeight"], most: Self.largestPageSide)
        titleFontSize = Self.textSize(values["titleFontSize"])
        quadrantLabelFontSize = Self.textSize(values["quadrantLabelFontSize"])
        xAxisLabelFontSize = Self.textSize(values["xAxisLabelFontSize"])
        yAxisLabelFontSize = Self.textSize(values["yAxisLabelFontSize"])
        pointLabelFontSize = Self.textSize(values["pointLabelFontSize"])
        quadrantPadding = Self.length(values["quadrantPadding"], most: Self.largestLength)
        xAxisLabelPadding = Self.length(values["xAxisLabelPadding"], most: Self.largestLength)
        yAxisLabelPadding = Self.length(values["yAxisLabelPadding"], most: Self.largestLength)
        titlePadding = Self.length(values["titlePadding"], most: Self.largestLength)
        quadrantTextTopPadding = Self.length(values["quadrantTextTopPadding"], most: Self.largestLength)
        pointRadius = Self.length(values["pointRadius"], most: Self.largestLength)
        pointTextPadding = Self.length(values["pointTextPadding"], most: Self.largestLength)
        xAxisIsBelow = values["xAxisPosition"] == .text("bottom")
        yAxisIsRight = values["yAxisPosition"] == .text("right")
    }

    private static func length(_ value: MermaidConfigurationOptions.Value?, most: Double) -> Double? {
        guard case .number(let number) = value, number >= 0 else { return nil }
        return min(number, most)
    }

    private static func textSize(_ value: MermaidConfigurationOptions.Value?) -> Double? {
        guard case .number(let number) = value, number.isFinite else { return nil }
        return min(largestTextSize, max(smallestTextSize, number))
    }
}

/// The page and the lengths a quadrant chart is laid out with: its options over Pele's defaults, and the width a narrow
/// column leaves it.
struct QuadrantChartMetrics {
    let page: CGSize
    let padding: CGFloat
    let xAxisLabelPadding: CGFloat
    let yAxisLabelPadding: CGFloat
    let titlePadding: CGFloat
    let quadrantTextTopPadding: CGFloat
    let pointRadius: CGFloat
    let pointTextPadding: CGFloat
    let xAxisIsBelowQuadrants: Bool
    let yAxisIsRight: Bool

    /// Pele's page: the chart's own width, or the container's when that is narrower (`DiagramWidthFitting.capWidth`, not
    /// under 280 points), and the height in proportion to the width taken from the chart's own. `padding` is Pele's
    /// padding option, which `quadrantPadding` replaces.
    init(options: QuadrantChartOptions, hasPoints: Bool, availableWidth: CGFloat?, defaultPadding: CGFloat) {
        let natural = max(QuadrantChartOptions.smallestPageSide, options.chartWidth ?? Double(QuadrantChartPlot.pageSide)).rounded()
        let width = DiagramWidthFitting.capWidth(availableWidth: availableWidth, natural: CGFloat(natural), least: Self.narrowestPageWidth).rounded()
        let ownHeight = max(QuadrantChartOptions.smallestPageSide, options.chartHeight ?? Double(QuadrantChartPlot.pageSide))
        page = CGSize(width: width, height: (CGFloat(ownHeight) * width / CGFloat(natural)).rounded())
        padding = CGFloat(options.quadrantPadding ?? Double(defaultPadding))
        xAxisLabelPadding = CGFloat(options.xAxisLabelPadding ?? Double(QuadrantChartPlot.axisLabelPadding))
        yAxisLabelPadding = CGFloat(options.yAxisLabelPadding ?? Double(QuadrantChartPlot.axisLabelPadding))
        titlePadding = CGFloat(options.titlePadding ?? Double(QuadrantChartPlot.titlePadding))
        quadrantTextTopPadding = CGFloat(options.quadrantTextTopPadding ?? Double(QuadrantChartLayoutEngine.quadrantTextTopPadding))
        pointRadius = CGFloat(options.pointRadius ?? Double(QuadrantChartPointPlacement.standardRadius))
        pointTextPadding = CGFloat(options.pointTextPadding ?? Double(QuadrantChartPointPlacement.textPadding))
        xAxisIsBelowQuadrants = hasPoints || options.xAxisIsBelow
        yAxisIsRight = options.yAxisIsRight
    }

    /// The narrowest page a narrow column makes.
    static let narrowestPageWidth: CGFloat = 280
}
