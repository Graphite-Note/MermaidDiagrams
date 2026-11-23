/**
 * File: LayeredFlatGraph.swift
 * ----------------------------
 * Layer: Core
 * Description: The graph Pele's layered layout orders and positions: every edge cut into rank-to-rank segments.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 23/11/2026
 */

/// The graph that gets ordered and positioned (Pele's `Graph` in layout/layered.ts): the nodes first, then the bends and
/// labels of the edges that pass ranks, every edge cut into segments from one rank to the next, and each rank's order.
struct LayeredFlatGraph {
    /// Nodes and bends.
    let vertexCount: Int
    /// The nodes of the graph, numbered first.
    let nodeCount: Int
    let maximumRank: Int
    let vertexWidth: [Double]
    let vertexKind: [LayeredVertexKind]
    let vertexRank: [Int]
    let segmentFrom: [Int]
    let segmentTo: [Int]
    /// Where each segment meets its upper and its lower vertex, across from its middle.
    var segmentFromOffset: [Double]
    var segmentToOffset: [Double]
    let successorStart: [Int]
    var successorSegments: [Int]
    let predecessorStart: [Int]
    var predecessorSegments: [Int]
    let rankStart: [Int]
    var order: [Int]
    var position: [Int]
    let hasOffsets: Bool
    /// Ranks whose order stays as it is.
    var isRankFixed: [Bool]
    /// The innermost group of each vertex, -1 for none; nil when the graph keeps no groups together.
    let vertexGroup: [Int]?
    let parentOfGroup: [Int]

    var segmentCount: Int { segmentFrom.count }

    /// Each vertex's segments down (`successors`) and up, as runs of segment indices.
    static func adjacency(vertexCount: Int, segmentFrom: [Int], segmentTo: [Int])
        -> (successorStart: [Int], successorSegments: [Int], predecessorStart: [Int], predecessorSegments: [Int]) {
        var successorStart = [Int](repeating: 0, count: vertexCount + 1)
        var predecessorStart = [Int](repeating: 0, count: vertexCount + 1)
        for segment in segmentFrom.indices {
            successorStart[segmentFrom[segment] + 1] += 1
            predecessorStart[segmentTo[segment] + 1] += 1
        }
        for vertex in 0..<vertexCount {
            successorStart[vertex + 1] += successorStart[vertex]
            predecessorStart[vertex + 1] += predecessorStart[vertex]
        }
        var successorSegments = [Int](repeating: 0, count: segmentFrom.count)
        var predecessorSegments = [Int](repeating: 0, count: segmentFrom.count)
        var successorFill = Array(successorStart[0..<vertexCount])
        var predecessorFill = Array(predecessorStart[0..<vertexCount])
        for segment in segmentFrom.indices {
            successorSegments[successorFill[segmentFrom[segment]]] = segment
            successorFill[segmentFrom[segment]] += 1
            predecessorSegments[predecessorFill[segmentTo[segment]]] = segment
            predecessorFill[segmentTo[segment]] += 1
        }
        return (successorStart, successorSegments, predecessorStart, predecessorSegments)
    }

    /// Where each rank's vertices start in `order`, by rank, with the end of the last rank after it.
    static func rankStarts(vertexRank: [Int], maximumRank: Int) -> [Int] {
        var rankStart = [Int](repeating: 0, count: maximumRank + 2)
        for rank in vertexRank { rankStart[rank + 1] += 1 }
        for rank in 0...maximumRank { rankStart[rank + 1] += rankStart[rank] }
        return rankStart
    }

    /// Sets every vertex's position in its rank from `order`.
    mutating func settlePositions() {
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
    func followed(_ segment: Int, isUpward: Bool, emptyRanks: [Bool]?) -> Int {
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
