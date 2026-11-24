/**
 * File: RadarCurveSpline.swift
 * ----------------------------
 * Layer: Core
 * Description: The closed curve through a radar chart's points: a Catmull-Rom spline as cubic Bézier segments, recorded
 *              into a Core Graphics path or a lane of the scene's workspace alike.
 *
 * Authors: Bahey Shalash
 * Version: 0.2
 * Date: 24/11/2026
 */

import CoreGraphics

/// The closed curve through a curve's points that Pele draws: a Catmull-Rom spline, each segment from a point to the next
/// a cubic Bézier whose control points lie a `tension` of the way along the chord of the neighbouring points; no tension
/// gives straight edges.
enum RadarCurveSpline {
    static func closedPath(through points: [CGPoint], tension: CGFloat) -> CGPath {
        let path = CGMutablePath()
        addClosedCurve(through: points, tension: tension, to: DiagramCoreGraphicsPath(mutable: path))
        return path
    }

    /// The straight-edged closed polygon through the points, for a radar drawn without curves and a polygonal graticule.
    static func closedPolygon(through points: [CGPoint]) -> CGPath {
        let path = CGMutablePath()
        addClosedPolygon(through: points, to: DiagramCoreGraphicsPath(mutable: path))
        return path
    }

    /// The spline's elements recorded into `path`, which is empty: nothing for no points.
    static func addClosedCurve<Path: DiagramPathRecording>(through points: [CGPoint], tension: CGFloat, to path: Path) {
        guard let first = points.first else { return }
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
    }

    /// The polygon's elements recorded into `path`, which is empty: nothing for no points.
    static func addClosedPolygon<Path: DiagramPathRecording>(through points: [CGPoint], to path: Path) {
        guard let first = points.first else { return }
        path.move(to: first)
        for point in points.dropFirst() { path.addLine(to: point) }
        path.closeSubpath()
    }
}
