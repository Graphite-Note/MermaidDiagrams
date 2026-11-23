/**
 * File: LayeredFlatRouting.swift
 * ------------------------------
 * Layer: Core
 * Description: The steps of Pele's layered layout after ordering: positions, ends, straightening and the edges' pieces.
 *
 * Authors: Bahey Shalash
 * Version: 0.2
 * Date: 23/11/2026
 */

extension LayeredFlatLayout {
    /// Positions the ordered graph, spreads and settles the ends, straightens the bends, cuts the edges into the pieces
    /// that cross one gap each, sizes the gaps and writes every node's place and every edge's route.
    mutating func route(graph: inout LayeredFlatGraph) -> (width: Double, height: Double) {
        if let fromEnds = segmentFromEnd, let toEnds = segmentToEnd { graph.spreadEnds(nodes: nodes, fromEnds: fromEnds, toEnds: toEnds) }
        var across = LayeredFlatPositioning.positions(&graph, options: options)
        let emptyRanks = graph.emptyRanks()
        if let fromEnds = segmentFromEnd, let toEnds = segmentToEnd {
            let free = graph.freeEnds(fromEnds: fromEnds, toEnds: toEnds)
            LayeredFlatLabelAlignment(graph: graph, nodes: nodes, free: free, options: options, emptyRanks: emptyRanks).align(&across)
            var settling = LayeredFlatEndSettling(graph: consume graph, nodes: nodes, across: across, fromEnds: fromEnds, toEnds: toEnds,
                                                  free: free, emptyRanks: emptyRanks)
            settling.settle()
            graph = (consume settling).graph
            var snapping = LayeredFlatSnapping(graph: graph, options: options, emptyRanks: emptyRanks)
            snapping.snap(&across)
            for edgeIndex in edges.indices where !isDirect[edgeIndex] {
                let upperOffset = graph.segmentFromOffset[firstSegment[edgeIndex]]
                let lowerOffset = graph.segmentToOffset[lastSegment[edgeIndex]]
                edges[edgeIndex].tailOffset = edges[edgeIndex].isReversed ? lowerOffset : upperOffset
                edges[edgeIndex].headOffset = edges[edgeIndex].isReversed ? upperOffset : lowerOffset
            }
        }
        graph.alignPorts(&across, emptyRanks: emptyRanks)
        // A rank that holds nothing but bends is only there because another edge has a label or a twin: its bends move
        // onto the straight line between their edges' ends, and one that gets there is left out of the route.
        var isOnLine = [Bool](repeating: false, count: graph.vertexCount)
        if let emptyRanks, !options.runsOnTracks {
            graph.straighten(&across, emptyRanks: emptyRanks, firstBend: firstBend, edgeRankSpan: edgeRankSpan,
                             separation: options.keepsTwinsApart ? 0 : options.edgeSeparation, isOnLine: &isOnLine)
        }
        if !options.runsOnTracks {
            graph.passLabels(&across, firstBend: firstBend, edgeRankSpan: edgeRankSpan, clearance: options.edgeSeparation, isOnLine: &isOnLine)
        }
        let usesPieces = options.runsOnTracks || (segmentFromEnd != nil && !options.isStraight)
        let (pieces, pieceStart) = usesPieces ? cutPieces(graph: graph, across: across, emptyRanks: emptyRanks, isOnLine: isOnLine) : (nil, [])
        var bands = LayeredFlatBands(layout: self, graph: graph, across: across, emptyRanks: emptyRanks, pieces: pieces)
        bands.size(layout: self, graph: graph)
        return writePlaces(graph: graph, across: across, bands: bands, pieceStart: pieceStart, isOnLine: isOnLine)
    }

    /// Every edge cut where it passes a rank that holds something, each piece crossing one gap; an edge that keeps a
    /// bend to stay clear of its twin, or has a bend left out in a rank of labels, is drawn through its bends as it is.
    private func cutPieces(graph: LayeredFlatGraph, across: [Double], emptyRanks: [Bool]?, isOnLine: [Bool]) -> (LayeredEdgePieces, [Int]) {
        var pieces = LayeredEdgePieces()
        var pieceStart = [Int](repeating: 0, count: edges.count + 1)
        for edgeIndex in edges.indices {
            pieceStart[edgeIndex] = pieces.count
            if isDirect[edgeIndex] { continue }
            let firstOfEdge = firstBend[edgeIndex]
            let bends = firstOfEdge < 0 ? 0..<0 : firstOfEdge..<(firstOfEdge + edgeRankSpan[edgeIndex] - 1)
            let isTwin = !options.runsOnTracks && bends.contains { bend in (emptyRanks?[graph.vertexRank[bend]] ?? false) != isOnLine[bend] }
            if isTwin { continue }
            let first = firstSegment[edgeIndex]
            var at = across[graph.segmentFrom[first]] + graph.segmentFromOffset[first]
            var rank = graph.vertexRank[graph.segmentFrom[first]]
            for bend in bends where !(emptyRanks?[graph.vertexRank[bend]] ?? false) {
                pieces.append(from: at, to: across[bend], rank: rank, lower: bend)
                at = across[bend]
                rank = graph.vertexRank[bend]
            }
            let last = lastSegment[edgeIndex]
            pieces.append(from: at, to: across[graph.segmentTo[last]] + graph.segmentToOffset[last], rank: rank, lower: -1)
        }
        pieceStart[edges.count] = pieces.count
        return (pieces, pieceStart)
    }
}

extension LayeredEdgePieces {
    mutating func append(from: Double, to: Double, rank: Int, lower: Int) {
        self.from.append(from)
        self.to.append(to)
        self.rank.append(rank)
        self.lower.append(lower)
    }
}
