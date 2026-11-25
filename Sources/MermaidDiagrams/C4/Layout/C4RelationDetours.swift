/**
 * File: C4RelationDetours.swift
 * -----------------------------
 * Layer: Core
 * Description: The elbow Pele's route.ts draws when a shape stands between a relation's ends that share no column or
 *              row: two corners through the gap between their columns or between their rows, apart from the routes
 *              already there.
 *
 * Authors: Bahey Shalash
 * Version: 0.2
 * Date: 24/11/2026
 */

import CoreGraphics

/// A line with two corners: its points, its cost, whether its middle stretch is upright, and the sides of its ends.
private struct C4Elbow {
    let points: C4Numbers
    let isUpright: Bool
    let startSide: Int
    let endSide: Int
    var cost: CGFloat = 0
}

extension C4Router {
    // MARK: - Elbows

    /// A line with two corners through the gap between the ends' columns, then through the gap between their rows,
    /// the cheapest clear of other shapes and apart from the lanes taken; nil when none is.
    mutating func elbow(from first: Int, to second: Int, startTrim: CGFloat, endTrim: CGFloat) -> C4Route? {
        var best: C4Elbow?
        searchThroughColumns(from: first, to: second, best: &best)
        searchThroughRows(from: first, to: second, best: &best)
        guard let best else { return nil }
        lanes.take(best.points)
        lanes.claim(first, side: best.startSide, at: best.isUpright ? best.points[1] : best.points[0])
        lanes.claim(second, side: best.endSide, at: best.isUpright ? best.points[7] : best.points[6])
        // The label sits on the middle stretch, across the gap.
        var route = Self.bent(Array(best.points), labelStretch: 2, startTrim: startTrim, endTrim: endTrim)
        route.labelRoom = best.isUpright ? C4Metrics.narrowLabelWidth : C4Metrics.wideLabelWidth
        return route
    }

    /// Through the gap between the ends' columns, when they share none: each end left from a side facing the other, a
    /// quarter of the way from its middle towards the other's height, the first clear way found.
    private func searchThroughColumns(from first: Int, to second: Int, best: inout C4Elbow?) {
        let start = boxes[first]
        let end = boxes[second]
        guard start.right <= end.x || end.right <= start.x else { return }
        let towardsRight = end.centerX > start.centerX
        let sides = towardsRight ? (1, 0) : (0, 1)
        let downward = Self.sign(end.centerY - start.centerY)
        let gaps = Self.lanesAcross(from: towardsRight ? start.right : end.right, to: towardsRight ? end.x : start.x)
        for startY in lanes.ports(of: first, side: sides.0, wanted: start.centerY + downward * start.height / 4, low: start.y + 8, high: start.bottom - 8) {
            for endY in lanes.ports(of: second, side: sides.1, wanted: end.centerY - downward * end.height / 4, low: end.y + 8, high: end.bottom - 8) {
                for lane in gaps {
                    let startX = lane + (start.centerX - lane) * min(start.hit(fromX: lane, y: startY, toX: start.centerX, y: startY), 1)
                    let endX = lane + (end.centerX - lane) * min(end.hit(fromX: lane, y: endY, toX: end.centerX, y: endY), 1)
                    let candidate = C4Elbow(points: C4Numbers(startX, startY, lane, startY, lane, endY, endX, endY), isUpright: true, startSide: sides.0,
                                            endSide: sides.1)
                    if consider(candidate, from: first, to: second, best: &best) { return }
                }
            }
        }
    }

    /// Through the gap between the ends' rows, when they share none, as through the columns.
    private func searchThroughRows(from first: Int, to second: Int, best: inout C4Elbow?) {
        let start = boxes[first]
        let end = boxes[second]
        guard start.bottom <= end.y || end.bottom <= start.y else { return }
        let below = end.centerY > start.centerY
        let sides = below ? (3, 2) : (2, 3)
        let sideways = Self.sign(end.centerX - start.centerX)
        let gaps = Self.lanesAcross(from: below ? start.bottom : end.bottom, to: below ? end.y : start.y)
        for startX in lanes.ports(of: first, side: sides.0, wanted: start.centerX + sideways * start.width / 4, low: start.x + 8, high: start.right - 8) {
            for endX in lanes.ports(of: second, side: sides.1, wanted: end.centerX - sideways * end.width / 4, low: end.x + 8, high: end.right - 8) {
                for lane in gaps {
                    let startY = lane + (start.centerY - lane) * min(start.hit(fromX: startX, y: lane, toX: startX, y: start.centerY), 1)
                    let endY = lane + (end.centerY - lane) * min(end.hit(fromX: endX, y: lane, toX: endX, y: end.centerY), 1)
                    let candidate = C4Elbow(points: C4Numbers(startX, startY, startX, lane, endX, lane, endX, endY), isUpright: false, startSide: sides.0,
                                            endSide: sides.1)
                    if consider(candidate, from: first, to: second, best: &best) { return }
                }
            }
        }
    }

    /// Whether `candidate` is clear of the shapes and lanes and cheaper than the best so far (its crossings first, then
    /// its length), and so becomes the best.
    private func consider(_ candidate: C4Elbow, from first: Int, to second: Int, best: inout C4Elbow?) -> Bool {
        let points = candidate.points
        guard isClear(points, of: first, second), isEveryStretchFree(points) else { return false }
        var cost = CGFloat(lanes.crossings(points)) * 1e6
        var index = 2
        while index < points.count {
            cost += abs(points[index] - points[index - 2]) + abs(points[index + 1] - points[index - 1])
            index += 2
        }
        if let best, cost >= best.cost { return false }
        var chosen = candidate
        chosen.cost = cost
        best = chosen
        return true
    }

    private func isEveryStretchFree(_ points: C4Numbers) -> Bool {
        var index = 2
        while index < points.count {
            let isUpright = points[index] == points[index - 2]
            guard lanes.isFree(upright: isUpright, at: isUpright ? points[index] : points[index + 1], from: isUpright ? points[index - 1] : points[index - 2],
                               to: isUpright ? points[index + 1] : points[index]) else { return false }
            index += 2
        }
        return true
    }

    /// Up to nine places across the gap from `low` to `high`, its middle first, a quarter of the gap apart (at least a
    /// lane step), each kept a near distance from the gap's sides.
    static func lanesAcross(from low: CGFloat, to high: CGFloat) -> C4Numbers {
        let middle = (low + high) / 2
        let step = max(C4Metrics.laneStep, (high - low) / 4)
        var places = C4Numbers()
        for index in 0..<9 {
            let place = middle + (index & 1 == 1 ? 1 : -1) * CGFloat((index + 1) / 2) * step
            if place >= low + C4Metrics.nearDistance && place <= high - C4Metrics.nearDistance { places.append(place) }
        }
        return places
    }
}
