/**
 * File: LayeredRouteCrossings.swift
 * ---------------------------------
 * Layer: Core
 * Description: Counts how often the drawn routes of Pele's compound layout cross (compound.ts routeCrossings).
 *
 * Authors: Bahey Shalash
 * Version: 0.4
 * Date: 25/11/2026
 */

import CoreGraphics

/// The straight pieces the drawn routes are cut into to count their crossings: each from its left end (`startX`,
/// `startY`) to its right end, its extent down, its edge, and whether it is the first (1) or last (2) of its edge.
struct LayeredRouteSegments {
    var startX: ScratchList<Double>
    var startY: ScratchList<Double>
    var endX: ScratchList<Double>
    var endY: ScratchList<Double>
    var low: ScratchList<Double>
    var high: ScratchList<Double>
    var owner: ScratchList<Int>
    var ends: ScratchList<UInt8>
    var top = Double.infinity
    var bottom = -Double.infinity
    /// The last piece added, to join a straight piece onto the one before it.
    private var lastFrom = CGPoint(x: Double.nan, y: Double.nan)
    private var lastTo = CGPoint(x: Double.nan, y: Double.nan)

    /// Empty lists of `arena`, with room for `capacity` pieces before they grow.
    init(capacity: Int, arena: DiagramScratchArena) {
        startX = arena.list(capacity: capacity, of: Double.self)
        startY = arena.list(capacity: capacity, of: Double.self)
        endX = arena.list(capacity: capacity, of: Double.self)
        endY = arena.list(capacity: capacity, of: Double.self)
        low = arena.list(capacity: capacity, of: Double.self)
        high = arena.list(capacity: capacity, of: Double.self)
        owner = arena.list(capacity: capacity, of: Int.self)
        ends = arena.list(capacity: capacity, of: UInt8.self)
    }

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
        _ = startX.removeLast(); _ = startY.removeLast(); _ = endX.removeLast(); _ = endY.removeLast()
        _ = low.removeLast(); _ = high.removeLast(); _ = owner.removeLast(); _ = ends.removeLast()
    }
}

/// Pele's `routeCrossings`: each route cut into straight pieces as it is drawn (corners and S curves approximated by a
/// few), pieces sorted into bands down the page, and every pair that crosses counted once, except where two edges fan
/// in or out at a shared node or merge into a shared run of their ends.
enum LayeredRouteCrossings {
    /// The crossings of `edges`, each route a range of `routePoints`, between `nodes`.
    static func count(nodes: ScratchSpan<LayeredCompoundNode>, edges: ScratchSpan<LayeredCompoundSpanEdge>, routePoints: ScratchSpan<LayeredRoutePoint>,
                      style: LayeredRouteStyle, arena: DiagramScratchArena) -> Int {
        #if DEBUG
        record(nodes: nodes, edges: edges, routePoints: routePoints, style: style)
        #endif
        let mark = arena.mark()
        defer { arena.release(to: mark) }
        func route(of edge: LayeredCompoundSpanEdge) -> ScratchSpan<LayeredRoutePoint> { routePoints.part(edge.routeStart..<(edge.routeStart + edge.routeCount)) }
        var pointCount = 0
        for edge in edges { pointCount += edge.routeCount }
        var segments = LayeredRouteSegments(capacity: 4 * pointCount, arena: arena)
        for (edgeIndex, edge) in edges.enumerated() where edge.source != edge.target {
            cut(route(of: edge), edge: edgeIndex, style: style, into: &segments)
        }
        // The straight runs at the ends of each route, four points an edge; an edge of fewer than two points has none.
        let runs: ScratchSpan<CGPoint> = arena.uninitializedSpan(count: 4 * edges.count)
        let hasRuns: ScratchSpan<Bool> = arena.uninitializedSpan(count: edges.count)
        for (edgeIndex, edge) in edges.enumerated() { hasRuns[edgeIndex] = writeEndRuns(of: route(of: edge), into: runs.part((4 * edgeIndex)..<(4 * edgeIndex + 4))) }
        return countCrossings(segments, nodes: nodes, edges: edges, runs: LayeredRouteEndRuns(points: runs, hasRuns: hasRuns), arena: arena)
    }

    #if DEBUG
    /// The nodes and edges counted, as lists, for the tests that count every compound layout's crossings again.
    private static func record(nodes: ScratchSpan<LayeredCompoundNode>, edges: ScratchSpan<LayeredCompoundSpanEdge>, routePoints: ScratchSpan<LayeredRoutePoint>,
                               style: LayeredRouteStyle) {
        guard let recording = LayeredLayoutRecording.current else { return }
        let recordedEdges = edges.map { edge in
            var recorded = LayeredCompoundEdge(source: edge.source, target: edge.target, minimumLength: edge.minimumLength, labelWidth: edge.labelWidth,
                                               labelHeight: edge.labelHeight)
            recorded.labelCenter = edge.labelCenter
            recorded.route = Array(routePoints.part(edge.routeStart..<(edge.routeStart + edge.routeCount)))
            return recorded
        }
        recording.routeCrossings.append((Array(nodes), recordedEdges, style))
    }
    #endif

    /// The straight run at each end of a route: its first point to where it leaves that line, and the last likewise,
    /// written to `runs`; whether the route has them (two points or more).
    private static func writeEndRuns(of route: ScratchSpan<LayeredRoutePoint>, into runs: ScratchSpan<CGPoint>) -> Bool {
        guard route.count >= 2 else { return false }
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
        runs[0] = route[0].point
        runs[1] = route[forward].point
        runs[2] = route[backward].point
        runs[3] = route[last].point
        return true
    }

    /// Whether (x, y) lies on the run at the start (`end` 1) or end of the route of `edge`.
    static func isOnRun(_ runs: LayeredRouteEndRuns, edge: Int, end: UInt8, x: Double, y: Double) -> Bool {
        guard runs.hasRuns[edge] else { return false }
        let start = runs.points[4 * edge + (end == 1 ? 0 : 2)]
        let finish = runs.points[4 * edge + (end == 1 ? 1 : 3)]
        let deltaX = finish.x - start.x
        let deltaY = finish.y - start.y
        let lengthSquared = deltaX * deltaX + deltaY * deltaY
        let along = lengthSquared > 0 ? max(0, min(1, ((x - start.x) * deltaX + (y - start.y) * deltaY) / lengthSquared)) : 0
        return hypot(x - start.x - along * deltaX, y - start.y - along * deltaY) < LayeredCompoundConstants.inLine
    }
}

/// The straight runs at the ends of every edge's route, four points an edge (start, where the first run ends, where the
/// last starts, end), and whether each edge has them.
struct LayeredRouteEndRuns {
    let points: ScratchSpan<CGPoint>
    let hasRuns: ScratchSpan<Bool>
}
