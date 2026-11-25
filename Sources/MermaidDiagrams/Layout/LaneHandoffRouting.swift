/**
 * File: LaneHandoffRouting.swift
 * ------------------------------
 * Layer: Core
 * Description: The lane layout's handoffs given simple routes of their own, on spans of the thread's scratch arena:
 *              one corner toward the other lane then along the flow (or the other way round), else around the margin of
 *              a lane, kept clear of boxes, texts and other lines, as Pele's `laneLayout` routes them.
 *
 * Authors: Bahey Shalash
 * Version: 0.2
 * Date: 24/11/2026
 */

import CoreGraphics

/// Up to four points of a route tried for a handoff, in flow space, kept in place rather than in a list.
struct LaneWay {
    private(set) var count = 0
    private var first = LaneFlowPoint(across: 0, along: 0)
    private var second = LaneFlowPoint(across: 0, along: 0)
    private var third = LaneFlowPoint(across: 0, along: 0)
    private var fourth = LaneFlowPoint(across: 0, along: 0)

    init() {}

    /// A route of three points, each (across, along).
    init(_ first: (CGFloat, CGFloat), _ second: (CGFloat, CGFloat), _ third: (CGFloat, CGFloat)) {
        append(LaneFlowPoint(across: first.0, along: first.1))
        append(LaneFlowPoint(across: second.0, along: second.1))
        append(LaneFlowPoint(across: third.0, along: third.1))
    }

    /// A route of four points, each (across, along).
    init(_ first: (CGFloat, CGFloat), _ second: (CGFloat, CGFloat), _ third: (CGFloat, CGFloat), _ fourth: (CGFloat, CGFloat)) {
        self.init(first, second, third)
        append(LaneFlowPoint(across: fourth.0, along: fourth.1))
    }

    mutating func append(_ point: LaneFlowPoint) {
        switch count {
        case 0: first = point
        case 1: second = point
        case 2: third = point
        default:
            precondition(count == 3, "A handoff's route has at most four points")
            fourth = point
        }
        count += 1
    }

    subscript(index: Int) -> LaneFlowPoint {
        precondition(index >= 0 && index < count, "Index out of range of a handoff's route")
        switch index {
        case 0: return first
        case 1: return second
        case 2: return third
        default: return fourth
        }
    }
}

/// Routes the handoffs of a placed pass, as Pele does: an edge between two lanes, its ends not in line, may leave toward
/// the other lane and then arrive along the flow, or the other way round, so that a decision's return branch does not leave
/// through its incoming side and retrace the path past the step before. Each of the two single-corner routes is tried and
/// kept when no box, no other edge's text and no other line along the same line is in its way; with both blocked, the
/// handoff goes out to the margin of a lane, along it and back in level with its end, in the margin that crosses the fewest
/// other edges and shares the fewest ends with them. A route's text sits on its longest stretch that holds it. The work is
/// bounded: past two million steps no handoff is routed, past a quarter of a million none goes around.
struct LaneHandoffRouting {
    static let routeBudget = 2_000_000
    static let relayDivisor = 8
    /// Lines closer than this are drawn as one.
    static let nearDistance: CGFloat = 4
    /// The run a route keeps straight either side of a corner.
    static let turnRoom: CGFloat = 20
    /// The room a lane keeps beside a handoff along its margin, and how much of it is between the handoff and the lane's items.
    static let marginRoom: CGFloat = 20
    static let legRoom: CGFloat = 14

    var placed: LanePlacedPass
    /// By ranked edge, whether it took a route of its own.
    let isRouted: ScratchSpan<Bool>
    /// By lane, whether a handoff runs along its margin.
    let usesMargin: ScratchSpan<Bool>
    let work: Int
    /// Each edge's text, in flow space; empty when the work is past the budget.
    let labels: ScratchSpan<LaneFlowPoint>

