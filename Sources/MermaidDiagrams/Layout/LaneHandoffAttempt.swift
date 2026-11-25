/**
 * File: LaneHandoffAttempt.swift
 * ------------------------------
 * Layer: Core
 * Description: One route tried for a lane layout's handoff: whether each stretch keeps clear of boxes, texts and other
 *              lines, where its text goes, and the route itself with a point short of and past each corner, written at
 *              the end of the pass's list of route points.
 *
 * Authors: Bahey Shalash
 * Version: 0.2
 * Date: 24/11/2026
 */

import CoreGraphics

/// A box of flow space: its lowest and highest across, its lowest and highest along.
struct LaneFlowBox {
    var lowAcross: CGFloat
    var lowAlong: CGFloat
    var highAcross: CGFloat
    var highAlong: CGFloat

    /// Whether it overlaps the box `width` across and `depth` along around `center`.
    @inline(__always)
    func overlaps(_ center: LaneFlowPoint, _ width: CGFloat, _ depth: CGFloat) -> Bool {
        highAcross > center.across - width / 2 && lowAcross < center.across + width / 2 && highAlong > center.along - depth / 2
            && lowAlong < center.along + depth / 2
    }
}

extension LaneHandoffRouting {
    /// Tries the route through `way` (flow space) for a ranked edge: kept when each stretch, grown by `margin`, keeps clear
    /// of every other box and text and runs along no other edge, and when its text, if it has one, finds a stretch to sit on.
    mutating func attempt(_ way: LaneWay, margin: CGFloat, rankedIndex: Int, arena: DiagramScratchArena) -> Bool {
        let edge = pass.setup.edges[rankedIndex]
        let edgeIndex = edge.edgeIndex
        for index in 1..<way.count {
            let (start, end) = (way[index - 1], way[index])
            let box = LaneFlowBox(lowAcross: min(start.across, end.across) - margin, lowAlong: min(start.along, end.along) - margin,
                                  highAcross: max(start.across, end.across) + margin, highAlong: max(start.along, end.along) + margin)
            guard isClear(box, besides: edge.tail, and: edge.head, edgeIndex: edgeIndex) else { return false }
            if retraces(from: pagePoint(start), to: pagePoint(end), edgeIndex: edgeIndex) { return false }
        }
        var label: LaneFlowPoint?
        if pass.setup.edgeHasLabel[edgeIndex] {
            guard let place = labelPlace(on: way, edgeIndex: edgeIndex) else { return false }
            label = place
        }
        writeRoute(through: way, of: edgeIndex, arena: arena)
        if let label {
            placed.labelCenters[edgeIndex] = pagePoint(label)
            labels[edgeIndex] = label
        }
        isRouted[rankedIndex] = true
        return true
    }

    /// The longest stretch that holds the text, its middle inside the diagram, clear of every box and text (its own ends'
    /// included), and covering no other edge's stretch; nil when none does.
    private func labelPlace(on way: LaneWay, edgeIndex: Int) -> LaneFlowPoint? {
        let setup = pass.setup
        let extentAcross = setup.edgeLabelAcross[edgeIndex]
        let extentAlong = setup.edgeLabelAlong[edgeIndex]
        let pageSize = setup.graphEdges[edgeIndex].labelSize ?? .zero
        var best: LaneFlowPoint?
        var longest: CGFloat = -1
        for index in 1..<way.count {
            let (start, end) = (way[index - 1], way[index])
            let middle = LaneFlowPoint(across: (start.across + end.across) / 2, along: (start.along + end.along) / 2)
            let across = abs(end.across - start.across)
            let along = abs(end.along - start.along)
            if across + along <= longest || (across > 0 ? across < extentAcross + 8 : along < extentAlong + 8) { continue }
            let box = LaneFlowBox(lowAcross: middle.across - extentAcross / 2, lowAlong: middle.along - extentAlong / 2,
                                  highAcross: middle.across + extentAcross / 2, highAlong: middle.along + extentAlong / 2)
            if box.lowAcross < 0 || box.highAcross > pass.laneStarts[pass.laneStarts.count - 1] || box.lowAlong < 0 || box.highAlong > placed.bands.length {
                continue
            }
            guard isClear(box, besides: -1, and: -1, edgeIndex: edgeIndex) else { continue }
            let center = pagePoint(middle)
            let pageBox = CGRect(x: center.x - pageSize.width / 2, y: center.y - pageSize.height / 2, width: pageSize.width, height: pageSize.height)
            if crossings(pageBox, edgeIndex: edgeIndex) > 0 { continue }
            best = middle
            longest = across + along
        }
        return best
    }

