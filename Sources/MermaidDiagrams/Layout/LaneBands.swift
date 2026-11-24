/**
 * File: LaneBands.swift
 * ---------------------
 * Layer: Core
 * Description: The lane layout's ranks along the flow, on spans of the thread's scratch arena: a band per rank after
 *              the lanes' titles, the room after each rank closed up where only plain handoffs and straight lines pass.
 *
 * Authors: Bahey Shalash
 * Version: 0.2
 * Date: 24/11/2026
 */

import CoreGraphics

/// Along the flow, as Pele's `laneLayout` places its ranks: one band per rank, as deep as its deepest vertex, after the
/// lanes' titles and the end room. The room after a rank is for the edges that turn there or are only as long as they were
/// asked to be: once some edges take plain routes of their own, the ranks close up to a third of the rank separation where
/// only plain handoffs and straight lines pass, as far as the text of a handoff between them leaves it a line to sit on.
struct LaneBands {
    /// The room a turn takes, either side of a handoff's text.
    static let turnRoom: CGFloat = 20
    /// How much closer ranks close up.
    static let closing: CGFloat = 3

    let starts: ScratchSpan<CGFloat>
    let ends: ScratchSpan<CGFloat>
    /// The diagram's length along the flow, its lanes' titles included.
    let length: CGFloat

    init(pass: LanePass, arena: DiagramScratchArena) {
        let rankCount = pass.maximumRank + 1
        starts = arena.uninitializedSpan(count: rankCount)
        ends = arena.uninitializedSpan(count: rankCount)
        let mark = arena.mark()
        defer { arena.release(to: mark) }
        let separations = Self.separations(pass, arena: arena)
        var position = pass.titleDepth + pass.setup.endPadding
        for rank in 0..<rankCount {
            // The deepest vertex of the rank, kept as `Sequence.max()` keeps it: a later one only when strictly deeper.
            var depth: CGFloat = 0
            let range = pass.rowRange(rank)
            if !range.isEmpty {
                depth = pass.along[pass.rowVertices[range.lowerBound]]
                for slot in range.dropFirst() where depth < pass.along[pass.rowVertices[slot]] { depth = pass.along[pass.rowVertices[slot]] }
            }
            starts[rank] = position
            ends[rank] = position + depth
            position += depth + (rank == pass.maximumRank ? 0 : separations[rank])
        }
        length = position + pass.setup.endPadding
    }

    /// The room after each rank.
    private static func separations(_ pass: LanePass, arena: DiagramScratchArena) -> ScratchSpan<CGFloat> {
        let full = pass.spacing.rankSeparation / CGFloat(pass.setup.step)
        guard pass.isPlain.contains(true) else { return arena.span(count: pass.maximumRank + 1, repeating: full) }
        let separations = arena.span(count: pass.maximumRank + 1, repeating: full / closing)
        let edges = pass.setup.edges
        for edgeIndex in 0..<edges.count {
            let edge = edges[edgeIndex]
            let upper = edge.upper
            let lower = edge.lower
            let span = pass.spans[edgeIndex]
            if pass.isPlain[edgeIndex] {
                guard edge.labelAlong > 0, span <= pass.setup.step else { continue }
                let room = min(full, (edge.labelAlong + 2 * turnRoom - min(pass.along[upper], pass.along[lower]) / 2) / CGFloat(span))
                for rank in pass.rank[upper]..<pass.rank[lower] { separations[rank] = max(separations[rank], room) }
                continue
            }
            let first = pass.firstPassingPoint[edgeIndex]
            guard first >= 0, span > pass.setup.step * edge.minimumRankSpan else {
                for rank in pass.rank[upper]..<pass.rank[lower] { separations[rank] = full }
                continue
            }
            // A stretch that changes lane or position across keeps the full room after its rank.
            for vertex in (first - 1)..<(first + span - 1) {
                let from = vertex < first ? upper : vertex
                let to = vertex + 1 < first + span - 1 ? vertex + 1 : lower
                if pass.lane[from] != pass.lane[to] || abs(pass.centers[from] - pass.centers[to]) >= 0.5 { separations[pass.rank[from]] = full }
            }
        }
        return separations
    }
}
