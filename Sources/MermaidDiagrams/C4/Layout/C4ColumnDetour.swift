/**
 * File: C4ColumnDetour.swift
 * --------------------------
 * Layer: Core
 * Description: The detour Pele's route.ts draws for a relation whose ends share a column or a row with a shape between
 *              them: along the outside of the shapes in the way, on the side that is outside the drawing or crosses
 *              fewer lines, a lane out from them and apart from the routes already there.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 19/11/2026
 */

import CoreGraphics

/// A detour on one side of the shapes between two ends: its corners, the side of the ends it leaves and reaches, where
/// on that side, and how many lanes out it went (5 when none was free).
private struct C4Detour {
    let points: [CGFloat]
    let side: Int
    let startPort: CGFloat
    let endPort: CGFloat
    let step: Int
}

/// The two ends of a detour, the straight line between them, and whether that line is upright (a column) or level.
private struct C4DetourEnds {
    let first: Int
    let second: Int
    let straightStart: CGPoint
    let straightEnd: CGPoint
    var isUpright: Bool { straightStart.x == straightEnd.x }
}

extension C4Router {
    /// The route around the shapes between two ends in one column or one row. It takes the outside of the drawing when
    /// only one side is outside, leaving the gaps between columns and rows to the relations that cross them; otherwise
    /// the side where it crosses fewer lines, then the one where it runs nearer its shapes, so that detours spread over
    /// both sides.
    mutating func detour(from first: Int, to second: Int, straightStart: CGPoint, straightEnd: CGPoint, startTrim: CGFloat,
                         endTrim: CGFloat) -> C4Route {
        let ends = C4DetourEnds(first: first, second: second, straightStart: straightStart, straightEnd: straightEnd)
        let natural = ends.isUpright ? straightEnd.y > straightStart.y : straightEnd.x < straightStart.x
        let naturalIsOutside = isOutside(ends, forward: natural, lane: lane(ends, forward: natural))
        let otherIsOutside = isOutside(ends, forward: !natural, lane: lane(ends, forward: !natural))
        let naturalWay = detour(ends, forward: natural)
        let otherWay = naturalIsOutside == otherIsOutside ? detour(ends, forward: !natural) : nil
        func cost(_ way: C4Detour) -> Int { lanes.crossings(way.points) * 8 + way.step }
        let forward: Bool
        if otherIsOutside, !naturalIsOutside {
            forward = !natural
        } else if let otherWay, cost(otherWay) < cost(naturalWay) {
            forward = !natural
        } else {
            forward = natural
        }
        let chosen = forward == natural ? naturalWay : (otherWay ?? detour(ends, forward: !natural))
        if chosen.step > 4 { lanes.squeezedCount += 1 }
        lanes.take(chosen.points)
        lanes.claim(first, side: chosen.side, at: chosen.startPort)
        lanes.claim(second, side: chosen.side, at: chosen.endPort)
        var route = Self.bent(chosen.points, labelStretch: 2, startTrim: startTrim, endTrim: endTrim)
        if ends.isUpright {
            route.labelSide = CGVector(dx: forward ? 1 : -1, dy: 0)
            route.labelLean = C4Metrics.labelLean
            route.labelRoom = C4Metrics.narrowLabelWidth
        }
        return route
    }

    /// The outer edge, on one side, of the two ends and of every shape the straight line runs into: where a lane along
    /// that side starts.
    private func lane(_ ends: C4DetourEnds, forward: Bool) -> CGFloat {
        var edge = forward ? -CGFloat.infinity : CGFloat.infinity
        func widen(_ box: C4RouteBox) {
            let near = ends.isUpright ? box.x : box.y
            edge = forward ? max(edge, near + (ends.isUpright ? box.width : box.height)) : min(edge, near)
        }
        widen(boxes[ends.first])
        widen(boxes[ends.second])
        for other in obstacles ?? [] where other != ends.first && other != ends.second && Self.stands(boxes[other], on: ends.straightStart, ends.straightEnd) {
            widen(boxes[other])
        }
        return edge
    }

