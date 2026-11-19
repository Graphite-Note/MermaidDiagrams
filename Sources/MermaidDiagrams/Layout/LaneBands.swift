/**
 * File: LaneBands.swift
 * ---------------------
 * Layer: Core
 * Description: The lane layout's ranks along the flow: a band per rank after the lanes' titles, the room after each rank
 *              closed up where only plain handoffs and straight lines pass.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 19/11/2026
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

    private(set) var starts: [CGFloat] = []
    private(set) var ends: [CGFloat] = []
    /// The diagram's length along the flow, its lanes' titles included.
    private(set) var length: CGFloat = 0

    init(pass: LanePass) {
        let separations = Self.separations(pass)
        var position = pass.titleDepth + pass.setup.endPadding
        for (rank, row) in pass.rows.enumerated() {
            let depth = row.map { vertex in pass.along[vertex] }.max() ?? 0
            starts.append(position)
            ends.append(position + depth)
            position += depth + (rank == pass.maximumRank ? 0 : separations[rank])
        }
        length = position + pass.setup.endPadding
    }

    /// The room after each rank.
    private static func separations(_ pass: LanePass) -> [CGFloat] {
        let full = pass.spacing.rankSeparation / CGFloat(pass.setup.step)
        guard pass.isPlain.contains(true) else { return Array(repeating: full, count: pass.maximumRank + 1) }
        var separations = [CGFloat](repeating: full / closing, count: pass.maximumRank + 1)
        for (edgeIndex, edge) in pass.setup.edges.enumerated() {
            let upper = edge.upper
            let lower = edge.lower
            let span = pass.spans[edgeIndex]
            if pass.isPlain[edgeIndex] {
                guard edge.labelAlong > 0, span <= pass.setup.step else { continue }
                let room = min(full, (edge.labelAlong + 2 * turnRoom - min(pass.along[upper], pass.along[lower]) / 2) / CGFloat(span))
                for rank in pass.rank[upper]..<pass.rank[lower] { separations[rank] = max(separations[rank], room) }
                continue
            }
            guard let first = pass.firstPassingPoint[edgeIndex], span > pass.setup.step * edge.minimumRankSpan else {
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
