/**
 * File: LaneLayout.swift
 * ----------------------
 * Layer: Core
 * Description: Lays a graph out in swimlanes as Pele's `laneLayout` does, on the thread's scratch arena: every top-level
 *              group a lane the length of the diagram, ranks shared across lanes, each box kept in its lane, handoffs
 *              given simple routes of their own.
 *
 * Authors: Bahey Shalash
 * Version: 0.2
 * Date: 24/11/2026
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
        guard !graph.boxes.isEmpty else {
            return LaneLayoutPlacement(size: .zero, frames: [], laneTitleDepth: 0, lanes: [], routes: graph.edges.map { _ in nil },
                                       labelCenters: graph.edges.map { _ in .zero })
        }
        return DiagramScratchArena.withCurrentThread { arena in place(graph, spacing: spacing, arena: arena) }
    }

    private static func place(_ graph: LaneLayoutGraph, spacing: LayeredSpacing, arena: DiagramScratchArena) -> LaneLayoutPlacement {
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
        return placement(of: routed)
    }

    private static func pass(_ setup: LaneLayoutItems, spacing: LayeredSpacing, isPlain: ScratchSpan<Bool>, keepsMargin: ScratchSpan<Bool>,
                             arena: DiagramScratchArena) -> LaneHandoffRouting {
        let pass = LanePass(setup: setup, spacing: spacing, isPlain: isPlain, keepsMargin: keepsMargin, arena: arena)
        return LaneHandoffRouting(placed: LanePlacedPass(pass: pass, bands: LaneBands(pass: pass, arena: arena), arena: arena), arena: arena)
    }

    /// The routed pass as the layout's result: the routes' points with each segment's flow, and the size.
    private static func placement(of routed: LaneHandoffRouting) -> LaneLayoutPlacement {
        let placed = routed.placed
        let setup = placed.pass.setup
        let breadth = placed.pass.laneStarts[placed.pass.laneStarts.count - 1]
        let length = placed.bands.length
        var routes: [LaneLayoutRoute?] = []
        routes.reserveCapacity(setup.graphEdges.count)
        for edgeIndex in 0..<setup.graphEdges.count {
            let route = placed.route(of: edgeIndex)
            guard route.count >= 2 else {
                routes.append(nil)
                continue
            }
            routes.append(LaneLayoutRoute(points: route.map(\.point), segmentsRunVertically: route.dropFirst().map { point in point.axis == 0 }))
        }
        return LaneLayoutPlacement(size: placed.runsAcross ? CGSize(width: length, height: breadth) : CGSize(width: breadth, height: length),
                                   frames: Array(placed.frames), laneTitleDepth: placed.pass.titleDepth, lanes: Array(setup.lanes), routes: routes,
                                   labelCenters: Array(placed.labelCenters))
    }
}
