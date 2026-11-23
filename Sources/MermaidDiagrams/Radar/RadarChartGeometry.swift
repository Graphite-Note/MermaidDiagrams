/**
 * File: RadarChartGeometry.swift
 * ------------------------------
 * Layer: Core
 * Description: The circle a radar chart is drawn on: its radius, its axes' directions, its rings and where each curve's
 *              values lie.
 *
 * Authors: Bahey Shalash
 * Version: 0.2
 * Date: 23/11/2026
 */

import CoreGraphics

/// The numbers a radar chart's layout takes from its chart, around the chart's own origin: the radius, each axis's
/// direction, the rings, and each drawn curve's points.
struct RadarChartGeometry {
    let radius: CGFloat
    let axisDirections: [CGPoint]
    let ringRadii: [CGFloat]
    let spokeLength: CGFloat
    /// How far from the origin an axis's label stands before it is moved off its spoke.
    let labelDistance: CGFloat
    /// The circle's box and the margins around it.
    let frameWithMargins: CGRect
    /// The curves with a value for every axis, around the origin.
    let curves: [RadarLayoutCurve]

    init(chart: RadarChart) {
        self.init(chart: chart, width: chart.appearance.width, height: chart.appearance.height)
    }

    /// The geometry of a chart whose circle's box is `width` by `height` rather than its own (`width` and `height`), as
    /// Pele's `fitWidth` draws a radar chart narrower.
    init(chart: RadarChart, width: CGFloat, height: CGFloat) {
        let appearance = chart.appearance
        let circleRadius = min(width, height) / 2
        radius = circleRadius
        let count = chart.axes.count
        axisDirections = chart.axes.indices.map { index in
            let angle = 2 * Double.pi * Double(index) / Double(count) - Double.pi / 2
            return CGPoint(x: cos(angle), y: sin(angle))
        }
        let tickCount = Int(chart.options.tickCount.rounded(.up))
        ringRadii = (0..<tickCount).map { index in min(circleRadius, circleRadius * CGFloat(index + 1) / CGFloat(chart.options.tickCount)) }
        spokeLength = circleRadius * appearance.axisScaleFactor
        labelDistance = circleRadius * appearance.axisLabelFactor + RadarChartLayoutEngine.labelOffset
        frameWithMargins = CGRect(x: -width / 2 - appearance.marginLeft, y: -height / 2 - appearance.marginTop,
                                  width: width + appearance.marginLeft + appearance.marginRight,
                                  height: height + appearance.marginTop + appearance.marginBottom)
        let valueRange = Self.valueRange(of: chart)
        let directions = axisDirections
        curves = chart.curves.enumerated().compactMap { index, curve in
            // A curve without a value for every axis is left out, as Mermaid leaves it; its legend entry stays.
            guard curve.values.count == count else { return nil }
            let points = zip(curve.values, directions).map { value, direction -> CGPoint in
                let distance = Self.relativeRadius(of: value, minimum: valueRange.minimum, maximum: valueRange.maximum, radius: Double(circleRadius))
                let safe = distance.isFinite ? CGFloat(distance) : 0
                return CGPoint(x: direction.x * safe, y: direction.y * safe)
            }
            return RadarLayoutCurve(seriesIndex: index, points: points, tension: appearance.curveTension, isRounded: chart.options.graticule == .circle)
        }
    }

    /// The values at the center and at the rim: the chart's `min` and `max`, the largest value of any curve when `max` is not
    /// written (minus infinity when there is no value at all).
    private static func valueRange(of chart: RadarChart) -> (minimum: Double, maximum: Double) {
        if let maximum = chart.options.maximum { return (chart.options.minimum, maximum) }
        var largest = -Double.infinity
        for curve in chart.curves { for value in curve.values where value > largest { largest = value } }
        return (chart.options.minimum, largest)
    }

    /// How far from the center a value lies: the value cut to `minimum` and `maximum`, and its distance from the minimum as a
    /// share of the range, of `radius`. Multiplying first keeps the rounding of Pele's, unless that overflows.
    static func relativeRadius(of value: Double, minimum: Double, maximum: Double, radius: Double) -> Double {
        let clipped = Swift.min(Swift.max(value, minimum), maximum)
        let scaled = radius * (clipped - minimum)
        return scaled.isFinite ? scaled / (maximum - minimum) : radius * ((clipped - minimum) / (maximum - minimum))
    }
}
