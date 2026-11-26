/**
 * File: LaneLayout.swift
 * ----------------------
 * Layer: Core
 * Description: Lays a graph out in swimlanes as Pele's `laneLayout` does, on the thread's scratch arena: every top-level
 *              group a lane the length of the diagram, ranks shared across lanes, each box kept in its lane, handoffs
 *              given simple routes of their own; the placement read where it lies in the arena or copied into lists.
 *
 * Authors: Bahey Shalash
 * Version: 0.4
 * Date: 26/11/2026
 */

import CoreGraphics

/// Lays a graph out in swimlanes, as Pele's `layout/lanes.ts` does. Every top-level group is a lane, a band that runs the
/// length of the diagram along the flow; ranks are shared by all lanes (Pele's own ranking, `LaneRanking`), so that a
/// step sits level with the steps that happen at the same time in other lanes, and each box stays inside its lane
/// (`LaneLayoutItems`, `LanePass`, `LaneBands`, `LanePlacedPass`). A handoff given a simple route of its own
/// (`LaneHandoffRouting`) needs no room kept for it through the ranks it passes, so the lanes are laid out again without it,
/// up to three times; a handoff that then loses its route goes back to the ranked one. Routing is most of the work, so a
/// large graph is laid out once. It never fails: its passing points are bounded (`LanePass.maximumPassingPointCount`) and so
/// is its routing's work. Every working list is a span of the calling thread's scratch arena, a pass's given back before
/// the next one, so a layout allocates only its result.
enum LaneLayout {
    static let roundCount = 3

    static func place(_ graph: LaneLayoutGraph, spacing: LayeredSpacing) -> LaneLayoutPlacement {
        withPlacement(graph, spacing: spacing) { placed in placed.placement }
    }

    /// `body` given where the layout put everything, read from the routed pass in the calling thread's arena, which it
    /// must not keep: a host that moves the boxes and routes onto its page in place needs no list of the placement.
    static func withPlacement<Result>(_ graph: LaneLayoutGraph, spacing: LayeredSpacing, _ body: (LaneLayoutPlacedView) -> Result) -> Result {
        DiagramScratchArena.withCurrentThread { arena in body(placed(graph.spans(in: arena), spacing: spacing, arena: arena)) }
    }

    /// Where the layout put a graph built in `arena`, read from the routed pass in that arena: valid until the arena is
    /// released past the graph.
    static func placed(_ graph: LaneLayoutSpanGraph, spacing: LayeredSpacing, arena: DiagramScratchArena) -> LaneLayoutPlacedView {
        guard !graph.boxes.isEmpty else { return LaneLayoutPlacedView(emptyWithEdgeCount: graph.edges.count, arena: arena) }
        return LaneLayoutPlacedView(place(graph, spacing: spacing, arena: arena))
    }

    private static func place(_ graph: LaneLayoutSpanGraph, spacing: LayeredSpacing, arena: DiagramScratchArena) -> LaneHandoffRouting {
        let setup = LaneLayoutItems(graph: graph, arena: arena)
        let isPlain = arena.span(count: setup.edges.count, repeating: false)
        let next = arena.span(count: setup.edges.count, repeating: false)
        let keepsMargin = arena.span(count: setup.laneCount, repeating: false)
        let passStart = arena.mark()
        var routed = pass(setup, spacing: spacing, isPlain: isPlain, keepsMargin: keepsMargin, arena: arena)
        for round in 0..<roundCount where routed.work <= LaneHandoffRouting.routeBudget / LaneHandoffRouting.relayDivisor {
            for edgeIndex in 0..<next.count { next[edgeIndex] = round == 0 ? routed.isRouted[edgeIndex] : isPlain[edgeIndex] && routed.isRouted[edgeIndex] }
            if next.elementsEqual(isPlain), routed.usesMargin.elementsEqual(keepsMargin) { break }
            isPlain.copyElements(from: next)
            keepsMargin.copyElements(from: routed.usesMargin)
            arena.release(to: passStart)
            routed = pass(setup, spacing: spacing, isPlain: isPlain, keepsMargin: keepsMargin, arena: arena)
        }
        if zip(isPlain, routed.isRouted).contains(where: { plain, isRouted in plain && !isRouted }) {
            isPlain.fill(with: false)
            keepsMargin.fill(with: false)
            arena.release(to: passStart)
            routed = pass(setup, spacing: spacing, isPlain: isPlain, keepsMargin: keepsMargin, arena: arena)
        }
        return routed
    }

