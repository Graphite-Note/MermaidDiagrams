/**
 * File: RadarChartLayout.swift
 * ----------------------------
 * Layer: Core
 * Description: A laid-out radar chart: its graticule, spokes, curves, axis labels, legend and title.
 *
 * Authors: Bahey Shalash
 * Version: 0.2
 * Date: 23/11/2026
 */

import CoreGraphics

/// A radar chart laid out on a page whose origin is the top left corner and whose y runs down, in points: the graticule's
/// rings and the spokes around the center, the curves, each axis's label beyond its spoke, the legend beside the chart and
/// the title above it.
public struct RadarChartLayout: Equatable, Sendable {
    /// The series colors the diagram's theme variables set, which its scene carries.
    public internal(set) var seriesColors = DiagramSeriesColors.none
    public let size: CGSize
    /// The font the text was measured in: the title at its size, labels and legend at their own.
    public let font: DiagramFont
    public let center: CGPoint
    /// The radius of the rim, where a value of the chart's maximum lies.
    public let radius: CGFloat
    /// The rings' radii, from the innermost out; none when the chart has no ticks.
    public let ringRadii: [CGFloat]
    public let graticule: RadarGraticule
    /// Each axis's direction from the center, a unit vector, the first pointing up and the rest clockwise.
    public let axisDirections: [CGPoint]
    /// How far each spoke reaches from the center.
    public let spokeLength: CGFloat
    public let axisLabels: [DiagramTextBlock]
    /// The curves drawn: those with a value for every axis.
    public let curves: [RadarLayoutCurve]
    /// One entry per curve of the chart, in the order they are written; none when the legend is hidden.
    public let legend: [RadarLegendEntry]
    public let title: DiagramTextBlock?
}

/// A curve of a radar chart with its points on the axes, in page coordinates.
public struct RadarLayoutCurve: Equatable, Sendable {
    /// The curve's place among the chart's curves, which picks its series color.
    public let seriesIndex: Int
    /// One point per axis.
    public let points: [CGPoint]
    /// How round its corners are; 0 for straight ones.
    public let tension: CGFloat
    /// Whether the corners are rounded (circular graticule) or straight (polygonal).
    public let isRounded: Bool
}

/// One row of the legend: a swatch in the curve's series color, then the curve's label.
public struct RadarLegendEntry: Equatable, Sendable {
    public let seriesIndex: Int
    public let swatch: CGRect
    public let text: DiagramTextBlock
}
