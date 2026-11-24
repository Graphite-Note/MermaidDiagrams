/**
 * File: LayeredFlatGraph.swift
 * ----------------------------
 * Layer: Core
 * Description: The graph Pele's layered layout orders and positions: every edge cut into rank-to-rank segments.
 *
 * Authors: Bahey Shalash
 * Version: 0.3
 * Date: 24/11/2026
 */

/// The graph that gets ordered and positioned (Pele's `Graph` in layout/layered.ts): the nodes first, then the bends and
/// labels of the edges that pass ranks, every edge cut into segments from one rank to the next, and each rank's order.
struct LayeredFlatGraph {
    /// Nodes and bends.
    let vertexCount: Int
    /// The nodes of the graph, numbered first.
    let nodeCount: Int
    let maximumRank: Int
    let segmentCount: Int
    let vertexWidth: ScratchSpan<Double>
    let vertexKind: ScratchSpan<LayeredVertexKind>
    let vertexRank: ScratchSpan<Int>
    let segmentFrom: ScratchSpan<Int>
    let segmentTo: ScratchSpan<Int>
    /// Where each segment meets its upper and its lower vertex, across from its middle.
    let segmentFromOffset: ScratchSpan<Double>
    let segmentToOffset: ScratchSpan<Double>
    let successorStart: ScratchSpan<Int>
    let successorSegments: ScratchSpan<Int>
    let predecessorStart: ScratchSpan<Int>
    let predecessorSegments: ScratchSpan<Int>
    let rankStart: ScratchSpan<Int>
    let order: ScratchSpan<Int>
    let position: ScratchSpan<Int>
    let hasOffsets: Bool
    /// Ranks whose order stays as it is.
    let isRankFixed: ScratchSpan<Bool>
    /// The innermost group of each vertex, -1 for none; nil when the graph keeps no groups together.
    let vertexGroup: ScratchSpan<Int>?
    let parentOfGroup: ScratchSpan<Int>

    /// Each vertex's segments down (`successors`) and up, as runs of segment indices.
    static func adjacency(vertexCount: Int, segmentFrom: ScratchSpan<Int>, segmentTo: ScratchSpan<Int>, arena: DiagramScratchArena)
        -> (successorStart: ScratchSpan<Int>, successorSegments: ScratchSpan<Int>, predecessorStart: ScratchSpan<Int>,
            predecessorSegments: ScratchSpan<Int>) {
        let successorStart = arena.span(count: vertexCount + 1, repeating: 0)
        let predecessorStart = arena.span(count: vertexCount + 1, repeating: 0)
        let successorSegments: ScratchSpan<Int> = arena.uninitializedSpan(count: segmentFrom.count)
        let predecessorSegments: ScratchSpan<Int> = arena.uninitializedSpan(count: segmentFrom.count)
        for segment in segmentFrom.indices {
            successorStart[segmentFrom[segment] + 1] += 1
            predecessorStart[segmentTo[segment] + 1] += 1
        }
        for vertex in 0..<vertexCount {
            successorStart[vertex + 1] += successorStart[vertex]
            predecessorStart[vertex + 1] += predecessorStart[vertex]
        }
        let mark = arena.mark()
        defer { arena.release(to: mark) }
        let successorFill = arena.copy(of: successorStart.part(0..<vertexCount))
        let predecessorFill = arena.copy(of: predecessorStart.part(0..<vertexCount))
        for segment in segmentFrom.indices {
            successorSegments[successorFill[segmentFrom[segment]]] = segment
            successorFill[segmentFrom[segment]] += 1
            predecessorSegments[predecessorFill[segmentTo[segment]]] = segment
            predecessorFill[segmentTo[segment]] += 1
        }
        return (successorStart, successorSegments, predecessorStart, predecessorSegments)
    }

    /// Where each rank's vertices start in `order`, by rank, with the end of the last rank after it.
    static func rankStarts(vertexRank: ScratchSpan<Int>, maximumRank: Int, arena: DiagramScratchArena) -> ScratchSpan<Int> {
        let rankStart = arena.span(count: maximumRank + 2, repeating: 0)
        for rank in vertexRank { rankStart[rank + 1] += 1 }
        for rank in 0...maximumRank { rankStart[rank + 1] += rankStart[rank] }
        return rankStart
    }

    /// Sets every vertex's position in its rank from `order`.
    func settlePositions() {
        for rank in 0...maximumRank {
            let start = rankStart[rank]
            for index in start..<rankStart[rank + 1] { position[order[index]] = index - start }
        }
    }

    /// Half the room a vertex takes across the flow with its share of the gap beside it: a port or bend needs no more
    /// than an edge (Pele's `halfRoom`).
    func halfRoom(of vertex: Int, options: LayeredFlatOptions) -> Double {
        vertexWidth[vertex] / 2 + (vertexKind[vertex] == .node ? options.nodeSeparation : options.edgeSeparation) / 2
    }

    /// The segment of an edge that reaches the next point held in place on the way up from `segment` (`isUpward`) or
    /// down: past the bends in ranks that hold nothing else (Pele's `follow`).
    func followed(_ segment: Int, isUpward: Bool, emptyRanks: ScratchSpan<Bool>?) -> Int {
        guard let emptyRanks else { return segment }
        var segment = segment
        for _ in 0..<100_000 {
            let vertex = isUpward ? segmentFrom[segment] : segmentTo[segment]
            if vertexKind[vertex] != .bend || !emptyRanks[vertexRank[vertex]] { break }
            segment = isUpward ? predecessorSegments[predecessorStart[vertex]] : successorSegments[successorStart[vertex]]
        }
        return segment
    }
}
