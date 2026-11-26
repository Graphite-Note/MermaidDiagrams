/**
 * File: C4RelationRouting.swift
 * -----------------------------
 * Layer: Core
 * Description: Routes a C4 relation between two laid-out boxes as Pele's route.ts does: a loop from a box to itself, a
 *              short line from a boundary to what it holds, a straight line between outlines through a shared column or
 *              row, and, when a shape stands in the way, a line with corners around it.
 *
 * Authors: Bahey Shalash
 * Version: 0.3
 * Date: 26/11/2026
 */

import CoreGraphics

/// A routed relation: its line, where its arrowheads go and which way they point, the stretch its label may sit on, the
/// side of that stretch the label is pushed to (a unit vector, zero to center it), how far it may lean instead, the
/// widest the label should be, and the corners of the line as x, y pairs (none for a loop), all kept in place.
struct C4Route {
    var path: C4RoutePath
    var start: CGPoint
    var startDirection: CGVector
    var end: CGPoint
    var endDirection: CGVector
    var labelStretchStart: CGPoint
    var labelStretchEnd: CGPoint
    var labelSide = CGVector.zero
    /// When above zero, the label stays over the line and moves `labelSide`'s way by at most this much.
    var labelLean: CGFloat = 0
    var labelRoom = C4Metrics.wideLabelWidth
    var points: C4Numbers
}

/// Routes relations one after another, each kept apart from those before it (`lanes`). `obstacles` are the shapes a
/// line steers clear of, the first boxes of `boxes`; nil skips that check, when the diagram is too large for it.
struct C4Router {
    let boxes: [C4RouteBox]
    let obstacles: Range<Int>?
    var lanes = C4Lanes()

    /// The route from box `first` to box `second`. `shift` moves the line sideways when another runs the opposite way.
    mutating func route(from first: Int, to second: Int, shift: CGFloat, startTrim: CGFloat, endTrim: CGFloat) -> C4Route {
        if first == second { return Self.loop(around: boxes[first], startTrim: startTrim, endTrim: endTrim) }
        let (start, end) = Self.connect(boxes[first], boxes[second], shift: shift)
        let isUpright = start.x == end.x
        let isLevel = start.y == end.y
        let isBlocked = isBlockedBetween(first, second, from: start, to: end)
        if isBlocked, !isUpright, !isLevel {
            if let around = elbow(from: first, to: second, startTrim: startTrim, endTrim: endTrim) { return around }
            lanes.squeezedCount += 1
        }
        if isBlocked, isUpright || isLevel {
            return detour(from: first, to: second, straightStart: start, straightEnd: end, startTrim: startTrim, endTrim: endTrim)
        }
        return straight(from: start, to: end, shift: shift, startTrim: startTrim, endTrim: endTrim)
    }

    /// Whether a shape other than the two ends stands on the straight line, when neither end holds the other.
    private func isBlockedBetween(_ first: Int, _ second: Int, from start: CGPoint, to end: CGPoint) -> Bool {
        guard let obstacles, !boxes[first].contains(boxes[second]), !boxes[second].contains(boxes[first]) else { return false }
        return obstacles.contains { other in other != first && other != second && Self.stands(boxes[other], on: start, end) }
    }

    static func stands(_ box: C4RouteBox, on start: CGPoint, _ end: CGPoint) -> Bool {
        C4RouteGeometry.hitRectangle(left: box.x, top: box.y, right: box.right, bottom: box.bottom, x: start.x, y: start.y,
                                     deltaX: end.x - start.x, deltaY: end.y - start.y) <= 1
    }

    /// Whether the line through `points` keeps clear of every shape but its two ends.
    func isClear<Points: RandomAccessCollection<CGFloat>>(_ points: Points, of first: Int, _ second: Int) -> Bool where Points.Index == Int {
        guard let obstacles else { return true }
        return !obstacles.contains { other in
            other != first && other != second
                && C4RouteGeometry.crosses(points, left: boxes[other].x, top: boxes[other].y, right: boxes[other].right, bottom: boxes[other].bottom)
        }
    }

    // MARK: - Straight lines

    private mutating func straight(from start: CGPoint, to end: CGPoint, shift: CGFloat, startTrim: CGFloat, endTrim: CGFloat) -> C4Route {
        let length = hypot(end.x - start.x, end.y - start.y)
        let usedLength = length == 0 ? 1 : length
        let directionX = (end.x - start.x) / usedLength
        let directionY = (end.y - start.y) / usedLength
        if start.x == end.x || start.y == end.y { lanes.take(C4Numbers(start.x, start.y, end.x, end.y)) }
        let path = C4RoutePath(start: CGPoint(x: start.x + directionX * startTrim, y: start.y + directionY * startTrim),
                               .line(to: CGPoint(x: end.x - directionX * endTrim, y: end.y - directionY * endTrim)))
        return C4Route(path: path, start: start, startDirection: CGVector(dx: -directionX, dy: -directionY), end: end,
                       endDirection: CGVector(dx: directionX, dy: directionY), labelStretchStart: start, labelStretchEnd: end,
                       labelSide: shift != 0 ? CGVector(dx: -directionY, dy: directionX) : .zero,
                       labelRoom: abs(directionX) > abs(directionY) ? C4Metrics.narrowLabelWidth : C4Metrics.wideLabelWidth,
                       points: C4Numbers(start.x, start.y, end.x, end.y))
    }

