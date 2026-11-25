/**
 * File: ReferenceLaneHandoffAttempt.swift
 * ---------------------------------------
 * Layer: Tests
 * Description: The 0.7.0 LaneHandoffAttempt kept as the reference the lane layout on the scratch arena is checked
 *              against: one route tried for a lane layout's handoff: whether each stretch keeps clear of boxes, texts
 *              and other lines, where its text goes, and the route itself with a point short of and past each corner.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 24/11/2026
 */

import CoreGraphics
@testable import MermaidDiagrams

extension ReferenceLaneHandoffRouting {
    /// Tries the route through `points` (flow space) for a ranked edge: kept when each stretch, grown by `margin`, keeps clear
    /// of every other box and text and runs along no other edge, and when its text, if it has one, finds a stretch to sit on.
    mutating func attempt(_ points: [(CGFloat, CGFloat)], margin: CGFloat, rankedIndex: Int) -> Bool {
        let edge = pass.setup.edges[rankedIndex]
        let edgeIndex = edge.edgeIndex
        for (start, end) in zip(points, points.dropFirst()) {
            let box = (min(start.0, end.0) - margin, min(start.1, end.1) - margin, max(start.0, end.0) + margin, max(start.1, end.1) + margin)
            guard isClear(box, besides: (edge.tail, edge.head), edgeIndex: edgeIndex) else { return false }
            if retraces(from: pagePoint(start.0, start.1), to: pagePoint(end.0, end.1), edgeIndex: edgeIndex) { return false }
        }
        var label: (CGFloat, CGFloat)?
        if let extent = labelExtent(of: edgeIndex) {
            guard let place = labelPlace(on: points, extent: extent, edgeIndex: edgeIndex) else { return false }
            label = place
        }
        placed.routes[edgeIndex] = route(through: points)
        if let label {
            placed.labelCenters[edgeIndex] = pagePoint(label.0, label.1)
            labels[edgeIndex] = (label.0, label.1)
        }
        isRouted[rankedIndex] = true
        return true
    }

    /// The longest stretch that holds the text, its middle inside the diagram, clear of every box and text (its own ends'
    /// included), and covering no other edge's stretch; nil when none does.
    private func labelPlace(on points: [(CGFloat, CGFloat)], extent: (across: CGFloat, along: CGFloat), edgeIndex: Int) -> (CGFloat, CGFloat)? {
        let pageSize = pass.setup.graph.edges[edgeIndex].labelSize ?? .zero
        var best: (CGFloat, CGFloat)?
        var longest: CGFloat = -1
        for (start, end) in zip(points, points.dropFirst()) {
            let middle = ((start.0 + end.0) / 2, (start.1 + end.1) / 2)
            let across = abs(end.0 - start.0)
            let along = abs(end.1 - start.1)
            if across + along <= longest || (across > 0 ? across < extent.across + 8 : along < extent.along + 8) { continue }
            let box = (middle.0 - extent.across / 2, middle.1 - extent.along / 2, middle.0 + extent.across / 2, middle.1 + extent.along / 2)
            if box.0 < 0 || box.2 > pass.laneStarts[pass.laneStarts.count - 1] || box.1 < 0 || box.3 > placed.bands.length { continue }
            guard isClear(box, besides: nil, edgeIndex: edgeIndex) else { continue }
            let center = pagePoint(middle.0, middle.1)
            let pageBox = CGRect(x: center.x - pageSize.width / 2, y: center.y - pageSize.height / 2, width: pageSize.width, height: pageSize.height)
            if crossings(pageBox, edgeIndex: edgeIndex) > 0 { continue }
            best = middle
            longest = across + along
        }
        return best
    }

    /// The route on the page: a point a turn's room short of each corner and one past it keep the turn close to the
    /// corner, so that the line stays under its text and the handoff takes little room; each point's axis is across the
    /// flow where the stretch arriving at it (or, for the first, leaving it) runs across.
    private func route(through points: [(CGFloat, CGFloat)]) -> [ReferenceLaneRoutePoint] {
        var way = [points[0]]
        for index in 1..<points.count {
            let (start, end) = (points[index - 1], points[index])
            let delta = (end.0 - start.0, end.1 - start.1)
            let run = abs(delta.0) + abs(delta.1)
            let first: CGFloat = index > 1 ? Self.turnRoom : 0
            let last: CGFloat = index + 1 < points.count ? Self.turnRoom : 0
            if run > first + last + 1 {
                if first > 0 { way.append((start.0 + delta.0 / run * first, start.1 + delta.1 / run * first)) }
                if last > 0 { way.append((end.0 - delta.0 / run * last, end.1 - delta.1 / run * last)) }
            }
            way.append(end)
        }
        return way.indices.map { index in
            let isCrosswise = index == 0 ? way[0].0 != way[1].0 : way[index].0 != way[index - 1].0
            return ReferenceLaneRoutePoint(point: pagePoint(way[index].0, way[index].1), axis: isCrosswise ? 1 - placed.axis : placed.axis)
        }
    }

