/**
 * File: RequirementRouteSegments.swift
 * ------------------------------------
 * Layer: Core
 * Description: A requirement relation's line through its route written straight into the layout's one list of path
 *              segments, already moved to its place on the page, as DiagramRouteDrawing draws the route into a path of
 *              its own and the layout then moves it.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 26/11/2026
 */

import CoreGraphics
import Foundation

/// Draws a route as `DiagramRouteDrawing.path(through:flowIsVertical:startTrim:endTrim:)` draws it, step for step: the
/// ends trimmed along the directions the route leaves and arrives in, then between two points in line a straight
/// segment, between two others one S along the flow. Each point is then moved by the layout's offset as
/// `DiagramPath.translate(by:)` moves it, and the segments are appended to a list the layout keeps for all its lines.
enum RequirementRouteSegments {
    /// The route through `points` (at least two, from the source's side to the target's), its start, its segments
    /// appended to `segments`, both moved by `offset`, and the unit directions it leaves and arrives in. `points` is
    /// trimmed where it stands.
    static func append(through points: ScratchSpan<CGPoint>, flowIsVertical: Bool, startTrim: CGFloat, offset: CGVector,
                       into segments: inout [DiagramPathSegment]) -> (start: CGPoint, startDirection: CGVector, endDirection: CGVector) {
        precondition(points.count >= 2, "a route has two points at least")
        let endTrim: CGFloat = 0
        let last = points.count - 1
        let startDirection = direction(from: points[0], to: points[1], flowIsVertical: flowIsVertical)
        let endDirection = direction(from: points[last - 1], to: points[last], flowIsVertical: flowIsVertical)
        points[0] = CGPoint(x: points[0].x + startDirection.dx * startTrim, y: points[0].y + startDirection.dy * startTrim)
        points[last] = CGPoint(x: points[last].x - endDirection.dx * endTrim, y: points[last].y - endDirection.dy * endTrim)
        for index in 1...last {
            let from = points[index - 1]
            let to = points[index]
            if isInLine(from, to) {
                segments.append(.line(to: to.translated(by: offset)))
            } else if flowIsVertical {
                let half = (to.y - from.y) / 2
                segments.append(.curve(to: to.translated(by: offset), control1: CGPoint(x: from.x, y: from.y + half).translated(by: offset),
                                       control2: CGPoint(x: to.x, y: to.y - half).translated(by: offset)))
            } else {
                let half = (to.x - from.x) / 2
                segments.append(.curve(to: to.translated(by: offset), control1: CGPoint(x: from.x + half, y: from.y).translated(by: offset),
                                       control2: CGPoint(x: to.x - half, y: to.y).translated(by: offset)))
            }
        }
        return (points[0].translated(by: offset), startDirection, endDirection)
    }

    /// The way the path heads from `from` to `to`: along the flow when an S joins them, straight at the other otherwise.
    private static func direction(from: CGPoint, to: CGPoint, flowIsVertical: Bool) -> CGVector {
        if !isInLine(from, to) {
            return flowIsVertical ? CGVector(dx: 0, dy: to.y >= from.y ? 1 : -1) : CGVector(dx: to.x >= from.x ? 1 : -1, dy: 0)
        }
        let length = max(hypot(to.x - from.x, to.y - from.y), 0.0001)
        return CGVector(dx: (to.x - from.x) / length, dy: (to.y - from.y) / length)
    }

    /// Two points are in line when they share a coordinate, to a hundredth of a point.
    private static func isInLine(_ first: CGPoint, _ second: CGPoint) -> Bool {
        abs(first.x - second.x) < 0.01 || abs(first.y - second.y) < 0.01
    }
}
