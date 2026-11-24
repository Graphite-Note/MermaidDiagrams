/**
 * File: RadarCurveSpline.swift
 * ----------------------------
 * Layer: Core
 * Description: The closed curve through a radar chart's points: a Catmull-Rom spline as cubic Bézier segments.
 *
 * Authors: Bahey Shalash
 * Version: 0.2
 * Date: 23/11/2026
 */

import CoreGraphics

/// The closed curve through a curve's points that Pele draws: a Catmull-Rom spline, each segment from a point to the next
/// a cubic Bézier whose control points lie a `tension` of the way along the chord of the neighbouring points; no tension
/// gives straight edges.
enum RadarCurveSpline {
    static func closedPath(through points: [CGPoint], tension: CGFloat) -> DiagramScenePath {
        var path = DiagramScenePath()
        guard let first = points.first else { return path }
        path.move(to: first)
        let count = points.count
        for index in 0..<count {
            let before = points[(index - 1 + count) % count]
            let from = points[index]
            let to = points[(index + 1) % count]
            let after = points[(index + 2) % count]
            path.addCurve(to: to, control1: CGPoint(x: from.x + (to.x - before.x) * tension, y: from.y + (to.y - before.y) * tension),
                          control2: CGPoint(x: to.x - (after.x - from.x) * tension, y: to.y - (after.y - from.y) * tension))
        }
        path.closeSubpath()
        return path
    }

    /// The straight-edged polygon through `points`, closed.
    static func closedPolygon(through points: [CGPoint]) -> DiagramScenePath {
        var path = DiagramScenePath()
        guard let first = points.first else { return path }
        path.move(to: first)
        for point in points.dropFirst() { path.addLine(to: point) }
        path.closeSubpath()
        return path
    }
}