    /// The straight line from `first` to `second`, from outline to outline. One holding the other is joined by a short
    /// line from the nearest side of the outer box; boxes that share a column or a row by an upright or level line through
    /// the shared span, moved by `shift` when both ends still meet it.
    static func connect(_ first: C4RouteBox, _ second: C4RouteBox, shift: CGFloat) -> (CGPoint, CGPoint) {
        let holdsSecond = first.contains(second)
        if holdsSecond || second.contains(first) { return connectNested(outer: holdsSecond ? first : second, inner: holdsSecond ? second : first,
                                                                         outerFirst: holdsSecond) }
        var startX = first.centerX
        var startY = first.centerY
        var endX = second.centerX
        var endY = second.centerY
        let sharedLeft = max(first.x, second.x)
        let sharedRight = min(first.right, second.right)
        let sharedTop = max(first.y, second.y)
        let sharedBottom = min(first.bottom, second.bottom)
        if sharedLeft < sharedRight {
            startX = (sharedLeft + sharedRight) / 2
            endX = startX
        } else if sharedTop < sharedBottom {
            startY = (sharedTop + sharedBottom) / 2
            endY = startY
        }
        return shifted(first, second, from: CGPoint(x: startX, y: startY), to: CGPoint(x: endX, y: endY), by: shift)
    }

    /// The line between the outlines moved sideways by `shift` when both ends still meet it moved, else the line
    /// between the centers.
    private static func shifted(_ first: C4RouteBox, _ second: C4RouteBox, from start: CGPoint, to end: CGPoint, by shift: CGFloat) -> (CGPoint, CGPoint) {
        var (startX, startY, endX, endY) = (start.x, start.y, end.x, end.y)
        let length = hypot(endX - startX, endY - startY)
        let usedLength = length == 0 ? 1 : length
        let offsetX = (-(endY - startY) / usedLength) * shift
        let offsetY = ((endX - startX) / usedLength) * shift
        var startFraction = first.hit(fromX: endX + offsetX, y: endY + offsetY, toX: startX + offsetX, y: startY + offsetY)
        var endFraction = second.hit(fromX: startX + offsetX, y: startY + offsetY, toX: endX + offsetX, y: endY + offsetY)
        if startFraction <= 1, endFraction <= 1 {
            startX += offsetX
            startY += offsetY
            endX += offsetX
            endY += offsetY
        } else {
            startX = first.centerX
            startY = first.centerY
            endX = second.centerX
            endY = second.centerY
            startFraction = min(first.hit(fromX: endX, y: endY, toX: startX, y: startY), 1)
            endFraction = min(second.hit(fromX: startX, y: startY, toX: endX, y: endY), 1)
        }
        return (CGPoint(x: endX + (startX - endX) * startFraction, y: endY + (startY - endY) * startFraction),
                CGPoint(x: startX + (endX - startX) * endFraction, y: startY + (endY - startY) * endFraction))
    }

    private static func connectNested(outer: C4RouteBox, inner: C4RouteBox, outerFirst: Bool) -> (CGPoint, CGPoint) {
        let innerX = inner.centerX
        let innerY = inner.centerY
        let left = inner.x - outer.x
        let right = outer.right - inner.right
        let top = inner.y - outer.y
        let bottom = outer.bottom - inner.bottom
        let least = min(left, right, top, bottom)
        let outerX = least == left ? outer.x : least == right ? outer.right : innerX
        let outerY = least == left || least == right ? innerY : least == bottom ? outer.bottom : outer.y
        let fraction = min(inner.hit(fromX: outerX, y: outerY, toX: innerX, y: innerY), 1)
        let met = CGPoint(x: outerX + (innerX - outerX) * fraction, y: outerY + (innerY - outerY) * fraction)
        let onOuter = CGPoint(x: outerX, y: outerY)
        return outerFirst ? (onOuter, met) : (met, onOuter)
    }

    // MARK: - Loops

