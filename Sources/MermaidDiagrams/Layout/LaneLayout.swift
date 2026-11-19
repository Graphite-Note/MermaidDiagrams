/**
 * File: LaneLayout.swift
 * ----------------------
 * Layer: Core
 * Description: Lays a graph out in swimlanes as Pele's `laneLayout` does: every top-level group a lane the length of the
 *              diagram, ranks shared across lanes, each box kept in its lane, handoffs given simple routes of their own.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 19/11/2026
 */

import CoreGraphics

/// Lays a graph out in swimlanes, as Pele's `layout/lanes.ts` does. Every top-level group is a lane, a band that runs the
/// length of the diagram along the flow; ranks are shared by all lanes (Pele's own ranking, `balancedRanks`), so that a
/// step sits level with the steps that happen at the same time in other lanes, and each box stays inside its lane
/// (`LaneLayoutItems`, `LanePass`, `LaneBands`, `LanePlacedPass`). A handoff given a simple route of its own
/// (`LaneHandoffRouting`) needs no room kept for it through the ranks it passes, so the lanes are laid out again without it,
/// up to three times; a handoff that then loses its route goes back to the ranked one. Routing is most of the work, so a
/// large graph is laid out once. It never fails: its passing points are bounded (`LanePass.maximumPassingPointCount`) and so
/// is its routing's work.
enum LaneLayout {
    static let roundCount = 3

    static func place(_ graph: LaneLayoutGraph, spacing: LayeredSpacing) -> LaneLayoutPlacement {
        guard !graph.boxes.isEmpty else {
            return LaneLayoutPlacement(size: .zero, frames: [], laneTitleDepth: 0, lanes: [], routes: graph.edges.map { _ in nil },
                                       labelCenters: graph.edges.map { _ in .zero })
        }
        let setup = LaneLayoutItems(graph: graph)
        var isPlain = [Bool](repeating: false, count: setup.edges.count)
        var keepsMargin = [Bool](repeating: false, count: setup.laneCount)
        var routed = pass(setup, spacing: spacing, isPlain: isPlain, keepsMargin: keepsMargin)
        for round in 0..<roundCount where routed.work <= LaneHandoffRouting.routeBudget / LaneHandoffRouting.relayDivisor {
            let next = round == 0 ? routed.isRouted : zip(isPlain, routed.isRouted).map { plain, isRouted in plain && isRouted }
            if next == isPlain, routed.usesMargin == keepsMargin { break }
            isPlain = next
            keepsMargin = routed.usesMargin
            routed = pass(setup, spacing: spacing, isPlain: isPlain, keepsMargin: keepsMargin)
        }
        if zip(isPlain, routed.isRouted).contains(where: { plain, isRouted in plain && !isRouted }) {
            routed = pass(setup, spacing: spacing, isPlain: Array(repeating: false, count: setup.edges.count),
                          keepsMargin: Array(repeating: false, count: setup.laneCount))
        }
        return placement(of: routed)
    }

    private static func pass(_ setup: LaneLayoutItems, spacing: LayeredSpacing, isPlain: [Bool], keepsMargin: [Bool]) -> LaneHandoffRouting {
        let pass = LanePass(setup: setup, spacing: spacing, isPlain: isPlain, keepsMargin: keepsMargin)
        return LaneHandoffRouting(placed: LanePlacedPass(pass: pass, bands: LaneBands(pass: pass)))
    }

    /// The routed pass as the layout's result: the routes' points with each segment's flow, and the size.
    private static func placement(of routed: LaneHandoffRouting) -> LaneLayoutPlacement {
        let placed = routed.placed
        let graph = placed.pass.setup.graph
        let breadth = placed.pass.laneStarts[placed.pass.laneStarts.count - 1]
        let length = placed.bands.length
        let routes: [LaneLayoutRoute?] = graph.edges.indices.map { edgeIndex in
            let route = placed.routes[edgeIndex]
            guard route.count >= 2 else { return nil }
            return LaneLayoutRoute(points: route.map(\.point), segmentsRunVertically: route.dropFirst().map { point in point.axis == 0 })
        }
        return LaneLayoutPlacement(size: placed.runsAcross ? CGSize(width: length, height: breadth) : CGSize(width: breadth, height: length),
                                   frames: placed.frames, laneTitleDepth: placed.pass.titleDepth, lanes: placed.pass.setup.lanes, routes: routes,
                                   labelCenters: placed.labelCenters)
    }
}