    private static func pass(_ setup: LaneLayoutItems, spacing: LayeredSpacing, isPlain: ScratchSpan<Bool>, keepsMargin: ScratchSpan<Bool>,
                             arena: DiagramScratchArena) -> LaneHandoffRouting {
        let pass = LanePass(setup: setup, spacing: spacing, isPlain: isPlain, keepsMargin: keepsMargin, arena: arena)
        return LaneHandoffRouting(placed: LanePlacedPass(pass: pass, bands: LaneBands(pass: pass, arena: arena), arena: arena), arena: arena)
    }

}

/// Where the lane layout put everything, on the page from the origin, read from the routed pass in the calling thread's
/// arena (`LaneLayout.withPlacement`): what `LaneLayoutPlacement` copies into lists.
struct LaneLayoutPlacedView {
    let size: CGSize
    /// Each box's frame.
    let frames: ScratchSpan<CGRect>
    let laneTitleDepth: CGFloat
    /// The lanes, by box, in the order they are placed across the flow.
    let lanes: ScratchSpan<Int>
    /// For each edge, the center of its text.
    let labelCenters: ScratchSpan<CGPoint>
    private let placed: LanePlacedPass?

    init(_ routed: LaneHandoffRouting) {
        let placed = routed.placed
        let breadth = placed.pass.laneStarts[placed.pass.laneStarts.count - 1]
        let length = placed.bands.length
        size = placed.runsAcross ? CGSize(width: length, height: breadth) : CGSize(width: breadth, height: length)
        frames = placed.frames
        laneTitleDepth = placed.pass.titleDepth
        lanes = placed.pass.setup.lanes
        labelCenters = placed.labelCenters
        self.placed = placed
    }

    /// A graph without boxes: nothing placed, no edge routed.
    init(emptyWithEdgeCount edgeCount: Int, arena: DiagramScratchArena) {
        size = .zero
        frames = .empty
        laneTitleDepth = 0
        lanes = .empty
        labelCenters = arena.span(count: edgeCount, repeating: CGPoint.zero)
        placed = nil
    }

    /// The points edge `edgeIndex` passes from where it leaves its source's box to where it reaches its target's, each
    /// with the flow of the segment that arrives at it (`axis` 0 for a vertical flow); empty for an edge it gave no route
    /// of two points or more, such as one from a box to itself.
    func route(of edgeIndex: Int) -> ScratchSpan<LaneRoutePoint> {
        guard let placed else { return .empty }
        let route = placed.route(of: edgeIndex)
        return route.count >= 2 ? route : .empty
    }

    /// The placement copied into lists: the routes' points with each segment's flow.
    var placement: LaneLayoutPlacement {
        var routes: [LaneLayoutRoute?] = []
        routes.reserveCapacity(labelCenters.count)
        for edgeIndex in 0..<labelCenters.count {
            let route = route(of: edgeIndex)
            guard route.count >= 2 else {
                routes.append(nil)
                continue
            }
            routes.append(LaneLayoutRoute(points: route.map(\.point), segmentsRunVertically: route.dropFirst().map { point in point.axis == 0 }))
        }
        return LaneLayoutPlacement(size: size, frames: Array(frames), laneTitleDepth: laneTitleDepth, lanes: Array(lanes), routes: routes,
                                   labelCenters: Array(labelCenters))
    }

}
