/**
 * File: LayeredRouteCrossings.swift
 * ---------------------------------
 * Layer: Core
 * Description: Counts how often the drawn routes of Pele's compound layout cross (compound.ts routeCrossings).
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 23/11/2026
 */

import CoreGraphics

/// The straight pieces the drawn routes are cut into to count their crossings: each from its left end (`startX`,
/// `startY`) to its right end, its extent down, its edge, and whether it is the first (1) or last (2) of its edge.
struct LayeredRouteSegments {
    var startX: [Double] = []
    var startY: [Double] = []
    var endX: [Double] = []
    var endY: [Double] = []
    var low: [Double] = []
    var high: [Double] = []
    var owner: [Int] = []
    var ends: [UInt8] = []
    var top = Double.infinity
    var bottom = -Double.infinity
    /// The last piece added, to join a straight piece onto the one before it.
    private var lastFrom = CGPoint(x: Double.nan, y: Double.nan)
    private var lastTo = CGPoint(x: Double.nan, y: Double.nan)

    var count: Int { owner.count }

    mutating func add(edge: Int, part: UInt8, from: CGPoint, to: CGPoint) {
        var from = from
        let previous = count - 1
        let isOn = from.x == lastTo.x && from.y == lastTo.y && ((to.y == from.y && lastFrom.y == from.y) || (to.x == from.x && lastFrom.x == from.x))
        if isOn && previous >= 0 && owner[previous] == edge && ends[previous] == part
            && (from.x - lastFrom.x) * (to.x - from.x) + (from.y - lastFrom.y) * (to.y - from.y) > 0 {
            removeLast()
            from = lastFrom
        }
        lastFrom = from
        lastTo = to
        ends.append(part)
        startX.append(min(from.x, to.x))
        endX.append(max(from.x, to.x))
        startY.append(from.x <= to.x ? from.y : to.y)
        endY.append(from.x <= to.x ? to.y : from.y)
        low.append(min(from.y, to.y))
        high.append(max(from.y, to.y))
        top = min(top, min(from.y, to.y))
        bottom = max(bottom, max(from.y, to.y))
        owner.append(edge)
    }

    private mutating func removeLast() {
        startX.removeLast(); startY.removeLast(); endX.removeLast(); endY.removeLast()
        low.removeLast(); high.removeLast(); owner.removeLast(); ends.removeLast()
    }
}

/// Pele's `routeCrossings`: each route cut into straight pieces as it is drawn (corners and S curves approximated by a
/// few), pieces sorted into bands down the page, and every pair that crosses counted once, except where two edges fan
/// in or out at a shared node or merge into a shared run of their ends.
enum LayeredRouteCrossings {
    static func count(nodes: [LayeredCompoundNode], edges: [LayeredCompoundEdge], style: LayeredRouteStyle) -> Int {
        var segments = LayeredRouteSegments()
        for (edgeIndex, edge) in edges.enumerated() where edge.source != edge.target {
            cut(edge.route, edge: edgeIndex, style: style, into: &segments)
        }
        let runs = edges.map { edge in endRuns(of: edge.route) }
        return countCrossings(segments, nodes: nodes, edges: edges, runs: runs)
    }

    /// The straight run at each end of a route: its first point to where it leaves that line, and the last likewise.
    private static func endRuns(of route: [LayeredRoutePoint]) -> [CGPoint] {
        guard route.count >= 2 else { return [] }
        func inLine(_ first: Int, _ second: Int, _ third: Int) -> Bool {
            let points = (route[first].point, route[second].point, route[third].point)
            return (abs(points.0.x - points.1.x) < LayeredCompoundConstants.inLine && abs(points.0.x - points.2.x) < LayeredCompoundConstants.inLine)
                || (abs(points.0.y - points.1.y) < LayeredCompoundConstants.inLine && abs(points.0.y - points.2.y) < LayeredCompoundConstants.inLine)
        }
        var forward = 1
        while forward + 1 < route.count && inLine(0, forward, forward + 1) { forward += 1 }
        let last = route.count - 1
        var backward = last - 1
        while backward >= 1 && inLine(last, backward, backward - 1) { backward -= 1 }
        return [route[0].point, route[forward].point, route[backward].point, route[last].point]
    }

    /// Whether (x, y) lies on the run at the start (`end` 1) or end of an edge's route.
    static func isOnRun(_ runs: [CGPoint], end: UInt8, x: Double, y: Double) -> Bool {
        guard runs.count == 4 else { return false }
        let start = runs[end == 1 ? 0 : 2]
        let finish = runs[end == 1 ? 1 : 3]
        let deltaX = finish.x - start.x
        let deltaY = finish.y - start.y
        let lengthSquared = deltaX * deltaX + deltaY * deltaY
        let along = lengthSquared > 0 ? max(0, min(1, ((x - start.x) * deltaX + (y - start.y) * deltaY) / lengthSquared)) : 0
        return hypot(x - start.x - along * deltaX, y - start.y - along * deltaY) < LayeredCompoundConstants.inLine
    }
}
