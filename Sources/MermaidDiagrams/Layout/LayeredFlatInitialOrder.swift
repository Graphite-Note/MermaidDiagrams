/**
 * File: LayeredFlatInitialOrder.swift
 * -----------------------------------
 * Layer: Core
 * Description: The order Pele's layered layout starts its sweeps from: depth first from the top, keys, pins and hints.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 23/11/2026
 */

extension LayeredFlatLayout {
    /// Depth first from the top so that subtrees start out contiguous; then each rank whose vertices all have a key
    /// sorted by it, the pinned nodes put first or last, and a first or last rank of ports that all have a hint sorted by
    /// it and kept so (layout/layered.ts).
    func orderInitially(_ graph: inout LayeredFlatGraph) {
        depthFirstOrder(&graph)
        for rank in 0...graph.maximumRank { _ = sortRank(&graph, rank: rank) { vertex in vertexKey[vertex] } }
        if nodes.contains(where: { node in node.pin != 0 }) {
            for rank in 0...graph.maximumRank {
                var layer = Array(graph.order[graph.rankStart[rank]..<graph.rankStart[rank + 1]])
                layer.sortStably { first, second in Double(pin(of: first) - pin(of: second)) }
                graph.order.replaceSubrange(graph.rankStart[rank]..<graph.rankStart[rank + 1], with: layer)
            }
        }
        // Preserve port order to avoid crossings outside the group.
        for rank in [0, graph.maximumRank] {
            if sortRank(&graph, rank: rank, by: portHint(of:)) { graph.isRankFixed[rank] = true }
        }
        graph.settlePositions()
    }

    func pin(of vertex: Int) -> Int { vertex < nodes.count ? nodes[vertex].pin : 0 }

    private func portHint(of vertex: Int) -> Double {
        vertex < nodes.count && nodes[vertex].kind.isPort ? nodes[vertex].portHint : .nan
    }

    private func depthFirstOrder(_ graph: inout LayeredFlatGraph) {
        let vertexCount = graph.vertexCount
        var byRank = [Int](repeating: 0, count: vertexCount)
        var fill = Array(graph.rankStart[0...graph.maximumRank])
        for vertex in 0..<vertexCount {
            byRank[fill[graph.vertexRank[vertex]]] = vertex
            fill[graph.vertexRank[vertex]] += 1
        }
        fill = Array(graph.rankStart[0...graph.maximumRank])
        var visited = [Bool](repeating: false, count: vertexCount)
        var stack: [Int] = []
        for start in byRank where !visited[start] {
            stack.append(start)
            while let vertex = stack.popLast() {
                if visited[vertex] { continue }
                visited[vertex] = true
                graph.order[fill[graph.vertexRank[vertex]]] = vertex
                fill[graph.vertexRank[vertex]] += 1
                var position = graph.successorStart[vertex + 1] - 1
                while position >= graph.successorStart[vertex] {
                    let next = graph.segmentTo[graph.successorSegments[position]]
                    if !visited[next] { stack.append(next) }
                    position -= 1
                }
            }
        }
    }

    /// Sorts a rank by `key` when it has two vertices or more and every one has a key; whether it did.
    private func sortRank(_ graph: inout LayeredFlatGraph, rank: Int, by key: (Int) -> Double) -> Bool {
        let start = graph.rankStart[rank]
        let end = graph.rankStart[rank + 1]
        if end - start < 2 { return false }
        for index in start..<end where key(graph.order[index]).isNaN { return false }
        var layer = Array(graph.order[start..<end])
        layer.sortStably { first, second in key(first) - key(second) }
        graph.order.replaceSubrange(start..<end, with: layer)
        return true
    }
}