    /// Whether a box of flow space (lowest across, lowest along, highest across, highest along) overlaps no item but the
    /// two `besides`, each grown by 8 points, and no other edge's text.
    private func isClear(_ box: (CGFloat, CGFloat, CGFloat, CGFloat), besides: (Int, Int)?, edgeIndex: Int) -> Bool {
        func overlaps(_ center: (CGFloat, CGFloat), _ width: CGFloat, _ depth: CGFloat) -> Bool {
            box.2 > center.0 - width / 2 && box.0 < center.0 + width / 2 && box.3 > center.1 - depth / 2 && box.1 < center.1 + depth / 2
        }
        for item in pass.setup.items.indices where item != besides?.0 && item != besides?.1 {
            if overlaps((pass.centers[item], placed.bandMiddle(of: item)), pass.across[item] + 8, pass.along[item] + 8) { return false }
        }
        for (other, edge) in pass.setup.graph.edges.enumerated() where other != edgeIndex && edge.source != edge.target {
            // A box's own loop keeps its text inside the box's room, and has no place here.
            guard let extent = labelExtent(of: other) else { continue }
            if overlaps(labels[other], extent.across, extent.along) { return false }
        }
        return true
    }

    /// How many other edges have a stretch whose box, curve included, is inside `box` on the page.
    func crossings(_ box: CGRect, edgeIndex: Int) -> Int {
        var count = 0
        for (other, route) in placed.routes.enumerated() where other != edgeIndex {
            for (start, end) in zip(route, route.dropFirst()) {
                if max(start.point.x, end.point.x) > box.minX, min(start.point.x, end.point.x) < box.maxX,
                   max(start.point.y, end.point.y) > box.minY, min(start.point.y, end.point.y) < box.maxY {
                    count += 1
                    break
                }
            }
        }
        return count
    }

    /// How many other edges start or end within a point of `point`.
    func meets(_ point: CGPoint, edgeIndex: Int) -> Int {
        placed.routes.enumerated().reduce(0) { count, pair in
            guard pair.offset != edgeIndex, let first = pair.element.first, let last = pair.element.last else { return count }
            let isEnd = (abs(first.point.x - point.x) < 1 && abs(first.point.y - point.y) < 1) || (abs(last.point.x - point.x) < 1 && abs(last.point.y - point.y) < 1)
            return isEnd ? count + 1 : count
        }
    }

    /// Whether a straight stretch runs along another edge's stretch on one line for more than a point: two lines drawn
    /// along one read as one path. Edges that leave the same box or arrive at the same box may share a trunk.
    private func retraces(from start: CGPoint, to end: CGPoint, edgeIndex: Int) -> Bool {
        let edges = pass.setup.graph.edges
        let isUpright = abs(end.x - start.x) < 0.5
        let low = isUpright ? min(start.y, end.y) : min(start.x, end.x)
        let high = isUpright ? max(start.y, end.y) : max(start.x, end.x)
        let line = isUpright ? start.x : start.y
        for (other, route) in placed.routes.enumerated() where other != edgeIndex {
            if edges[other].source == edges[edgeIndex].source || edges[other].target == edges[edgeIndex].target { continue }
            for (from, to) in zip(route, route.dropFirst()) {
                let (lineFrom, lineTo) = isUpright ? (from.point.x, to.point.x) : (from.point.y, to.point.y)
                guard abs(lineFrom - line) < Self.nearDistance, abs(lineTo - line) < Self.nearDistance else { continue }
                let (spanFrom, spanTo) = isUpright ? (from.point.y, to.point.y) : (from.point.x, to.point.x)
                if min(high, max(spanFrom, spanTo)) - max(low, min(spanFrom, spanTo)) > 1 { return true }
            }
        }
        return false
    }
}
