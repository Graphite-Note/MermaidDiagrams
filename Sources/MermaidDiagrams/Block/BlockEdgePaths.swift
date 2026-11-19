/**
 * File: BlockEdgePaths.swift
 * --------------------------
 * Layer: Core
 * Description: The lines of a block diagram's edges as Pele draws them: through two or three points with the bend
 *              rounded and room left for the marks, and a block's loops as arcs round its top right corner.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 19/11/2026
 */

import CoreGraphics
import Foundation

/// An edge's drawn line and the points and directions its marks are drawn at, Pele's `EdgePath`.
struct BlockEdgeLine {
    let path: DiagramPath
    let start: CGPoint
    /// The direction the start's mark points in.
    let startDirection: CGVector
    let end: CGPoint
    let endDirection: CGVector
}

/// Pele's `trace`, `loopArc` and `loopPath`.
enum BlockEdgePaths {
    /// The most a bend is rounded by.
    static let cornerRadius: CGFloat = 8

    /// The line through two or three points, the bend rounded and the ends cut back by the marks' trims.
    static func traced(_ points: [CGPoint], startTrim: CGFloat, endTrim: CGFloat) -> BlockEdgeLine {
        let start = points[0]
        let end = points[points.count - 1]
        let (first, firstLength) = unit(from: start, to: points[1])
        let (last, lastLength) = unit(from: points[points.count - 2], to: end)
        var startTrim = startTrim
        var endTrim = endTrim
        if points.count == 2, startTrim + endTrim > firstLength {
            let scale = firstLength / (startTrim + endTrim)
            startTrim *= scale
            endTrim *= scale
        }
        startTrim = min(startTrim, firstLength)
        endTrim = min(endTrim, lastLength)
        var segments: [DiagramPathSegment] = []
        if points.count == 3 {
            let corner = points[1]
            let radius = max(0, min(cornerRadius, firstLength - startTrim, lastLength - endTrim))
            let into = CGPoint(x: corner.x - first.dx * radius, y: corner.y - first.dy * radius)
            let out = CGPoint(x: corner.x + last.dx * radius, y: corner.y + last.dy * radius)
            segments.append(.line(to: into))
            segments.append(quadratic(from: into, control: corner, to: out))
        }
        segments.append(.line(to: CGPoint(x: end.x - last.dx * endTrim, y: end.y - last.dy * endTrim)))
        let path = DiagramPath(start: CGPoint(x: start.x + first.dx * startTrim, y: start.y + first.dy * startTrim), segments: segments)
        return BlockEdgeLine(path: path, start: start, startDirection: CGVector(dx: -first.dx, dy: -first.dy), end: end, endDirection: last)
    }

    /// The quadratic curve SVG's `Q` draws, as the cubic curve it is.
    static func quadratic(from start: CGPoint, control: CGPoint, to end: CGPoint) -> DiagramPathSegment {
        .curve(to: end, control1: CGPoint(x: start.x + 2 / 3 * (control.x - start.x), y: start.y + 2 / 3 * (control.y - start.y)),
               control2: CGPoint(x: end.x + 2 / 3 * (control.x - end.x), y: end.y + 2 / 3 * (control.y - end.y)))
    }

    /// The unit vector from `start` to `end` (zero length taken as one) and the length.
    private static func unit(from start: CGPoint, to end: CGPoint) -> (CGVector, CGFloat) {
        let length = hypot(end.x - start.x, end.y - start.y)
        let divisor = length == 0 ? 1 : length
        return (CGVector(dx: (end.x - start.x) / divisor, dy: (end.y - start.y) / divisor), length)
    }

