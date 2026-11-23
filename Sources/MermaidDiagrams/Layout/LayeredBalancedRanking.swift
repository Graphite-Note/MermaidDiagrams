/**
 * File: LayeredBalancedRanking.swift
 * ----------------------------------
 * Layer: Core
 * Description: Pele's own orientation and ranking of a layered graph (`orient` and `rank` of its `layered.ts`), which its
 *              lane layout ranks on: cycles broken in declaration order, longest paths, then nodes moved toward the side
 *              with more edges.
 *
 * Authors: Bahey Shalash
 * Version: 0.2
 * Date: 23/11/2026
 */

/// The ranking the lane layout uses; the layered layout itself ranks with `LayeredFlatRanking`.
enum LayeredRanking {
    /// The edges to turn around, as Pele's `orient` finds them: a depth-first walk from every node in turn, in the order of
    /// the nodes, turns each edge that reaches a node still on its path. The walk does not start
    /// from the nodes no edge enters first.
    static func declarationOrderCycleClosingEdges(nodeCount: Int, edges: [(source: Int, target: Int)]) -> [Bool] {
        var outgoingEdgeIndices = [[Int]](repeating: [], count: nodeCount)
        for (edgeIndex, edge) in edges.enumerated() { outgoingEdgeIndices[edge.source].append(edgeIndex) }
        var isReversed = [Bool](repeating: false, count: edges.count)
        var visitState = [UInt8](repeating: 0, count: nodeCount)
        var stack: [(node: Int, nextOutgoingPosition: Int)] = []
        for root in 0..<nodeCount where visitState[root] == 0 {
            visitState[root] = 1
            stack.append((root, 0))
            while let top = stack.last {
                let outgoing = outgoingEdgeIndices[top.node]
                guard top.nextOutgoingPosition < outgoing.count else {
                    visitState[top.node] = 2
                    stack.removeLast()
                    continue
                }
                stack[stack.count - 1].nextOutgoingPosition += 1
                let edgeIndex = outgoing[top.nextOutgoingPosition]
                let target = edges[edgeIndex].target
                if visitState[target] == 1 {
                    isReversed[edgeIndex] = true
                } else if visitState[target] == 0 {
                    visitState[target] = 1
                    stack.append((target, 0))
                }
            }
        }
        return isReversed
    }

    /// Ranks as Pele's `rank` gives them, over oriented `(source, target, length)` edges: each node as low as its longest
    /// path from a node no edge enters, then up to eight passes, in reverse topological order, that move a node with more
    /// edges out than in as far down as its successors allow and one with more in than out as far up as its predecessors
    /// allow, so that a loosely attached node sits next to its neighbours. The smallest rank is 0.
    static func balancedRanks(nodeCount: Int, orientedEdges: [(source: Int, target: Int, length: Int)]) -> [Int] {
        var incoming = [[Int]](repeating: [], count: nodeCount)
        var outgoing = [[Int]](repeating: [], count: nodeCount)
        for (edgeIndex, edge) in orientedEdges.enumerated() {
            outgoing[edge.source].append(edgeIndex)
            incoming[edge.target].append(edgeIndex)
        }
        var remainingIncoming = incoming.map(\.count)
        var topologicalOrder = (0..<nodeCount).filter { node in remainingIncoming[node] == 0 }
        var rank = [Int](repeating: 0, count: nodeCount)
        var position = 0
        while position < topologicalOrder.count {
            let node = topologicalOrder[position]
            position += 1
            for edgeIndex in outgoing[node] {
                let edge = orientedEdges[edgeIndex]
                rank[edge.target] = max(rank[edge.target], rank[node] + edge.length)
                remainingIncoming[edge.target] -= 1
                if remainingIncoming[edge.target] == 0 { topologicalOrder.append(edge.target) }
            }
        }
        balance(&rank, order: topologicalOrder, incoming: incoming, outgoing: outgoing, edges: orientedEdges)
        let lowest = rank.min() ?? 0
        return rank.map { nodeRank in nodeRank - lowest }
    }

    /// Pele's passes that move each node toward the side that has more edges, until a pass moves none.
    private static func balance(_ rank: inout [Int], order: [Int], incoming: [[Int]], outgoing: [[Int]],
                                edges: [(source: Int, target: Int, length: Int)]) {
        for _ in 0..<8 {
            var changed = false
            for node in order.reversed() {
                let inCount = incoming[node].count
                let outCount = outgoing[node].count
                guard inCount > 0 || outCount > 0 else { continue }
                var next = rank[node]
                if outCount > inCount, let highest = outgoing[node].map({ edgeIndex in rank[edges[edgeIndex].target] - edges[edgeIndex].length }).min() {
                    next = highest
                } else if inCount > outCount, let lowest = incoming[node].map({ edgeIndex in rank[edges[edgeIndex].source] + edges[edgeIndex].length }).max() {
                    next = lowest
                }
                if next != rank[node] {
                    rank[node] = next
                    changed = true
                }
            }
            if !changed { break }
        }
    }
}
