/**
 * File: LayeredFlatCompaction.swift
 * ---------------------------------
 * Layer: Core
 * Description: Compacts the blocks of one of Brandes and Köpf's alignments and balances the four (layered.ts position).
 *
 * Authors: Bahey Shalash
 * Version: 0.2
 * Date: 23/11/2026
 */

/// The blocks of one alignment as a graph: an edge from each block to the next in every rank, as wide as the room the
/// two vertices need, and each block's edges out.
private struct LayeredBlockGraph {
    var edgeTo: [Int] = []
    var edgeWidth: [Double] = []
    var remainingIn: [Int]
    var outStart: [Int]
    var outEdges: [Int]

    init(_ graph: LayeredFlatGraph, root: [Int], shift: [Double], gap: [Double], isRightward: Bool) {
        let vertexCount = graph.vertexCount
        var edgeFrom: [Int] = []
        // A rank of n vertices gives n - 1 edges: at most one edge per vertex.
        edgeFrom.reserveCapacity(vertexCount)
        edgeTo.reserveCapacity(vertexCount)
        edgeWidth.reserveCapacity(vertexCount)
        remainingIn = [Int](repeating: 0, count: vertexCount)
        outStart = [Int](repeating: 0, count: vertexCount + 1)
        for rank in 0...graph.maximumRank {
            let end = graph.rankStart[rank + 1]
            for index in (graph.rankStart[rank] + 1)..<max(graph.rankStart[rank] + 1, end) {
                let first = isRightward ? graph.order[index] : graph.order[index - 1]
                let second = isRightward ? graph.order[index - 1] : graph.order[index]
                let separation = gap[first] + gap[second]
                edgeFrom.append(root[first])
                edgeTo.append(root[second])
                edgeWidth.append(isRightward ? separation - shift[first] + shift[second] : separation + shift[first] - shift[second])
                remainingIn[root[second]] += 1
                outStart[root[first] + 1] += 1
            }
        }
        for vertex in 0..<vertexCount { outStart[vertex + 1] += outStart[vertex] }
        var fill = Array(outStart[0..<vertexCount])
        outEdges = [Int](repeating: 0, count: edgeFrom.count)
        for edge in edgeFrom.indices {
            outEdges[fill[edgeFrom[edge]]] = edge
            fill[edgeFrom[edge]] += 1
        }
    }
}

extension LayeredFlatPositioning {
    /// The positions of one alignment: its block graph laid out longest path first, then each block pulled towards
    /// its successors.
    static func compacted(_ graph: LayeredFlatGraph, root: [Int], shift: [Double], gap: [Double], isRightward: Bool) -> [Double] {
        var blocks = LayeredBlockGraph(graph, root: root, shift: shift, gap: gap, isRightward: isRightward)
        var across = [Double](repeating: 0, count: graph.vertexCount)
        var topological = (0..<graph.vertexCount).filter { vertex in root[vertex] == vertex && blocks.remainingIn[vertex] == 0 }
        topological.reserveCapacity(graph.vertexCount)
        var queueIndex = 0
        while queueIndex < topological.count {
            let block = topological[queueIndex]
            queueIndex += 1
            for position in blocks.outStart[block]..<blocks.outStart[block + 1] {
                let edge = blocks.outEdges[position]
                let next = blocks.edgeTo[edge]
                if across[block] + blocks.edgeWidth[edge] > across[next] { across[next] = across[block] + blocks.edgeWidth[edge] }
                blocks.remainingIn[next] -= 1
                if blocks.remainingIn[next] == 0 { topological.append(next) }
            }
        }
        for block in topological.reversed() {
            var least = Double.infinity
            for position in blocks.outStart[block]..<blocks.outStart[block + 1] {
                let edge = blocks.outEdges[position]
                least = min(least, across[blocks.edgeTo[edge]] - blocks.edgeWidth[edge])
            }
            if least != .infinity && least > across[block] { across[block] = least }
        }
        return (0..<graph.vertexCount).map { vertex in (isRightward ? -across[root[vertex]] : across[root[vertex]]) + shift[vertex] }
    }

    /// The four layouts moved onto the narrowest (the leftward ones by their left edges, the rightward by their right),
    /// each vertex at the mean of its middle two positions.
    static func balanced(_ results: [[Double]], widths: [Double]) -> [Double] {
        var results = results
        var narrowest = 0
        var bestWidth = Double.infinity
        var lows: [Double] = []
        var highs: [Double] = []
        for layout in results {
            var low = Double.infinity
            var high = -Double.infinity
            for vertex in layout.indices {
                low = min(low, layout[vertex] - widths[vertex] / 2)
                high = max(high, layout[vertex] + widths[vertex] / 2)
            }
            lows.append(low)
            highs.append(high)
            if high - low < bestWidth {
                bestWidth = high - low
                narrowest = lows.count - 1
            }
        }
        for variant in 0..<4 {
            let delta = variant & 1 == 0 ? lows[narrowest] - lows[variant] : highs[narrowest] - highs[variant]
            if delta != 0 { results[variant] = results[variant].map { position in position + delta } }
        }
        return results[0].indices.map { vertex in
            let sorted = [results[0][vertex], results[1][vertex], results[2][vertex], results[3][vertex]].sorted()
            return (sorted[1] + sorted[2]) / 2
        }
    }
}