    /// The circle the `count`-th loop on `outline` lies on, and the angles it leaves and returns at: round the top right
    /// corner of a box, or round the matching point of a circle's or a diamond's outline.
    static func loopArc(on outline: BlockOutline, count: Int) -> (center: CGPoint, radius: CGFloat, leaving: CGFloat, returning: CGFloat) {
        let halfWidth = outline.size.width / 2
        let halfHeight = outline.size.height / 2
        let radius = max(1, min(10 + 5 * CGFloat(count - 1), halfWidth, halfHeight))
        let center = outline.center
        switch outline.form {
        case .round:
            let point = CGPoint(x: center.x + halfWidth * CGFloat(0.5).squareRoot(), y: center.y - halfWidth * CGFloat(0.5).squareRoot())
            let half = 2 * asin(min(1, radius / (2 * halfWidth)))
            func angle(_ at: CGFloat) -> CGFloat { atan2(center.y - halfWidth * sin(at) - point.y, center.x + halfWidth * cos(at) - point.x) }
            return (point, radius, angle(.pi / 4 + half), angle(.pi / 4 - half))
        case .diamond:
            let slope = atan2(halfHeight, halfWidth)
            return (CGPoint(x: center.x + halfWidth / 2, y: center.y - halfHeight / 2), radius, slope + .pi, slope)
        default:
            return (CGPoint(x: center.x + halfWidth, y: center.y - halfHeight), radius, .pi, .pi / 2)
        }
    }

    /// The `count`-th loop on `outline`, cut back at its ends by the marks' trims, each mark lying along the chord it
    /// covers so that it follows the curve.
    static func loop(on outline: BlockOutline, count: Int, startTrim: CGFloat, endTrim: CGFloat) -> BlockEdgeLine {
        let (center, radius, leaving, returning) = loopArc(on: outline, count: count)
        let from = leaving + startTrim / radius
        let to = returning - endTrim / radius
        var sweep = (to - from).truncatingRemainder(dividingBy: 2 * .pi)
        if sweep <= 0 { sweep += 2 * .pi }
        func point(_ angle: CGFloat) -> CGPoint { CGPoint(x: center.x + radius * cos(angle), y: center.y + radius * sin(angle)) }
        let trimmedStart = point(from)
        let trimmedEnd = point(to)
        let start = point(leaving)
        let end = point(returning)
        let startChord = hypot(start.x - trimmedStart.x, start.y - trimmedStart.y)
        let endChord = hypot(end.x - trimmedEnd.x, end.y - trimmedEnd.y)
        let startDirection = startChord > 0 ? CGVector(dx: (start.x - trimmedStart.x) / startChord, dy: (start.y - trimmedStart.y) / startChord)
            : CGVector(dx: sin(leaving), dy: -cos(leaving))
        let endDirection = endChord > 0 ? CGVector(dx: (end.x - trimmedEnd.x) / endChord, dy: (end.y - trimmedEnd.y) / endChord)
            : CGVector(dx: -sin(returning), dy: cos(returning))
        let path = DiagramPath(start: trimmedStart, segments: arc(center: center, radius: radius, from: from, sweep: sweep))
        return BlockEdgeLine(path: path, start: start, startDirection: startDirection, end: end, endDirection: endDirection)
    }

    /// An arc of a circle swept with increasing angle (clockwise on a page whose y runs down), as cubic curves of at most
    /// a quarter turn each.
    static func arc(center: CGPoint, radius: CGFloat, from start: CGFloat, sweep: CGFloat) -> [DiagramPathSegment] {
        let count = max(1, Int((sweep / (.pi / 2)).rounded(.up)))
        let step = sweep / CGFloat(count)
        let reach = 4 / 3 * tan(step / 4) * radius
        var segments: [DiagramPathSegment] = []
        var angle = start
        for _ in 0..<count {
            let next = angle + step
            let from = CGPoint(x: center.x + radius * cos(angle), y: center.y + radius * sin(angle))
            let to = CGPoint(x: center.x + radius * cos(next), y: center.y + radius * sin(next))
            segments.append(.curve(to: to, control1: CGPoint(x: from.x - reach * sin(angle), y: from.y + reach * cos(angle)),
                                   control2: CGPoint(x: to.x + reach * sin(next), y: to.y - reach * cos(next))))
            angle = next
        }
        return segments
    }
}
