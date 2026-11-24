/**
 * File: LayeredFlatRouting.swift
 * ------------------------------
 * Layer: Core
 * Description: The steps of Pele's layered layout after ordering: positions, ends, straightening and the edges' pieces.
 *
 * Authors: Bahey Shalash
 * Version: 0.4
 * Date: 24/11/2026
 */

extension LayeredFlatLayout {
    /// Positions the ordered graph, spreads and settles the ends, straightens the bends, cuts the edges into the pieces
    /// that cross one gap each, sizes the gaps and writes every node's place and every edge's route.
    mutating func route(graph: LayeredFlatGraph) -> (width: Double, height: Double) {
        if let fromEnds = segmentFromEnd, let toEnds = segmentToEnd {
            graph.spreadEnds(nodes: nodes, fromEnds: fromEnds, toEnds: toEnds, arena: arena)
        }
        let across = LayeredFlatPositioning.positions(graph, options: options, arena: arena)
        let emptyRanks = graph.emptyRanks(arena: arena)
        if let fromEnds = segmentFromEnd, let toEnds = segmentToEnd {
            settleEnds(graph: graph, across: across, emptyRanks: emptyRanks, fromEnds: fromEnds, toEnds: toEnds)
        }
        graph.alignPorts(across, emptyRanks: emptyRanks, arena: arena)
        // A rank that holds nothing but bends is only there because another edge has a label or a twin: its bends move
        // onto the straight line between their edges' ends, and one that gets there is left out of the route.
        let isOnLine = arena.span(count: graph.vertexCount, repeating: false)
        if let emptyRanks, !options.runsOnTracks {
            graph.straighten(across, emptyRanks: emptyRanks, firstBend: firstBend, edgeRankSpan: edgeRankSpan,
                             separation: options.keepsTwinsApart ? 0 : options.edgeSeparation, isOnLine: isOnLine, arena: arena)
        }
        if !options.runsOnTracks {
            graph.passLabels(across, firstBend: firstBend, edgeRankSpan: edgeRankSpan, clearance: options.edgeSeparation, isOnLine: isOnLine,
                             arena: arena)
        }
        let usesPieces = options.runsOnTracks || (segmentFromEnd != nil && !options.isStraight)
        let (pieces, pieceStart) = usesPieces ? cutPieces(graph: graph, across: across, emptyRanks: emptyRanks, isOnLine: isOnLine)
            : (nil, ScratchSpan<Int>.empty)
        var bands = LayeredFlatBands(layout: self, graph: graph, across: across, emptyRanks: emptyRanks, pieces: pieces)
        bands.size(layout: self, graph: graph)
        return writePlaces(graph: graph, across: across, bands: bands, pieceStart: pieceStart, isOnLine: isOnLine)
    }

    /// Where nodes spread their ends: the labels aligned, the ends settled along their sides, the vertices snapped into
    /// line, and each edge's offsets at its nodes written back. Every step changes the graph's spans in place; each
    /// step's working lists are given back when it ends.
    private func settleEnds(graph: LayeredFlatGraph, across: ScratchSpan<Double>, emptyRanks: ScratchSpan<Bool>?,
                                     fromEnds: ScratchSpan<LayeredSegmentEnd>, toEnds: ScratchSpan<LayeredSegmentEnd>) {
        let mark = arena.mark()
        defer { arena.release(to: mark) }
        let free = graph.freeEnds(fromEnds: fromEnds, toEnds: toEnds, arena: arena)
        let alignment = LayeredFlatLabelAlignment(graph: graph, nodes: nodes, free: free, options: options, emptyRanks: emptyRanks)
        alignment.align(across, arena: arena)
        let stepMark = arena.mark()
        var settling = LayeredFlatEndSettling(graph: graph, nodes: nodes, across: across, fromEnds: fromEnds, toEnds: toEnds,
                                              free: free, emptyRanks: emptyRanks, arena: arena)
        settling.settle()
        arena.release(to: stepMark)
        let snapping = LayeredFlatSnapping(graph: graph, options: options, emptyRanks: emptyRanks, arena: arena)
        snapping.snap(across)
        for edgeIndex in edges.indices where !isDirect[edgeIndex] {
            let upperOffset = graph.segmentFromOffset[firstSegment[edgeIndex]]
            let lowerOffset = graph.segmentToOffset[lastSegment[edgeIndex]]
            edges[edgeIndex].tailOffset = edges[edgeIndex].isReversed ? lowerOffset : upperOffset
            edges[edgeIndex].headOffset = edges[edgeIndex].isReversed ? upperOffset : lowerOffset
        }
    }

    /// Every edge cut where it passes a rank that holds something, each piece crossing one gap; an edge that keeps a
    /// bend to stay clear of its twin, or has a bend left out in a rank of labels, is drawn through its bends as it is.
    private func cutPieces(graph: LayeredFlatGraph, across: ScratchSpan<Double>, emptyRanks: ScratchSpan<Bool>?,
                           isOnLine: ScratchSpan<Bool>) -> (LayeredEdgePieces, ScratchSpan<Int>) {
        // Each piece crosses one gap or more: no more pieces than segments.
        var pieces = LayeredEdgePieces(capacity: graph.segmentCount, arena: arena)
        let pieceStart = arena.span(count: edges.count + 1, repeating: 0)
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
    /// Empty lists from `arena`, with room for `count` pieces where the cutting fills them.
    init(capacity count: Int, arena: DiagramScratchArena) {
        from = arena.list(capacity: count, of: Double.self)
        to = arena.list(capacity: count, of: Double.self)
        rank = arena.list(capacity: count, of: Int.self)
        lower = arena.list(capacity: count, of: Int.self)
    }

    mutating func append(from: Double, to: Double, rank: Int, lower: Int) {
        self.from.append(from)
        self.to.append(to)
        self.rank.append(rank)
        self.lower.append(lower)
    }
}
