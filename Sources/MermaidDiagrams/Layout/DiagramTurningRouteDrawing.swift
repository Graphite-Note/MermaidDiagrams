/**
 * File: DiagramTurningRouteDrawing.swift
 * --------------------------------------
 * Layer: Core
 * Description: The path through a route that turns corners, as Pele's `routePath` draws it: an S between points not in
 *              line, a wide turn where the route turns from one way to the other, and a short straight run into a mark.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 19/11/2026
 */

import CoreGraphics
import Foundation

/// The path through a route as Pele's `routePath` (`svg/edges.ts`) draws a smooth one, for routes that turn corners at
/// right angles, as the lane layout's handoffs do: between two points not in line, an S that leaves and arrives along its
/// segment's flow, its handles half the way along it or less where it runs far across (Pele's `ease`); where the route turns
/// from running one way to running the other, a turn as wide as it can be, taking the whole of a leg that ends at a node
/// and half of a leg it shares with the next turn, its handles 0.62 of the way to the corner; a point part of the way along
/// one straight run adds nothing. An end whose mark sits on a bend runs straight into it for a little first: a quarter of
/// its last run, at most 6 points. `DiagramRouteDrawing`, which the other types draw with, turns no corner.
enum DiagramTurningRouteDrawing {
    /// How far the handles of a turn reach along its legs: a little more than a circle's, which makes the turn fuller.
    static let handle: CGFloat = 0.62
    /// How far an edge runs straight before a mark at its end, where it has the room.
    static let lead: CGFloat = 6

    /// - Parameter segmentsRunVertically: For each segment, whether its S leaves and arrives up or down the page.
    /// - Returns: The path, and the unit directions the edge leaves its source and arrives at its target in.
    static func path(through route: [CGPoint], segmentsRunVertically: [Bool], startTrim: CGFloat,
                     endTrim: CGFloat) -> (path: DiagramPath, startDirection: CGVector, endDirection: CGVector) {
        var points = route
        var axes = [segmentsRunVertically[0]] + segmentsRunVertically
        let startDirection = unit(points, 0, 1, isVertical: axes[1])
        let endDirection = unit(points, points.count - 2, points.count - 1, isVertical: axes[points.count - 1])
        points[0] = CGPoint(x: points[0].x + startDirection.dx * startTrim, y: points[0].y + startDirection.dy * startTrim)
        let last = points.count - 1
        points[last] = CGPoint(x: points[last].x - endDirection.dx * endTrim, y: points[last].y - endDirection.dy * endTrim)
        let arrives = endTrim > 0 && (!isAligned(points, last) || turns(points, last - 1)) ? leadLength(run: along(points, last, endDirection)) : 0
        let leaves = startTrim > 0 && (!isAligned(points, 1) || turns(points, 1)) ? leadLength(run: along(points, 1, startDirection)) : 0
        if arrives >= 1 {
            points.insert(CGPoint(x: points[last].x - endDirection.dx * arrives, y: points[last].y - endDirection.dy * arrives), at: last)
            axes.insert(axes[last], at: last)
        }
        if leaves >= 1 {
            points.insert(CGPoint(x: points[0].x + startDirection.dx * leaves, y: points[0].y + startDirection.dy * leaves), at: 1)
            axes.insert(axes[1], at: 1)
        }
        return (DiagramPath(start: points[0], segments: segments(points, axes: axes)), startDirection, endDirection)
    }

