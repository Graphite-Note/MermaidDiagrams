/**
 * File: LayeredFlatRouting.swift
 * ------------------------------
 * Layer: Core
 * Description: The steps of Pele's layered layout after ordering: positions, ends, straightening and the edges' pieces.
 *
 * Authors: Bahey Shalash
 * Version: 0.3
 * Date: 23/11/2026
 */

extension LayeredFlatLayout {
    /// Positions the ordered graph, spreads and settles the ends, straightens the bends, cuts the edges into the pieces
    /// that cross one gap each, sizes the gaps and writes every node's place and every edge's route.
    mutating func route(graph: inout LayeredFlatGraph) -> (width: Double, height: Double) {
        if let fromEnds = segmentFromEnd, let toEnds = segmentToEnd {
            graph.spreadEnds(nodes: nodes, fromEnds: fromEnds, toEnds: toEnds, workspace: workspace)
        }
        var across = LayeredFlatPositioning.positions(&graph, options: options, workspace: workspace)
        let emptyRanks = graph.emptyRanks(workspace: workspace)
        if let fromEnds = segmentFromEnd, let toEnds = segmentToEnd {
            settleEnds(graph: &graph, across: &across, emptyRanks: emptyRanks, fromEnds: fromEnds, toEnds: toEnds)
        }
        graph.alignPorts(&across, emptyRanks: emptyRanks)
        // A rank that holds nothing but bends is only there because another edge has a label or a twin: its bends move
        // onto the straight line between their edges' ends, and one that gets there is left out of the route.
        var isOnLine = workspace.flags(count: graph.vertexCount, repeating: false)
        if let emptyRanks, !options.runsOnTracks {
            graph.straighten(&across, emptyRanks: emptyRanks, firstBend: firstBend, edgeRankSpan: edgeRankSpan,
                             separation: options.keepsTwinsApart ? 0 : options.edgeSeparation, isOnLine: &isOnLine, workspace: workspace)
        }
        if !options.runsOnTracks {
            graph.passLabels(&across, firstBend: firstBend, edgeRankSpan: edgeRankSpan, clearance: options.edgeSeparation, isOnLine: &isOnLine,
                             workspace: workspace)
        }
        let usesPieces = options.runsOnTracks || (segmentFromEnd != nil && !options.isStraight)
        let (pieces, pieceStart) = usesPieces ? cutPieces(graph: graph, across: across, emptyRanks: emptyRanks, isOnLine: isOnLine) : (nil, [])
        var bands = LayeredFlatBands(layout: self, graph: graph, across: across, emptyRanks: emptyRanks, pieces: pieces)
        bands.size(layout: self, graph: graph)
        let placed = writePlaces(graph: graph, across: across, bands: bands, pieceStart: pieceStart, isOnLine: isOnLine)
        bands.recycle(into: workspace)
        workspace.recycle(consume across)
        workspace.recycle(consume isOnLine)
        workspace.recycle(consume pieceStart)
        if let emptyRanks { workspace.recycle(consume emptyRanks) }
        return placed
    }

    /// Where nodes spread their ends: the labels aligned, the ends settled along their sides, the vertices snapped into
    /// line, and each edge's offsets at its nodes written back. The graph moves into each step and back, so that it is
    /// never copied.
    private mutating func settleEnds(graph: inout LayeredFlatGraph, across: inout [Double], emptyRanks: [Bool]?,
                                     fromEnds: [LayeredSegmentEnd], toEnds: [LayeredSegmentEnd]) {
        let free = graph.freeEnds(fromEnds: fromEnds, toEnds: toEnds, workspace: workspace)
        // The graph moves into each step and back, so that it is never copied.
        let alignment = LayeredFlatLabelAlignment(graph: consume graph, nodes: nodes, free: free, options: options, emptyRanks: emptyRanks)
        alignment.align(&across, workspace: workspace)
        graph = (consume alignment).graph
        var settling = LayeredFlatEndSettling(graph: consume graph, nodes: nodes, across: across, fromEnds: fromEnds, toEnds: toEnds,
                                              free: free, emptyRanks: emptyRanks, workspace: workspace)
        settling.settle()
        graph = (consume settling).finished()
        workspace.recycle(consume free)
        var snapping = LayeredFlatSnapping(graph: consume graph, options: options, emptyRanks: emptyRanks, workspace: workspace)
        snapping.snap(&across)
        graph = (consume snapping).finished()
        for edgeIndex in edges.indices where !isDirect[edgeIndex] {
            let upperOffset = graph.segmentFromOffset[firstSegment[edgeIndex]]
            let lowerOffset = graph.segmentToOffset[lastSegment[edgeIndex]]
            edges[edgeIndex].tailOffset = edges[edgeIndex].isReversed ? lowerOffset : upperOffset
            edges[edgeIndex].headOffset = edges[edgeIndex].isReversed ? upperOffset : lowerOffset
        }
    }

    /// Every edge cut where it passes a rank that holds something, each piece crossing one gap; an edge that keeps a
    /// bend to stay clear of its twin, or has a bend left out in a rank of labels, is drawn through its bends as it is.
    private func cutPieces(graph: LayeredFlatGraph, across: [Double], emptyRanks: [Bool]?, isOnLine: [Bool]) -> (LayeredEdgePieces, [Int]) {
        // Each piece crosses one gap or more: no more pieces than segments.
        var pieces = LayeredEdgePieces(capacity: graph.segmentCount, workspace: workspace)
        var pieceStart = workspace.integers(count: edges.count + 1, repeating: 0)
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
    /// Empty lists from `workspace`, with room for `count` pieces where the cutting fills them.
    init(capacity count: Int, workspace: LayeredFlatWorkspace) {
        from = workspace.emptyNumbers(capacity: count)
        to = workspace.emptyNumbers(capacity: count)
        rank = workspace.emptyIntegers(capacity: count)
        lower = workspace.emptyIntegers(capacity: count)
    }

    mutating func append(from: Double, to: Double, rank: Int, lower: Int) {
        self.from.append(from)
        self.to.append(to)
        self.rank.append(rank)
        self.lower.append(lower)
    }
}
