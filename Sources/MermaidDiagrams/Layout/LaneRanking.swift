/**
 * File: LaneRanking.swift
 * -----------------------
 * Layer: Core
 * Description: Pele's orientation and ranking of the lane layout's graph (`orient` and `rank` of its `layered.ts`) on
 *              spans of the thread's scratch arena: cycles broken in declaration order, longest paths, then nodes moved
 *              toward the side with more edges, every rank as `LayeredRanking` gives it.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 24/11/2026
 */

/// An edge the lane layout ranks on: from `source` down to `target`, at least `length` ranks long.
struct LaneOrientedEdge {
    var source: Int
    var target: Int
    var length: Int
}

/// Values grouped by node, as one list with a start per node (`starts[node]..<starts[node + 1]`), each node's in the order
/// they were listed: what `[[Int]]` per node holds, in two spans. The edges of each node of a graph, the neighbours of
/// each vertex or the vertices of each rank.
struct LaneAdjacency {
    let starts: ScratchSpan<Int>
    let members: ScratchSpan<Int>

    /// The `count` values `member` gives, grouped by the node `nodeOf` gives each, by a counting sort that keeps their order.
    @inline(__always)
    init(nodeCount: Int, count: Int, arena: DiagramScratchArena, nodeOf: (Int) -> Int, member: (Int) -> Int) {
        let starts = arena.span(count: nodeCount + 1, repeating: 0)
        for index in 0..<count { starts[nodeOf(index) + 1] += 1 }
        for node in 0..<nodeCount { starts[node + 1] += starts[node] }
        let members: ScratchSpan<Int> = arena.uninitializedSpan(count: count)
        let mark = arena.mark()
        defer { arena.release(to: mark) }
        let next = arena.copy(of: starts)
        for index in 0..<count {
            let node = nodeOf(index)
            members[next[node]] = member(index)
            next[node] += 1
        }
        self.starts = starts
        self.members = members
    }

    /// The indexes `0..<count` grouped by the node `nodeOf` gives each.
    @inline(__always)
    init(nodeCount: Int, count: Int, arena: DiagramScratchArena, nodeOf: (Int) -> Int) {
        self.init(nodeCount: nodeCount, count: count, arena: arena, nodeOf: nodeOf) { index in index }
    }

    @inline(__always)
    func count(of node: Int) -> Int { starts[node + 1] - starts[node] }

    @inline(__always)
    func range(of node: Int) -> Range<Int> { starts[node]..<starts[node + 1] }
}

/// The lane layout's ranking, as `LayeredRanking` does it, on spans.
enum LaneRanking {
    /// The edges to turn around, as Pele's `orient` finds them (`LayeredRanking.declarationOrderCycleClosingEdges`):
    /// a depth-first walk from every node in turn turns each edge that reaches a node still on its path.
    static func cycleClosingEdges(nodeCount: Int, sources: ScratchSpan<Int>, targets: ScratchSpan<Int>,
                                  arena: DiagramScratchArena) -> ScratchSpan<Bool> {
        let edgeCount = sources.count
        let outgoing = LaneAdjacency(nodeCount: nodeCount, count: edgeCount, arena: arena) { edgeIndex in sources[edgeIndex] }
        let isReversed = arena.span(count: edgeCount, repeating: false)
        let visitState = arena.span(count: nodeCount, repeating: UInt8(0))
        // A node is pushed once, when first reached, so the stack never holds more than every node.
        let stackNodes: ScratchSpan<Int> = arena.uninitializedSpan(count: nodeCount)
        let stackPositions: ScratchSpan<Int> = arena.uninitializedSpan(count: nodeCount)
        var depth = 0
        for root in 0..<nodeCount where visitState[root] == 0 {
            visitState[root] = 1
            stackNodes[0] = root
            stackPositions[0] = 0
            depth = 1
            while depth > 0 {
                let node = stackNodes[depth - 1]
                let position = stackPositions[depth - 1]
                guard position < outgoing.count(of: node) else {
                    visitState[node] = 2
                    depth -= 1
                    continue
                }
                stackPositions[depth - 1] = position + 1
                let edgeIndex = outgoing.members[outgoing.starts[node] + position]
                let target = targets[edgeIndex]
                if visitState[target] == 1 {
                    isReversed[edgeIndex] = true
                } else if visitState[target] == 0 {
                    visitState[target] = 1
                    stackNodes[depth] = target
                    stackPositions[depth] = 0
                    depth += 1
                }
            }
        }
        return isReversed
    }

    /// Ranks as Pele's `rank` gives them (`LayeredRanking.balancedRanks`): longest paths from the nodes no edge enters,
    /// then up to eight passes in reverse topological order toward the side with more edges; the smallest rank is 0.
    static func balancedRanks(nodeCount: Int, edges: ScratchSpan<LaneOrientedEdge>, arena: DiagramScratchArena) -> ScratchSpan<Int> {
        let outgoing = LaneAdjacency(nodeCount: nodeCount, count: edges.count, arena: arena) { edgeIndex in edges[edgeIndex].source }
        let incoming = LaneAdjacency(nodeCount: nodeCount, count: edges.count, arena: arena) { edgeIndex in edges[edgeIndex].target }
        let remainingIncoming: ScratchSpan<Int> = arena.uninitializedSpan(count: nodeCount)
        let order: ScratchSpan<Int> = arena.uninitializedSpan(count: nodeCount)
        var orderCount = 0
        for node in 0..<nodeCount {
            remainingIncoming[node] = incoming.count(of: node)
            if remainingIncoming[node] == 0 {
                order[orderCount] = node
                orderCount += 1
            }
        }
        let rank = arena.span(count: nodeCount, repeating: 0)
        var position = 0
        while position < orderCount {
            let node = order[position]
            position += 1
            for slot in outgoing.starts[node]..<outgoing.starts[node + 1] {
                let edge = edges[outgoing.members[slot]]
                rank[edge.target] = max(rank[edge.target], rank[node] + edge.length)
                remainingIncoming[edge.target] -= 1
                if remainingIncoming[edge.target] == 0 {
                    order[orderCount] = edge.target
                    orderCount += 1
                }
            }
        }
        balance(rank, order: order.part(0..<orderCount), incoming: incoming, outgoing: outgoing, edges: edges)
        var lowest = 0
        if nodeCount > 0 {
            lowest = rank[0]
            for node in 1..<nodeCount where rank[node] < lowest { lowest = rank[node] }
        }
        for node in 0..<nodeCount { rank[node] -= lowest }
        return rank
    }

    /// Pele's passes that move each node toward the side that has more edges, until a pass moves none.
    private static func balance(_ rank: ScratchSpan<Int>, order: ScratchSpan<Int>, incoming: LaneAdjacency, outgoing: LaneAdjacency,
                                edges: ScratchSpan<LaneOrientedEdge>) {
        for _ in 0..<8 {
            var changed = false
            for orderIndex in stride(from: order.count - 1, through: 0, by: -1) {
                let node = order[orderIndex]
                let inCount = incoming.count(of: node)
                let outCount = outgoing.count(of: node)
                guard inCount > 0 || outCount > 0 else { continue }
                var next = rank[node]
                if outCount > inCount {
                    next = Int.max
                    for slot in outgoing.starts[node]..<outgoing.starts[node + 1] {
                        let edge = edges[outgoing.members[slot]]
                        next = min(next, rank[edge.target] - edge.length)
                    }
                } else if inCount > outCount {
                    next = Int.min
                    for slot in incoming.starts[node]..<incoming.starts[node + 1] {
                        let edge = edges[incoming.members[slot]]
                        next = max(next, rank[edge.source] + edge.length)
                    }
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