    /// The route on the page, written at the end of the points list as the edge's route: a point a turn's room short of each
    /// corner and one past it keep the turn close to the corner, so that the line stays under its text and the handoff takes
    /// little room; each point's axis is across the flow where the stretch arriving at it (or, for the first, leaving it)
    /// runs across.
    private mutating func writeRoute(through way: LaneWay, of edgeIndex: Int, arena: DiagramScratchArena) {
        // The points list grows before the mark, so that giving back the corners' room keeps its own.
        placed.routePoints.reserveCapacity(placed.routePoints.count + 3 * way.count)
        let mark = arena.mark()
        defer { arena.release(to: mark) }
        var points = arena.list(capacity: 3 * way.count, of: LaneFlowPoint.self)
        points.append(way[0])
        for index in 1..<way.count {
            let (start, end) = (way[index - 1], way[index])
            let delta = (end.across - start.across, end.along - start.along)
            let run = abs(delta.0) + abs(delta.1)
            let first: CGFloat = index > 1 ? Self.turnRoom : 0
            let last: CGFloat = index + 1 < way.count ? Self.turnRoom : 0
            if run > first + last + 1 {
                if first > 0 { points.append(LaneFlowPoint(across: start.across + delta.0 / run * first, along: start.along + delta.1 / run * first)) }
                if last > 0 { points.append(LaneFlowPoint(across: end.across - delta.0 / run * last, along: end.along - delta.1 / run * last)) }
            }
            points.append(end)
        }
        let start = placed.routePoints.count
        for index in 0..<points.count {
            let isCrosswise = index == 0 ? points[0].across != points[1].across : points[index].across != points[index - 1].across
            placed.routePoints.append(LaneRoutePoint(point: pagePoint(points[index]), axis: isCrosswise ? 1 - placed.axis : placed.axis))
        }
        placed.routeStarts[edgeIndex] = start
        placed.routeCounts[edgeIndex] = points.count
    }

    /// Whether a box of flow space overlaps no item but `first` and `second` (-1 for none), each grown by 8 points, and no
    /// other edge's text.
    private func isClear(_ box: LaneFlowBox, besides first: Int, and second: Int, edgeIndex: Int) -> Bool {
        let setup = pass.setup
        for item in 0..<setup.items.count where item != first && item != second {
            if box.overlaps(LaneFlowPoint(across: pass.centers[item], along: placed.bandMiddle(of: item)), pass.across[item] + 8, pass.along[item] + 8) {
                return false
            }
        }
        let edges = setup.graphEdges
        for other in 0..<edges.count where other != edgeIndex && edges[other].source != edges[other].target {
            // A box's own loop keeps its text inside the box's room, and has no place here.
            guard setup.edgeHasLabel[other] else { continue }
            if box.overlaps(labels[other], setup.edgeLabelAcross[other], setup.edgeLabelAlong[other]) { return false }
        }
        return true
    }

    /// How many other edges have a stretch whose box, curve included, is inside `box` on the page.
    func crossings(_ box: CGRect, edgeIndex: Int) -> Int {
        var count = 0
        for other in 0..<placed.routeCounts.count where other != edgeIndex {
            let route = placed.route(of: other)
            guard route.count > 1 else { continue }
            for index in 1..<route.count {
                let (start, end) = (route[index - 1].point, route[index].point)
                if max(start.x, end.x) > box.minX, min(start.x, end.x) < box.maxX, max(start.y, end.y) > box.minY, min(start.y, end.y) < box.maxY {
                    count += 1
                    break
                }
            }
        }
        return count
    }

    /// How many other edges start or end within a point of `point`.
    func meets(_ point: CGPoint, edgeIndex: Int) -> Int {
        var count = 0
        for other in 0..<placed.routeCounts.count where other != edgeIndex && placed.routeCounts[other] > 0 {
            let route = placed.route(of: other)
            let (first, last) = (route[0].point, route[route.count - 1].point)
            if (abs(first.x - point.x) < 1 && abs(first.y - point.y) < 1) || (abs(last.x - point.x) < 1 && abs(last.y - point.y) < 1) { count += 1 }
        }
        return count
    }

    /// Whether a straight stretch runs along another edge's stretch on one line for more than a point: two lines drawn
    /// along one read as one path. Edges that leave the same box or arrive at the same box may share a trunk.
    private func retraces(from start: CGPoint, to end: CGPoint, edgeIndex: Int) -> Bool {
        let edges = pass.setup.graphEdges
        let isUpright = abs(end.x - start.x) < 0.5
        let low = isUpright ? min(start.y, end.y) : min(start.x, end.x)
        let high = isUpright ? max(start.y, end.y) : max(start.x, end.x)
        let line = isUpright ? start.x : start.y
        for other in 0..<placed.routeCounts.count where other != edgeIndex {
            if edges[other].source == edges[edgeIndex].source || edges[other].target == edges[edgeIndex].target { continue }
            let route = placed.route(of: other)
            guard route.count > 1 else { continue }
            for index in 1..<route.count {
                let (from, to) = (route[index - 1].point, route[index].point)
                let (lineFrom, lineTo) = isUpright ? (from.x, to.x) : (from.y, to.y)
                guard abs(lineFrom - line) < Self.nearDistance, abs(lineTo - line) < Self.nearDistance else { continue }
                let (spanFrom, spanTo) = isUpright ? (from.y, to.y) : (from.x, to.x)
                if min(high, max(spanFrom, spanTo)) - max(low, min(spanFrom, spanTo)) > 1 { return true }
            }
        }
        return false
    }
}