    init(placed: LanePlacedPass, arena: DiagramScratchArena) {
        self.placed = placed
        let setup = placed.pass.setup
        isRouted = arena.span(count: setup.edges.count, repeating: false)
        usesMargin = arena.span(count: setup.laneCount, repeating: false)
        let routePointCount = placed.routePoints.count
        work = setup.edges.count * (setup.items.count + setup.graphEdges.count + routePointCount)
        guard work <= Self.routeBudget else {
            labels = .empty
            return
        }
        let labels: ScratchSpan<LaneFlowPoint> = arena.uninitializedSpan(count: setup.graphEdges.count)
        self.labels = labels
        for edgeIndex in 0..<labels.count { labels[edgeIndex] = flowPoint(placed.labelCenters[edgeIndex]) }
        for rankedIndex in 0..<setup.edges.count { routeHandoff(rankedIndex, arena: arena) }
    }

    var pass: LanePass { placed.pass }

    /// A page point in flow space.
    func flowPoint(_ point: CGPoint) -> LaneFlowPoint {
        let pageAlong = placed.runsAcross ? point.x : point.y
        let along = pass.setup.isFlipped ? pass.titleDepth + placed.bands.length - pageAlong : pageAlong
        return LaneFlowPoint(across: placed.runsAcross ? point.y : point.x, along: along)
    }

    @inline(__always)
    func pagePoint(_ point: LaneFlowPoint) -> CGPoint {
        placed.pagePoint(across: point.across, along: point.along)
    }

    private mutating func routeHandoff(_ rankedIndex: Int, arena: DiagramScratchArena) {
        let edge = pass.setup.edges[rankedIndex]
        let source = edge.tail
        let target = edge.head
        let sourceAcross = pass.centers[source]
        let targetAcross = pass.centers[target]
        guard pass.lane[source] != pass.lane[target], abs(targetAcross - sourceAcross) >= 1 else { return }
        let sourceAlong = placed.bandMiddle(of: source)
        let targetAlong = placed.bandMiddle(of: target)
        let acrossSign: CGFloat = targetAcross > sourceAcross ? 1 : -1
        let alongSign: CGFloat = targetAlong > sourceAlong ? 1 : (targetAlong < sourceAlong ? -1 : 0)
        let acrossFirst = LaneWay((sourceAcross + acrossSign * pass.across[source] / 2, sourceAlong), (targetAcross, sourceAlong),
                                  (targetAcross, targetAlong - alongSign * pass.along[target] / 2))
        if attempt(acrossFirst, margin: 2, rankedIndex: rankedIndex, arena: arena) { return }
        let alongFirst = LaneWay((sourceAcross, sourceAlong + alongSign * pass.along[source] / 2), (sourceAcross, targetAlong),
                                 (targetAcross - acrossSign * pass.across[target] / 2, targetAlong))
        if attempt(alongFirst, margin: 2, rankedIndex: rankedIndex, arena: arena) { return }
        guard work <= Self.routeBudget / Self.relayDivisor else { return }
        let around = aroundRoutes(rankedIndex)
        for index in 0..<around.count where attempt(around[index].way, margin: 1, rankedIndex: rankedIndex, arena: arena) {
            usesMargin[around[index].lane] = true
            return
        }
    }

