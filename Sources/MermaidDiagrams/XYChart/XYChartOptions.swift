/**
 * File: XYChartOptions.swift
 * --------------------------
 * Layer: Core
 * Description: The options of XY charts a diagram's front matter and directives set, as Pele's XY renderer reads them,
 *              and the page a chart is laid out on.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 19/11/2026
 */

import CoreGraphics

/// The options of XY charts a diagram's front matter (`config:`, then `xyChart:`, in block or flow form) and its
/// `%%{init: …}%%` directives set, a directive's over the front matter's, as Pele's XY renderer reads them: the chart's
/// size, its orientation when the text writes none, whether the bars' values, the title and the legend are shown, and
/// for each axis its labels, title, ticks and line. A flag that is not a Boolean, a size that is not a positive number
/// and any other option leave the default.
public struct XYChartOptions: Equatable, Sendable {
    /// `width` and `height`: the page's, before a narrow column shrinks it, rounded and kept from 100 to 4,000 points;
    /// nil for Pele's 700 and 500.
    public internal(set) var width: Double?
    public internal(set) var height: Double?
    /// `chartOrientation: horizontal`, which the chart's own `horizontal` or `vertical` word overrides.
    public internal(set) var orientation: XYChartOrientation = .vertical
    /// `showDataLabel`: each bar's value past its end, where it fits.
    public internal(set) var showsDataLabels = false
    /// `showTitle` and `showLegend`.
    public internal(set) var showsTitle = true
    public internal(set) var showsLegend = true
    /// `xAxis` is the category axis (the bottom one of a vertical chart, the left one of a horizontal chart), `yAxis` the
    /// value axis.
    public internal(set) var xAxis = XYChartAxisOptions()
    public internal(set) var yAxis = XYChartAxisOptions()

    /// The page's smallest and largest side, and Pele's own size.
    static let smallestPageSide = 100.0
    static let largestPageSide = 4_000.0
    static let standardPage = CGSize(width: 700, height: 500)
    /// The narrowest a narrow column makes the page, and how much of its height it keeps at least.
    static let narrowestPageWidth: CGFloat = 240
    static let smallestHeightShare: CGFloat = 0.6

    /// Options that set nothing: Pele's defaults.
    public init() {}

    init(_ options: MermaidConfigurationOptions) {
        let values = options.values
        width = Self.dimension(values["width"])
        height = Self.dimension(values["height"])
        if values["chartOrientation"] == .text("horizontal") { orientation = .horizontal }
        showsDataLabels = Self.flag(values["showDataLabel"], default: false)
        showsTitle = Self.flag(values["showTitle"], default: true)
        showsLegend = Self.flag(values["showLegend"], default: true)
        xAxis = XYChartAxisOptions(options.nestedValues, axis: "xAxis")
        yAxis = XYChartAxisOptions(options.nestedValues, axis: "yAxis")
    }

    /// A positive number, rounded and kept from 100 to 4,000; nil for anything else.
    private static func dimension(_ value: MermaidConfigurationOptions.Value?) -> Double? {
        guard case .number(let number) = value, number > 0 else { return nil }
        return min(max(number, smallestPageSide), largestPageSide).rounded()
    }

    static func flag(_ value: MermaidConfigurationOptions.Value?, default fallback: Bool) -> Bool {
        if case .boolean(let flag) = value { return flag }
        return fallback
    }

    /// The page: the chart's own size, its width cut to the column's (`DiagramWidthFitting.capWidth`, not under 240
    /// points), and its height scaled with the width, by at least 0.6 of it, so that the plot keeps room for its marks.
    func page(availableWidth: CGFloat?) -> CGSize {
        let natural = CGFloat(width ?? Double(Self.standardPage.width))
        let pageWidth = DiagramWidthFitting.capWidth(availableWidth: availableWidth, natural: natural, least: Self.narrowestPageWidth)
        let ownHeight = CGFloat(height ?? Double(Self.standardPage.height))
        return CGSize(width: pageWidth, height: (ownHeight * max(Self.smallestHeightShare, pageWidth / natural)).rounded())
    }
}

/// What an XY chart's axis shows, each unless the options say `false`.
public struct XYChartAxisOptions: Equatable, Sendable {
    /// `showLabel`: the marks' labels (and a category axis' category labels).
    public internal(set) var showsLabels = true
    /// `showTitle`: the axis' title.
    public internal(set) var showsTitle = true
    /// `showTick`: a 4-point tick at each mark.
    public internal(set) var showsTicks = true
    /// `showAxisLine`: the axis' line.
    public internal(set) var showsAxisLine = true

    public init() {}

    /// The length of the ticks the axis draws: 4 points, or none.
    var tickLength: CGFloat { showsTicks ? XYChartLayoutEngine.tickLength : 0 }

    init(_ nestedValues: [String: MermaidConfigurationOptions.Value], axis: String) {
        showsLabels = XYChartOptions.flag(nestedValues[axis + ".showLabel"], default: true)
        showsTitle = XYChartOptions.flag(nestedValues[axis + ".showTitle"], default: true)
        showsTicks = XYChartOptions.flag(nestedValues[axis + ".showTick"], default: true)
        showsAxisLine = XYChartOptions.flag(nestedValues[axis + ".showAxisLine"], default: true)
    }
}
