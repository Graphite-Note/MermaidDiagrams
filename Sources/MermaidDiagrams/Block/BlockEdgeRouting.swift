/**
 * File: BlockEdgeRouting.swift
 * ----------------------------
 * Layer: Core
 * Description: Routes a block diagram's edges as Pele's block renderer does: straight between blocks that share a row
 *              or a column, else one bend, or straight across, whichever crosses the fewest other blocks.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 19/11/2026
 */

import CoreGraphics

/// A block as an edge meets it: its center, its drawn size and what its outline is.
struct BlockOutline: Equatable {
    enum Form: Equatable {
        /// A circle or a double circle.
        case round
        case diamond
        /// Another of the flowchart's shapes, whose outline lies inside its box by its inset.
        case shape(FlowchartNodeShape)
        /// An arrow, by the axis its shaft runs along (nil for one drawn as a box with points).
        case arrow(BlockArrowAxis?)
        /// A composite's box.
        case box
    }

    let center: CGPoint
    let size: CGSize
    let form: Form

    /// Where a vertical line at `x` meets the outline, below the center (`sign` 1) or above it (-1).
    func verticalEdge(atX x: CGFloat, sign: CGFloat) -> CGFloat {
        let halfWidth = size.width / 2
        let halfHeight = size.height / 2
        let offset = abs(x - center.x)
        var reach = halfHeight
        switch form {
        case .round: reach = max(halfWidth * halfWidth - offset * offset, 0).squareRoot()
        case .diamond: reach = halfHeight * max(1 - offset / halfWidth, 0)
        case .shape(let shape): reach = halfHeight - FlowchartShapeGeometry.inset(of: shape, size: size, side: sign > 0 ? .bottom : .top, offset: 0)
        case .arrow(.across): reach = halfHeight - BlockArrowShape.overhang
        case .arrow, .box: break
        }
        return center.y + sign * reach
    }

    /// Where a horizontal line at `y` meets the outline, right of the center (`sign` 1) or left of it (-1).
    func horizontalEdge(atY y: CGFloat, sign: CGFloat) -> CGFloat {
        let halfWidth = size.width / 2
        let halfHeight = size.height / 2
        let offset = abs(y - center.y)
        var reach = halfWidth
        switch form {
        case .round: reach = max(halfHeight * halfHeight - offset * offset, 0).squareRoot()
        case .diamond: reach = halfWidth * max(1 - offset / halfHeight, 0)
        case .shape(let shape): reach = halfWidth - FlowchartShapeGeometry.inset(of: shape, size: size, side: sign > 0 ? .right : .left, offset: 0)
        case .arrow(.down): reach = halfWidth - BlockArrowShape.overhang
        case .arrow, .box: break
        }
        return center.x + sign * reach
    }

    /// Where the line from the center toward `target` leaves the outline.
    func border(toward target: CGPoint) -> CGPoint {
        let offset = CGVector(dx: target.x - center.x, dy: target.y - center.y)
        let halfWidth = size.width / 2
        let halfHeight = size.height / 2
        var scale: CGFloat
        switch form {
        case .round: scale = halfWidth / nonzero(hypot(offset.dx, offset.dy))
        case .diamond: scale = 1 / nonzero(abs(offset.dx) / halfWidth + abs(offset.dy) / halfHeight)
        default:
            scale = min(offset.dx == 0 ? .infinity : halfWidth / abs(offset.dx), offset.dy == 0 ? .infinity : halfHeight / abs(offset.dy))
        }
        if scale == .infinity { scale = 0 }
        return CGPoint(x: center.x + offset.dx * scale, y: center.y + offset.dy * scale)
    }

    /// JavaScript's `value || 1`: 1 for zero (and for not a number).
    private func nonzero(_ value: CGFloat) -> CGFloat {
        value == 0 || value.isNaN ? 1 : value
    }

    /// Whether the segment from `start` to `end` crosses the outline's box drawn a point inside its edges.
    func isCrossed(from start: CGPoint, to end: CGPoint) -> Bool {
        let left = center.x - size.width / 2 + 1
        let right = center.x + size.width / 2 - 1
        let top = center.y - size.height / 2 + 1
        let bottom = center.y + size.height / 2 - 1
        let isBesideAcross = (start.x < left && end.x < left) || (start.x > right && end.x > right)
        let isBesideDown = (start.y < top && end.y < top) || (start.y > bottom && end.y > bottom)
        if isBesideAcross || isBesideDown { return false }
        if start.x == end.x || start.y == end.y { return true }
        // A diagonal whose bounds overlap the box hits it unless all four corners are on one side of it.
        let delta = CGVector(dx: end.x - start.x, dy: end.y - start.y)
        func side(_ x: CGFloat, _ y: CGFloat) -> CGFloat {
            let cross: CGFloat = delta.dx * (y - start.y) - delta.dy * (x - start.x)
            return cross > 0 ? 1 : cross < 0 ? -1 : 0
        }
        let first = side(left, top)
        return first == 0 || side(right, top) != first || side(right, bottom) != first || side(left, bottom) != first
    }
}