    /// The routes around a lane's margin, out from the source's side, along the margin and in to the target's side level
    /// with it, in each margin of the two lanes, the target's first, the cheapest first: each end shared with another edge
    /// and each other edge crossed costing a million, then the length.
    private func aroundRoutes(_ rankedIndex: Int) -> LaneAroundRoutes {
        let edge = pass.setup.edges[rankedIndex]
        let (source, target) = (edge.tail, edge.head)
        let (sourceAcross, targetAcross) = (pass.centers[source], pass.centers[target])
        let (sourceAlong, targetAlong) = (placed.bandMiddle(of: source), placed.bandMiddle(of: target))
        let lanes = pass.lane[source] < pass.lane[target] ? (pass.lane[target], pass.lane[source]) : (pass.lane[source], pass.lane[target])
        var around = LaneAroundRoutes()
        for laneNumber in 0..<2 {
            let lane = laneNumber == 0 ? lanes.0 : lanes.1
            let inset = max(pass.paddings[lane] - Self.legRoom, min(pass.paddings[lane] / 2, Self.marginRoom - Self.legRoom))
            for side in 0..<2 {
                let margin = side == 0 ? pass.laneStarts[lane] + inset : pass.laneStarts[lane + 1] - inset
                if abs(margin - sourceAcross) < pass.across[source] / 2 + 4 || abs(margin - targetAcross) < pass.across[target] / 2 + 4 { continue }
                let way = LaneWay((sourceAcross + Self.sign(margin - sourceAcross) * pass.across[source] / 2, sourceAlong), (margin, sourceAlong),
                                  (margin, targetAlong), (targetAcross + Self.sign(margin - targetAcross) * pass.across[target] / 2, targetAlong))
                around.append(LaneAroundRoute(way: way, cost: cost(of: way, edgeIndex: edge.edgeIndex), lane: lane))
            }
        }
        around.sortByCost()
        return around
    }

    private func cost(of way: LaneWay, edgeIndex: Int) -> CGFloat {
        var cost = CGFloat(meets(pagePoint(way[0]), edgeIndex: edgeIndex) + meets(pagePoint(way[way.count - 1]), edgeIndex: edgeIndex)) * 1e6
        for index in 1..<way.count {
            let start = pagePoint(way[index - 1])
            let end = pagePoint(way[index])
            let box = CGRect(x: min(start.x, end.x), y: min(start.y, end.y), width: abs(end.x - start.x), height: abs(end.y - start.y))
            cost += CGFloat(crossings(box, edgeIndex: edgeIndex)) * 1e6 + abs(end.x - start.x) + abs(end.y - start.y)
        }
        return cost
    }

    /// JavaScript's `Math.sign`.
    static func sign(_ value: CGFloat) -> CGFloat {
        value > 0 ? 1 : (value < 0 ? -1 : 0)
    }
}

/// A route around a lane's margin, what it costs and the lane whose margin it runs along.
struct LaneAroundRoute {
    var way: LaneWay
    var cost: CGFloat
    var lane: Int
}

/// Up to four routes around a lane's margin, in the order tried, kept in place rather than in a list.
struct LaneAroundRoutes {
    private(set) var count = 0
    private var first = LaneAroundRoute(way: LaneWay(), cost: 0, lane: 0)
    private var second = LaneAroundRoute(way: LaneWay(), cost: 0, lane: 0)
    private var third = LaneAroundRoute(way: LaneWay(), cost: 0, lane: 0)
    private var fourth = LaneAroundRoute(way: LaneWay(), cost: 0, lane: 0)

    subscript(index: Int) -> LaneAroundRoute {
        get {
            precondition(index >= 0 && index < count, "Index out of range of the routes around a margin")
            switch index {
            case 0: return first
            case 1: return second
            case 2: return third
            default: return fourth
            }
        }
        set {
            precondition(index >= 0 && index < count, "Index out of range of the routes around a margin")
            switch index {
            case 0: first = newValue
            case 1: second = newValue
            case 2: third = newValue
            default: fourth = newValue
            }
        }
    }

    mutating func append(_ route: LaneAroundRoute) {
        precondition(count < 4, "Two lanes have four margins")
        count += 1
        self[count - 1] = route
    }

    /// The cheapest first, and of two that cost the same the one appended first, as a stable sort by cost leaves them.
    mutating func sortByCost() {
        guard count > 1 else { return }
        for index in 1..<count {
            var position = index
            while position > 0, self[position].cost < self[position - 1].cost {
                let moved = self[position]
                self[position] = self[position - 1]
                self[position - 1] = moved
                position -= 1
            }
        }
    }
}
