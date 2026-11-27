/**
 * File: EntityRelationshipRouteSegments.swift
 * -------------------------------------------
 * Layer: Core
 * Description: An entity relationship's line through its route written straight into the layout's one list of path
 *              segments, as DiagramRouteDrawing draws a route into a path of its own: S curves along the flow, or along
 *              each segment's own flow through groups' boxes.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 26/11/2026
 */

import CoreGraphics
import Foundation

/// Draws a route as `DiagramRouteDrawing.path(through:segmentsRunVertically:startTrim:endTrim:)` draws it with no trim,
/// step for step: the ends moved by no trim along the directions the route leaves and arrives in (as that drawing moves
/// them, so that even a zero's sign is its), then between two points in line a straight segment, between two others one
/// S along the flow its segment follows. The segments are appended to a list the layout keeps for all its lines.
enum EntityRelationshipRouteSegments {
    /// The route through `points` (at least two), each segment following the flow `flowIsVertical` gives every one, or
    /// `axes[i]` gives segment `i` when given; its start, its segments appended to `segments`, and the unit directions
    /// it leaves and arrives in. `points` is trimmed where it stands.
    static func append(through points: ScratchSpan<CGPoint>, flowIsVertical: Bool, axes: ScratchSpan<Bool>?,
                       into segments: inout [DiagramPathSegment]) -> (start: CGPoint, startDirection: CGVector, endDirection: CGVector) {
        precondition(points.count >= 2 && (axes == nil || axes?.count == points.count - 1), "a route has two points at least and an axis a segment")
        let trim: CGFloat = 0
        let last = points.count - 1
        let startDirection = direction(from: points[0], to: points[1], flowIsVertical: axes?[0] ?? flowIsVertical)
        let endDirection = direction(from: points[last - 1], to: points[last], flowIsVertical: axes?[last - 1] ?? flowIsVertical)
        points[0] = CGPoint(x: points[0].x + startDirection.dx * trim, y: points[0].y + startDirection.dy * trim)
        points[last] = CGPoint(x: points[last].x - endDirection.dx * trim, y: points[last].y - endDirection.dy * trim)
        for index in 1...last {
            let from = points[index - 1]
            let to = points[index]
            if isInLine(from, to) {
                segments.append(.line(to: to))
            } else if axes?[index - 1] ?? flowIsVertical {
                let half = (to.y - from.y) / 2
                segments.append(.curve(to: to, control1: CGPoint(x: from.x, y: from.y + half), control2: CGPoint(x: to.x, y: to.y - half)))
            } else {
                let half = (to.x - from.x) / 2
                segments.append(.curve(to: to, control1: CGPoint(x: from.x + half, y: from.y), control2: CGPoint(x: to.x - half, y: to.y)))
            }
        }
        return (points[0], startDirection, endDirection)
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
    static func isInLine(_ first: CGPoint, _ second: CGPoint) -> Bool {
        abs(first.x - second.x) < 0.01 || abs(first.y - second.y) < 0.01
    }

    /// The segments from `range` of `segments`, each point moved by `offset` where it stands, as `DiagramPath.translate`
    /// moves them.
    static func translate(_ range: Range<Int>, of segments: inout [DiagramPathSegment], by offset: CGVector) {
        for index in range {
            switch segments[index] {
            case .line(let end): segments[index] = .line(to: end.translated(by: offset))
            case .curve(let end, let firstControl, let secondControl):
                segments[index] = .curve(to: end.translated(by: offset), control1: firstControl.translated(by: offset),
                                         control2: secondControl.translated(by: offset))
            }
        }
    }
}
