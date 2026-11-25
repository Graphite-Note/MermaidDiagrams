/**
 * File: LayeredFlatInitialOrder.swift
 * -----------------------------------
 * Layer: Core
 * Description: The order Pele's layered layout starts its sweeps from: depth first from the top, keys, pins and hints.
 *
 * Authors: Bahey Shalash
 * Version: 0.5
 * Date: 25/11/2026
 */

extension LayeredFlatLayout {
    /// Depth first from the top so that subtrees start out contiguous; then each rank whose vertices all have a key
    /// sorted by it, the pinned nodes put first or last, and a first or last rank of ports that all have a hint sorted by
    /// it and kept so (layout/layered.ts).
    func orderInitially(_ graph: LayeredFlatGraph) {
        let mark = arena.mark()
        defer { arena.release(to: mark) }
        depthFirstOrder(graph)
        let keys = vertexKey
        let nodes = nodes
        for rank in 0...graph.maximumRank {
            _ = Self.sortRank(graph, rank: rank, arena: arena) { vertex in keys[vertex] }
        }
        if nodes.contains(where: { node in node.pin != 0 }) {
            for rank in 0...graph.maximumRank {
                graph.order.sortStably(graph.rankStart[rank]..<graph.rankStart[rank + 1], in: arena) { first, second in
                    Double(Self.pin(of: first, nodes: nodes) - Self.pin(of: second, nodes: nodes)) < 0
                }
            }
        }
        // Preserve port order to avoid crossings outside the group.
        for isFirstRank in [true, false] {
            let rank = isFirstRank ? 0 : graph.maximumRank
            if Self.sortRank(graph, rank: rank, arena: arena, by: { vertex in Self.portHint(of: vertex, nodes: nodes) }) {
                graph.isRankFixed[rank] = true
            }
        }
        graph.settlePositions()
    }

    private static func pin(of vertex: Int, nodes: ScratchSpan<LayeredFlatNode>) -> Int { vertex < nodes.count ? nodes[vertex].pin : 0 }

    private static func portHint(of vertex: Int, nodes: ScratchSpan<LayeredFlatNode>) -> Double {
        vertex < nodes.count && nodes[vertex].kind.isPort ? nodes[vertex].portHint : .nan
    }

    private func depthFirstOrder(_ graph: LayeredFlatGraph) {
        let vertexCount = graph.vertexCount
        // The graph's spans read once: they live in the arena, where every store below could be to them as far as the
        // compiler knows.
        let vertexRank = graph.vertexRank, rankStart = graph.rankStart, order = graph.order
        let successorStart = graph.successorStart, successorSegments = graph.successorSegments, segmentTo = graph.segmentTo
        let byRank: ScratchSpan<Int> = arena.uninitializedSpan(count: vertexCount)
        let fill = arena.copy(of: rankStart.part(0..<(graph.maximumRank + 1)))
        for vertex in 0..<vertexCount {
            byRank[fill[vertexRank[vertex]]] = vertex
            fill[vertexRank[vertex]] += 1
        }
        for rank in 0...graph.maximumRank { fill[rank] = rankStart[rank] }
        let visited = arena.span(count: vertexCount, repeating: false)
        var stack = arena.list(capacity: vertexCount, of: Int.self)
        for start in byRank where !visited[start] {
            stack.append(start)
            while let vertex = stack.popLast() {
                if visited[vertex] { continue }
                visited[vertex] = true
                order[fill[vertexRank[vertex]]] = vertex
                fill[vertexRank[vertex]] += 1
                var position = successorStart[vertex + 1] - 1
                while position >= successorStart[vertex] {
                    let next = segmentTo[successorSegments[position]]
                    if !visited[next] { stack.append(next) }
                    position -= 1
                }
            }
        }
    }

    /// Sorts a rank by `key` when it has two vertices or more and every one has a key; whether it did.
    private static func sortRank(_ graph: LayeredFlatGraph, rank: Int, arena: DiagramScratchArena, by key: (Int) -> Double) -> Bool {
        let start = graph.rankStart[rank]
        let end = graph.rankStart[rank + 1]
        if end - start < 2 { return false }
        for index in start..<end where key(graph.order[index]).isNaN { return false }
        graph.order.sortStably(start..<end, in: arena) { first, second in key(first) - key(second) < 0 }
        return true
    }
}
