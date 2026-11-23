/**
 * File: RadarChart.swift
 * ----------------------
 * Layer: Core
 * Description: A Mermaid radar chart as its text describes it: axes, curves over them, the chart's options and titles.
 *
 * Authors: Bahey Shalash
 * Version: 0.2
 * Date: 23/11/2026
 */

/// A Mermaid radar chart (`radar-beta`): the axes in the order they are written, the curves (each a value per axis in the
/// axes' order, named entries ordered by axis), the options its statements set (`showLegend`, `ticks`, `max`, `min`,
/// `graticule`) and its titles. A curve written with a value for an axis only some axes have is refused while the chart is
/// read; a curve of numbers whose count is not the axes' count is kept and left out of the drawing, as Mermaid leaves it.
public struct RadarChart: Equatable, Sendable {
    /// The series colors its theme variables set, which its series are painted in over a palette's; none unless it
    /// sets them.
    public internal(set) var seriesColors = DiagramSeriesColors.none
    public internal(set) var axes: [RadarAxis]
    public internal(set) var curves: [RadarCurve]
    /// What the chart's own statements set.
    public internal(set) var options = RadarChartOptions()
    /// What its front matter and directives set (`radar:`).
    public internal(set) var appearance = RadarAppearance()
    /// `title …` in the chart, else `title:` in the front matter, or nil.
    public internal(set) var title: String?
    /// `accTitle: …`, the short name a screen reader gives the chart, or nil.
    public internal(set) var accessibilityTitle: String?
    /// `accDescr: …` or `accDescr { … }`, the longer description a screen reader reads, or nil.
    public internal(set) var accessibilityDescription: String?

    init(axes: [RadarAxis] = [], curves: [RadarCurve] = [], title: String? = nil, accessibilityTitle: String? = nil,
         accessibilityDescription: String? = nil) {
        self.axes = axes
        self.curves = curves
        self.title = title
        self.accessibilityTitle = accessibilityTitle
        self.accessibilityDescription = accessibilityDescription
    }
}

/// One axis of a radar chart: its name, which curves' entries refer to, and its label, the name unless one is written.
public struct RadarAxis: Equatable, Sendable {
    public let name: String
    public let label: DiagramLabel

    init(name: String, label: DiagramLabel) {
        self.name = name
        self.label = label
    }
}

/// One curve of a radar chart: its name, its label (the name unless one is written) and its values, one per axis in the
/// axes' order when it is drawn.
public struct RadarCurve: Equatable, Sendable {
    public let name: String
    public let label: DiagramLabel
    public let values: [Double]

    init(name: String, label: DiagramLabel, values: [Double]) {
        self.name = name
        self.label = label
        self.values = values
    }
}

/// How a radar chart's rings are drawn: circles with rounded curves, or polygons with straight ones.
public enum RadarGraticule: String, Equatable, Sendable {
    case circle
    case polygon
}

/// The options a radar chart's statements set; the last of an option written twice wins.
public struct RadarChartOptions: Equatable, Sendable {
    /// `showLegend`: whether the legend of the curves is drawn.
    public internal(set) var showsLegend = true
    /// `ticks`: how many rings the graticule has, at most 32.
    public internal(set) var tickCount: Double = 5
    /// `max`: the value at the rim; nil for the largest value of any curve.
    public internal(set) var maximum: Double?
    /// `min`: the value at the center.
    public internal(set) var minimum: Double = 0
    /// `graticule`: the rings' form.
    public internal(set) var graticule: RadarGraticule = .circle

    /// The most rings a graticule has, so that a text cannot ask for millions.
    public static let largestTickCount: Double = 32

    public init() {}
}
