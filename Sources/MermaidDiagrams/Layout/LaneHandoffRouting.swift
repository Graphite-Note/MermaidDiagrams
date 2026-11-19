/**
 * File: LaneHandoffRouting.swift
 * ------------------------------
 * Layer: Core
 * Description: The lane layout's handoffs given simple routes of their own: one corner toward the other lane then along
 *              the flow (or the other way round), else around the margin of a lane, kept clear of boxes, texts and other
 *              lines, as Pele's `laneLayout` routes them.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 19/11/2026
 */

import CoreGraphics

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
    var isRouted: [Bool]
    /// By lane, whether a handoff runs along its margin.
    var usesMargin: [Bool]
    let work: Int
    /// Each edge's text, in flow space (across, along).
    var labels: [(across: CGFloat, along: CGFloat)]

    init(placed: LanePlacedPass) {
        self.placed = placed
        let setup = placed.pass.setup
        isRouted = Array(repeating: false, count: setup.edges.count)
        usesMargin = Array(repeating: false, count: setup.laneCount)
        let routePointCount = placed.routes.reduce(0) { count, route in count + route.count }
        work = setup.edges.count * (setup.items.count + setup.graph.edges.count + routePointCount)
        labels = []
        guard work <= Self.routeBudget else { return }
        labels = placed.labelCenters.map { center in flowPoint(center) }
        for rankedIndex in setup.edges.indices { routeHandoff(rankedIndex) }
    }

    var pass: LanePass { placed.pass }

    /// A page point in flow space.
    func flowPoint(_ point: CGPoint) -> (across: CGFloat, along: CGFloat) {
        let pageAlong = placed.runsAcross ? point.x : point.y
        let along = pass.setup.isFlipped ? pass.titleDepth + placed.bands.length - pageAlong : pageAlong
        return (placed.runsAcross ? point.y : point.x, along)
    }

    func pagePoint(_ across: CGFloat, _ along: CGFloat) -> CGPoint {
        placed.pagePoint(across: across, along: along)
    }

    /// An edge's text's room across and along the flow.
    func labelExtent(of edgeIndex: Int) -> (across: CGFloat, along: CGFloat)? {
        guard let size = pass.setup.graph.edges[edgeIndex].labelSize, size.width > 0 else { return nil }
        return placed.runsAcross ? (size.height, size.width) : (size.width, size.height)
    }

    private mutating func routeHandoff(_ rankedIndex: Int) {
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
        let acrossFirst = [(sourceAcross + acrossSign * pass.across[source] / 2, sourceAlong), (targetAcross, sourceAlong),
                           (targetAcross, targetAlong - alongSign * pass.along[target] / 2)]
        if attempt(acrossFirst, margin: 2, rankedIndex: rankedIndex) { return }
        let alongFirst = [(sourceAcross, sourceAlong + alongSign * pass.along[source] / 2), (sourceAcross, targetAlong),
                          (targetAcross - acrossSign * pass.across[target] / 2, targetAlong)]
        if attempt(alongFirst, margin: 2, rankedIndex: rankedIndex) { return }
        guard work <= Self.routeBudget / Self.relayDivisor else { return }
        for way in aroundRoutes(rankedIndex) where attempt(way.points, margin: 1, rankedIndex: rankedIndex) {
            usesMargin[way.lane] = true
            return
        }
    }

    /// The routes around a lane's margin, out from the source's side, along the margin and in to the target's side level
    /// with it, in each margin of the two lanes, the target's first, the cheapest first: each end shared with another edge
    /// and each other edge crossed costing a million, then the length.
    private func aroundRoutes(_ rankedIndex: Int) -> [(points: [(CGFloat, CGFloat)], cost: CGFloat, lane: Int)] {
        let edge = pass.setup.edges[rankedIndex]
        let (source, target) = (edge.tail, edge.head)
        let (sourceAcross, targetAcross) = (pass.centers[source], pass.centers[target])
        let (sourceAlong, targetAlong) = (placed.bandMiddle(of: source), placed.bandMiddle(of: target))
        let lanes = pass.lane[source] < pass.lane[target] ? [pass.lane[target], pass.lane[source]] : [pass.lane[source], pass.lane[target]]
        var around: [(points: [(CGFloat, CGFloat)], cost: CGFloat, lane: Int)] = []
        for lane in lanes {
            let inset = max(pass.paddings[lane] - Self.legRoom, min(pass.paddings[lane] / 2, Self.marginRoom - Self.legRoom))
            for margin in [pass.laneStarts[lane] + inset, pass.laneStarts[lane + 1] - inset] {
                if abs(margin - sourceAcross) < pass.across[source] / 2 + 4 || abs(margin - targetAcross) < pass.across[target] / 2 + 4 { continue }
                let points = [(sourceAcross + Self.sign(margin - sourceAcross) * pass.across[source] / 2, sourceAlong), (margin, sourceAlong),
                              (margin, targetAlong), (targetAcross + Self.sign(margin - targetAcross) * pass.across[target] / 2, targetAlong)]
                around.append((points, cost(of: points, edgeIndex: edge.edgeIndex), lane))
            }
        }
        return around.enumerated().sorted { first, second in (first.element.cost, first.offset) < (second.element.cost, second.offset) }.map(\.element)
    }

    private func cost(of points: [(CGFloat, CGFloat)], edgeIndex: Int) -> CGFloat {
        let page = points.map { across, along in pagePoint(across, along) }
        var cost = CGFloat(meets(page[0], edgeIndex: edgeIndex) + meets(page[page.count - 1], edgeIndex: edgeIndex)) * 1e6
        for (start, end) in zip(page, page.dropFirst()) {
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
