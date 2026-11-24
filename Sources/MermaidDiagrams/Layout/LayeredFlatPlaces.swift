/**
 * File: LayeredFlatPlaces.swift
 * -----------------------------
 * Layer: Core
 * Description: Writes where Pele's layered layout puts each node, and each edge's route and label, in flow space.
 *
 * Authors: Bahey Shalash
 * Version: 0.3
 * Date: 24/11/2026
 */

import CoreGraphics

extension LayeredFlatLayout {
    /// The nodes' places, the leftmost edge of anything at 0: where edges spread along their nodes, a rank whose nodes
    /// only send edges on stands on one line and one whose nodes only receive them hangs from one; any other rank's
    /// nodes are centred in its band. Each edge from its upper node's side to its lower's, through its pieces' tracks
    /// and its bends, in its own direction, appended to `points`. Returns the width and height.
    mutating func writePlaces(graph: LayeredFlatGraph, across: ScratchSpan<Double>, bands: LayeredFlatBands, pieceStart: ScratchSpan<Int>,
                              isOnLine: ScratchSpan<Bool>) -> (width: Double, height: Double) {
        var lowest = Double.infinity
        var highest = -Double.infinity
        for vertex in 0..<graph.vertexCount {
            lowest = min(lowest, across[vertex] - graph.vertexWidth[vertex] / 2)
            highest = max(highest, across[vertex] + graph.vertexWidth[vertex] / 2)
        }
        let arrives = arena.span(count: graph.maximumRank + 1, repeating: false)
        let leaves = arena.span(count: graph.maximumRank + 1, repeating: false)
        for node in 0..<graph.nodeCount where graph.vertexKind[node] == .node && segmentFromEnd != nil {
            if graph.predecessorStart[node + 1] > graph.predecessorStart[node] { arrives[graph.vertexRank[node]] = true }
            if graph.successorStart[node + 1] > graph.successorStart[node] { leaves[graph.vertexRank[node]] = true }
        }
        for node in nodes.indices {
            let rank = nodes[node].rank
            nodes[node].x = across[node] - lowest
            if graph.vertexKind[node] == .node && leaves[rank] && !arrives[rank] {
                nodes[node].y = bands.bandBottom[rank] - nodes[node].height / 2
            } else if graph.vertexKind[node] == .node && arrives[rank] && !leaves[rank] {
                nodes[node].y = bands.bandTop[rank] + nodes[node].height / 2
            } else {
                nodes[node].y = (bands.bandTop[rank] + bands.bandBottom[rank]) / 2
            }
        }
        for edgeIndex in edges.indices {
            writeRoute(edgeIndex, graph: graph, across: across, bands: bands, pieceStart: pieceStart, isOnLine: isOnLine, leftmost: lowest)
        }
        return (highest - lowest, bands.height)
    }

    private mutating func writeRoute(_ edgeIndex: Int, graph: LayeredFlatGraph, across: ScratchSpan<Double>, bands: LayeredFlatBands,
                                     pieceStart: ScratchSpan<Int>, isOnLine: ScratchSpan<Bool>, leftmost: Double) {
        let edge = edges[edgeIndex]
        let first = nodes[edge.isReversed ? edge.head : edge.tail]
        let last = nodes[edge.isReversed ? edge.tail : edge.head]
        let pointStart = points.count
        points.append(CGPoint(x: first.x + (edge.isReversed ? edge.headOffset : edge.tailOffset), y: first.y + first.height / 2))
        let firstOfEdge = firstBend[edgeIndex]
        if let pieces = bands.pieces, pieceStart[edgeIndex + 1] > pieceStart[edgeIndex] {
            for piece in pieceStart[edgeIndex]..<pieceStart[edgeIndex + 1] {
                let onTracks = options.runsOnTracks
                if pieces.track[piece] >= 0 && (onTracks || pieces.isWide[piece]) {
                    let along = bands.trackAlong(piece, runsOnTracks: onTracks)
                    points.append(CGPoint(x: pieces.from[piece] - leftmost, y: along))
                    points.append(CGPoint(x: pieces.to[piece] - leftmost, y: along))
                } else if pieces.track[piece] > 0 {
                    // A short piece among levels runs straight until past the level before its own, then turns in one S.
                    points.append(CGPoint(x: pieces.from[piece] - leftmost, y: bands.trackAlong(piece, onTrack: pieces.track[piece] - 1, runsOnTracks: onTracks)))
                }
                let bend = pieces.lower[piece]
                if bend >= 0 { appendBend(bend, graph: graph, across: across, bands: bands, leftmost: leftmost) }
            }
        } else if firstOfEdge >= 0 {
            for bend in firstOfEdge..<(firstOfEdge + edgeRankSpan[edgeIndex] - 1) where !isOnLine[bend] {
                appendBend(bend, graph: graph, across: across, bands: bands, leftmost: leftmost)
            }
        }
        points.append(CGPoint(x: last.x + (edge.isReversed ? edge.tailOffset : edge.headOffset), y: last.y - last.height / 2))
        let route = points.elements.part(pointStart..<points.count)
        if edge.isReversed { route.reverse(0..<route.count) }
        edges[edgeIndex].pointStart = pointStart
        edges[edgeIndex].pointCount = route.count
        writeLabelCenter(of: edgeIndex, route: route, graph: graph, across: across, bands: bands, leftmost: leftmost)
    }

    /// The center of the edge's label: its place in its rank, or the middle of a direct edge's route.
    private func writeLabelCenter(of edgeIndex: Int, route: ScratchSpan<CGPoint>, graph: LayeredFlatGraph, across: ScratchSpan<Double>,
                                  bands: LayeredFlatBands, leftmost: Double) {
        let label = labelVertex[edgeIndex]
        if label >= 0 {
            let rank = graph.vertexRank[label]
            edges[edgeIndex].labelCenter = CGPoint(x: across[label] - leftmost, y: (bands.bandTop[rank] + bands.bandBottom[rank]) / 2)
        } else if edges[edgeIndex].labelWidth > 0 {
            let start = route[0]
            let end = route[route.count - 1]
            edges[edgeIndex].labelCenter = CGPoint(x: (start.x + end.x) / 2, y: (start.y + end.y) / 2)
        }
    }

    private mutating func appendBend(_ bend: Int, graph: LayeredFlatGraph, across: ScratchSpan<Double>, bands: LayeredFlatBands, leftmost: Double) {
        let rank = graph.vertexRank[bend]
        let inset = bands.inset(of: bend, graph: graph, runsOnTracks: options.runsOnTracks)
        points.append(CGPoint(x: across[bend] - leftmost, y: bands.bandTop[rank] + inset))
        if bands.bandBottom[rank] > bands.bandTop[rank] { points.append(CGPoint(x: across[bend] - leftmost, y: bands.bandBottom[rank] - inset)) }
    }
}