    /// Whether no shape beside the stretch between the ends reaches past `lane` on that side.
    private func isOutside(_ ends: C4DetourEnds, forward: Bool, lane: CGFloat) -> Bool {
        let start = boxes[ends.first]
        let end = boxes[ends.second]
        let low = ends.isUpright ? min(start.y, end.y) : min(start.x, end.x)
        let high = ends.isUpright ? max(start.bottom, end.bottom) : max(start.right, end.right)
        for other in obstacles ?? [] where other != ends.first && other != ends.second {
            let box = boxes[other]
            let isNear = ends.isUpright ? box.y < high && box.bottom > low : box.x < high && box.right > low
            let near = ends.isUpright ? box.x : box.y
            let far = near + (ends.isUpright ? box.width : box.height)
            if isNear, forward ? far > lane : near < lane { return false }
        }
        return true
    }

    /// The detour on one side: each end leaves its shape a quarter of the way from the middle towards the other, clear of
    /// the straight lines that meet the middle of that side and of other routes there; the lane runs a little further out
    /// for each route already along that gap, and never behind a shape.
    private func detour(_ ends: C4DetourEnds, forward: Bool) -> C4Detour {
        let start = boxes[ends.first]
        let end = boxes[ends.second]
        let isUpright = ends.isUpright
        let outerEdge = lane(ends, forward: forward)
        let sign: CGFloat = forward ? 1 : -1
        let side = isUpright ? (forward ? 1 : 0) : (forward ? 3 : 2)
        let towards = isUpright ? Self.sign(end.centerY - start.centerY) : Self.sign(end.centerX - start.centerX)
        let startPort = isUpright
            ? lanes.ports(of: ends.first, side: side, wanted: start.centerY + towards * start.height / 4, low: start.y + 8, high: start.bottom - 8)[0]
            : lanes.ports(of: ends.first, side: side, wanted: start.centerX + towards * start.width / 4, low: start.x + 8, high: start.right - 8)[0]
        let endPort = isUpright
            ? lanes.ports(of: ends.second, side: side, wanted: end.centerY - towards * end.height / 4, low: end.y + 8, high: end.bottom - 8)[0]
            : lanes.ports(of: ends.second, side: side, wanted: end.centerX - towards * end.width / 4, low: end.x + 8, high: end.right - 8)[0]
        func points(at place: CGFloat) -> [CGFloat] {
            if isUpright {
                let startX = place + (start.centerX - place) * min(start.hit(fromX: place, y: startPort, toX: start.centerX, y: startPort), 1)
                let endX = place + (end.centerX - place) * min(end.hit(fromX: place, y: endPort, toX: end.centerX, y: endPort), 1)
                return [startX, startPort, place, startPort, place, endPort, endX, endPort]
            }
            let startY = place + (start.centerY - place) * min(start.hit(fromX: startPort, y: place, toX: startPort, y: start.centerY), 1)
            let endY = place + (end.centerY - place) * min(end.hit(fromX: endPort, y: place, toX: endPort, y: end.centerY), 1)
            return [startPort, startY, startPort, place, endPort, place, endPort, endY]
        }
        var chosen = points(at: outerEdge + sign * C4Metrics.lane)
        for step in 0...4 {
            let place = outerEdge + sign * (C4Metrics.lane + CGFloat(step) * C4Metrics.laneStep)
            let tried = points(at: place)
            guard isClear(tried, of: ends.first, ends.second) else { continue }
            chosen = tried
            if lanes.isFree(upright: isUpright, at: place, from: startPort, to: endPort) {
                return C4Detour(points: chosen, side: side, startPort: startPort, endPort: endPort, step: step)
            }
        }
        return C4Detour(points: chosen, side: side, startPort: startPort, endPort: endPort, step: 5)
    }
}