/// Pele's `routeEdge` and `hits`.
enum BlockEdgeRouting {
    /// The route from `source` to `target`: two points for a straight line, three for a bend. Edges between the same
    /// two blocks are spread `shift` apart; `obstacles` (nil past Pele's budget) are the blocks a bend tries to miss,
    /// by their place in `outlines`.
    static func route(from source: Int, to target: Int, outlines: [BlockOutline], shift: CGFloat, obstacles: [Int]?) -> [CGPoint] {
        let start = outlines[source]
        let end = outlines[target]
        let left = max(start.center.x - start.size.width / 2, end.center.x - end.size.width / 2)
        let right = min(start.center.x + start.size.width / 2, end.center.x + end.size.width / 2)
        let top = max(start.center.y - start.size.height / 2, end.center.y - end.size.height / 2)
        let bottom = min(start.center.y + start.size.height / 2, end.center.y + end.size.height / 2)
        let overlapsAcross = right - left > 6
        let overlapsDown = bottom - top > 6
        if overlapsAcross, overlapsDown { return nested(start, end) }
        if overlapsAcross {
            let margin = min(6, (right - left) / 2)
            let x = min(max((left + right) / 2 + shift, left + margin), right - margin)
            let down: CGFloat = end.center.y > start.center.y ? 1 : -1
            return [CGPoint(x: x, y: start.verticalEdge(atX: x, sign: down)), CGPoint(x: x, y: end.verticalEdge(atX: x, sign: -down))]
        }
        if overlapsDown {
            let margin = min(6, (bottom - top) / 2)
            let y = min(max((top + bottom) / 2 + shift, top + margin), bottom - margin)
            let toRight: CGFloat = end.center.x > start.center.x ? 1 : -1
            return [CGPoint(x: start.horizontalEdge(atY: y, sign: toRight), y: y), CGPoint(x: end.horizontalEdge(atY: y, sign: -toRight), y: y)]
        }
        return bend(from: source, to: target, outlines: outlines, obstacles: obstacles)
    }

    /// One block inside the other: the inner one joined to the nearest side of the outer one.
    private static func nested(_ start: BlockOutline, _ end: BlockOutline) -> [CGPoint] {
        let startIsInner = start.size.width * start.size.height <= end.size.width * end.size.height
        let inner = startIsInner ? start : end
        let outer = startIsInner ? end : start
        let up = inner.center.y - inner.size.height / 2 - (outer.center.y - outer.size.height / 2)
        let down = outer.center.y + outer.size.height / 2 - (inner.center.y + inner.size.height / 2)
        let left = inner.center.x - inner.size.width / 2 - (outer.center.x - outer.size.width / 2)
        let right = outer.center.x + outer.size.width / 2 - (inner.center.x + inner.size.width / 2)
        let least = min(up, down, left, right)
        let points: [CGPoint]
        if least == down {
            points = [CGPoint(x: inner.center.x, y: inner.verticalEdge(atX: inner.center.x, sign: 1)), CGPoint(x: inner.center.x, y: outer.center.y + outer.size.height / 2)]
        } else if least == up {
            points = [CGPoint(x: inner.center.x, y: inner.verticalEdge(atX: inner.center.x, sign: -1)), CGPoint(x: inner.center.x, y: outer.center.y - outer.size.height / 2)]
        } else if least == right {
            points = [CGPoint(x: inner.horizontalEdge(atY: inner.center.y, sign: 1), y: inner.center.y), CGPoint(x: outer.center.x + outer.size.width / 2, y: inner.center.y)]
        } else {
            points = [CGPoint(x: inner.horizontalEdge(atY: inner.center.y, sign: -1), y: inner.center.y), CGPoint(x: outer.center.x - outer.size.width / 2, y: inner.center.y)]
        }
        return startIsInner ? points : points.reversed()
    }

    /// Blocks that share neither a row nor a column: a bend along the wider way, the other bend when it crosses fewer
    /// blocks, or a straight line between their borders when that crosses fewer still.
    private static func bend(from source: Int, to target: Int, outlines: [BlockOutline], obstacles: [Int]?) -> [CGPoint] {
        let start = outlines[source]
        let end = outlines[target]
        let toRight: CGFloat = end.center.x > start.center.x ? 1 : -1
        let down: CGFloat = end.center.y > start.center.y ? 1 : -1
        let across = [CGPoint(x: start.horizontalEdge(atY: start.center.y, sign: toRight), y: start.center.y), CGPoint(x: end.center.x, y: start.center.y),
                      CGPoint(x: end.center.x, y: end.verticalEdge(atX: end.center.x, sign: -down))]
        let along = [CGPoint(x: start.center.x, y: start.verticalEdge(atX: start.center.x, sign: down)), CGPoint(x: start.center.x, y: end.center.y),
                     CGPoint(x: end.horizontalEdge(atY: end.center.y, sign: -toRight), y: end.center.y)]
        let isWide = abs(end.center.x - start.center.x) >= abs(end.center.y - start.center.y)
        var best = isWide ? across : along
        guard let obstacles else { return best }
        var least = hits(best, source: source, target: target, outlines: outlines, obstacles: obstacles)
        guard least > 0 else { return best }
        let other = isWide ? along : across
        let count = hits(other, source: source, target: target, outlines: outlines, obstacles: obstacles)
        if count < least {
            best = other
            least = count
        }
        guard least > 0 else { return best }
        let direct = [start.border(toward: end.center), end.border(toward: start.center)]
        return hits(direct, source: source, target: target, outlines: outlines, obstacles: obstacles) < least ? direct : best
    }

    /// How many obstacles other than the two ends the route crosses.
    static func hits(_ points: [CGPoint], source: Int, target: Int, outlines: [BlockOutline], obstacles: [Int]) -> Int {
        var count = 0
        for obstacle in obstacles where obstacle != source && obstacle != target {
            for index in 0..<(points.count - 1) where outlines[obstacle].isCrossed(from: points[index], to: points[index + 1]) {
                count += 1
                break
            }
        }
        return count
    }
}