    /// The segments after the start, an S, a line or a turn at each point.
    private static func segments(_ points: [CGPoint], axes: [Bool]) -> [DiagramPathSegment] {
        let last = points.count - 1
        var segments: [DiagramPathSegment] = []
        var at = points[0]
        func line(to point: CGPoint) {
            guard abs(point.x - at.x) >= 0.01 || abs(point.y - at.y) >= 0.01 else { return }
            segments.append(.line(to: point))
            at = point
        }
        for index in 1...last {
            let point = points[index]
            if !isAligned(points, index) {
                let isDown = axes[index]
                let alongRun = isDown ? point.y - at.y : point.x - at.x
                let reach = abs(alongRun) * ease(across: isDown ? point.x - at.x : point.y - at.y, along: alongRun) * (alongRun < 0 ? -1 : 1)
                let handle = isDown ? CGVector(dx: 0, dy: reach) : CGVector(dx: reach, dy: 0)
                segments.append(.curve(to: point, control1: CGPoint(x: at.x + handle.dx, y: at.y + handle.dy),
                                       control2: CGPoint(x: point.x - handle.dx, y: point.y - handle.dy)))
                at = point
            } else if !turns(points, index) {
                // A point part of the way along one straight run adds nothing to the path.
                if index < last, isAligned(points, index + 1),
                   (point.x - points[index - 1].x) * (points[index + 1].x - point.x) + (point.y - points[index - 1].y) * (points[index + 1].y - point.y) > 0 { continue }
                line(to: point)
            } else {
                let before = turns(points, index - 1) ? length(points, index) / 2 : length(points, index)
                let after = turns(points, index + 1) ? length(points, index + 1) / 2 : length(points, index + 1)
                let into = unit(points, index - 1, index, isVertical: axes[index])
                let out = unit(points, index, index + 1, isVertical: axes[index + 1])
                line(to: CGPoint(x: point.x - into.dx * before, y: point.y - into.dy * before))
                let end = CGPoint(x: point.x + out.dx * after, y: point.y + out.dy * after)
                segments.append(.curve(to: end, control1: CGPoint(x: point.x - into.dx * before * (1 - handle), y: point.y - into.dy * before * (1 - handle)),
                                       control2: CGPoint(x: point.x + out.dx * after * (1 - handle), y: point.y + out.dy * after * (1 - handle))))
                at = end
            }
        }
        return segments
    }

    /// Pele's `ease`: how far along the flow the handles of an S reach, as a share of the way it travels along it; half for
    /// an even S, down to a quarter for one that runs sixteen times as far across as along.
    static func ease(across: CGFloat, along: CGFloat) -> CGFloat {
        max(0.25, min(0.5, 4 * abs(along) / (abs(across) == 0 ? 1 : abs(across))))
    }

    /// Of the way from an end's run to where it bends, what runs straight into its mark: a quarter, at most 6 points.
    private static func leadLength(run: CGFloat) -> CGFloat {
        min(lead, run / 4)
    }

    private static func isAligned(_ points: [CGPoint], _ index: Int) -> Bool {
        abs(points[index].x - points[index - 1].x) < 0.01 || abs(points[index].y - points[index - 1].y) < 0.01
    }

    private static func length(_ points: [CGPoint], _ index: Int) -> CGFloat {
        abs(points[index].x - points[index - 1].x) + abs(points[index].y - points[index - 1].y)
    }

    /// Whether the route turns a corner at `index`, from running one way to running the other.
    private static func turns(_ points: [CGPoint], _ index: Int) -> Bool {
        guard index > 0, index < points.count - 1, isAligned(points, index), isAligned(points, index + 1),
              length(points, index) >= 0.01, length(points, index + 1) >= 0.01 else { return false }
        return (abs(points[index].x - points[index - 1].x) < 0.01) != (abs(points[index + 1].x - points[index].x) < 0.01)
    }

    /// How far the run into `index` goes along `direction`.
    private static func along(_ points: [CGPoint], _ index: Int, _ direction: CGVector) -> CGFloat {
        abs(points[index].x - points[index - 1].x) * abs(direction.dx) + abs(points[index].y - points[index - 1].y) * abs(direction.dy)
    }

    /// The way from one point to the next: along the flow where an S joins them, straight at the other otherwise.
    private static func unit(_ points: [CGPoint], _ from: Int, _ to: Int, isVertical: Bool) -> CGVector {
        let delta = CGVector(dx: points[to].x - points[from].x, dy: points[to].y - points[from].y)
        guard abs(delta.dx) < 0.01 || abs(delta.dy) < 0.01 else {
            return isVertical ? CGVector(dx: 0, dy: delta.dy < 0 ? -1 : 1) : CGVector(dx: delta.dx < 0 ? -1 : 1, dy: 0)
        }
        let length = hypot(delta.dx, delta.dy)
        return length == 0 ? delta : CGVector(dx: delta.dx / length, dy: delta.dy / length)
    }
}