    /// A box related to itself: a loop off the middle of its right side.
    private static func loop(around box: C4RouteBox, startTrim: CGFloat, endTrim: CGFloat) -> C4Route {
        let spread = min(box.height / 2 - 4, 10)
        let reach = C4Metrics.loopReach
        let length = hypot(reach, spread)
        let side = box.right
        let middle = box.centerY
        let unitX = reach / length
        let unitY = spread / length
        let path = C4RoutePath(start: CGPoint(x: side + unitX * startTrim, y: middle - spread - unitY * startTrim),
                               .curve(to: CGPoint(x: side + unitX * endTrim, y: middle + spread + unitY * endTrim),
                                      control1: CGPoint(x: side + reach, y: middle - spread * 2), control2: CGPoint(x: side + reach, y: middle + spread * 2)))
        let labelPlace = CGPoint(x: side + reach + 4, y: middle)
        return C4Route(path: path, start: CGPoint(x: side, y: middle - spread), startDirection: CGVector(dx: -unitX, dy: unitY),
                       end: CGPoint(x: side, y: middle + spread), endDirection: CGVector(dx: -unitX, dy: -unitY), labelStretchStart: labelPlace,
                       labelStretchEnd: labelPlace, labelSide: CGVector(dx: 1, dy: 0), labelRoom: C4Metrics.loopLabelWidth, points: C4Numbers())
    }

    // MARK: - Lines with corners

    /// The route for a line with corners through `points`, from one outline to the other; its label sits on the stretch
    /// that starts at point `labelStretch`.
    static func bent(_ points: C4Numbers, labelStretch: Int, startTrim: CGFloat, endTrim: CGFloat) -> C4Route {
        let count = points.count
        return C4Route(path: path(through: points, startTrim: startTrim, endTrim: endTrim), start: CGPoint(x: points[0], y: points[1]),
                       startDirection: CGVector(dx: -sign(points[2] - points[0]), dy: -sign(points[3] - points[1])),
                       end: CGPoint(x: points[count - 2], y: points[count - 1]),
                       endDirection: CGVector(dx: sign(points[count - 2] - points[count - 4]), dy: sign(points[count - 1] - points[count - 3])),
                       labelStretchStart: CGPoint(x: points[labelStretch], y: points[labelStretch + 1]),
                       labelStretchEnd: CGPoint(x: points[labelStretch + 2], y: points[labelStretch + 3]), points: points)
    }

    /// Pele's `path`: level and upright stretches, each corner rounded by a quadratic curve of at most 8 points (drawn as
    /// the cubic that is the same curve), the ends trimmed for their arrowheads.
    private static func path(through points: C4Numbers, startTrim: CGFloat, endTrim: CGFloat) -> C4RoutePath {
        let count = points.count
        let startStepX = sign(points[2] - points[0])
        let startStepY = sign(points[3] - points[1])
        var current = CGPoint(x: points[0] + startStepX * startTrim, y: points[1] + startStepY * startTrim)
        var path = C4RoutePath(start: current)
        var index = 2
        while index < count - 2 {
            let corner = CGPoint(x: points[index], y: points[index + 1])
            let inX = sign(corner.x - points[index - 2])
            let inY = sign(corner.y - points[index - 1])
            let outX = sign(points[index + 2] - corner.x)
            let outY = sign(points[index + 3] - corner.y)
            let radius = min(C4Metrics.cornerRadius, abs(corner.x - points[index - 2] + corner.y - points[index - 1]) / 2,
                             abs(points[index + 2] - corner.x + points[index + 3] - corner.y) / 2)
            current = inX != 0 ? CGPoint(x: corner.x - inX * radius, y: current.y) : CGPoint(x: current.x, y: corner.y - inY * radius)
            path.append(.line(to: current))
            let after = CGPoint(x: corner.x + outX * radius, y: corner.y + outY * radius)
            path.append(quadratic(from: current, control: corner, to: after))
            current = after
            index += 2
        }
        let lastX = sign(points[count - 2] - points[count - 4])
        let lastY = sign(points[count - 1] - points[count - 3])
        current = lastX != 0 ? CGPoint(x: points[count - 2] - lastX * endTrim, y: current.y) : CGPoint(x: current.x, y: points[count - 1] - lastY * endTrim)
        path.append(.line(to: current))
        return path
    }

    /// A quadratic curve as the cubic that draws it.
    private static func quadratic(from start: CGPoint, control: CGPoint, to end: CGPoint) -> DiagramPathSegment {
        .curve(to: end, control1: CGPoint(x: start.x + 2 / 3 * (control.x - start.x), y: start.y + 2 / 3 * (control.y - start.y)),
               control2: CGPoint(x: end.x + 2 / 3 * (control.x - end.x), y: end.y + 2 / 3 * (control.y - end.y)))
    }

    /// JavaScript's `Math.sign`: -1, 0 or 1.
    static func sign(_ value: CGFloat) -> CGFloat {
        value > 0 ? 1 : value < 0 ? -1 : 0
    }
}
