/**
 * File: LayeredFlatInitialOrder.swift
 * -----------------------------------
 * Layer: Core
 * Description: The order Pele's layered layout starts its sweeps from: depth first from the top, keys, pins and hints.
 *
 * Authors: Bahey Shalash
 * Version: 0.3
 * Date: 23/11/2026
 */

extension LayeredFlatLayout {
    /// Depth first from the top so that subtrees start out contiguous; then each rank whose vertices all have a key
    /// sorted by it, the pinned nodes put first or last, and a first or last rank of ports that all have a hint sorted by
    /// it and kept so (layout/layered.ts).
    func orderInitially(_ graph: inout LayeredFlatGraph) {
        depthFirstOrder(&graph)
        // The keys are read through local copies, so that no closure holds the whole layout.
        let keys = vertexKey
        let nodes = nodes
        // One list holds the rank being sorted and one the merge sort's spare, for every rank.
        var layer = workspace.emptyIntegers(capacity: 0)
        var spare = workspace.emptyIntegers(capacity: 0)
        for rank in 0...graph.maximumRank {
            _ = Self.sortRank(&graph, rank: rank, layer: &layer, spare: &spare) { vertex in keys[vertex] }
        }
        if nodes.contains(where: { node in node.pin != 0 }) {
            for rank in 0...graph.maximumRank {
                layer.removeAll(keepingCapacity: true)
                layer.append(contentsOf: graph.order[graph.rankStart[rank]..<graph.rankStart[rank + 1]])
                layer.sortStably(spare: &spare) { first, second in
                    Double(Self.pin(of: first, nodes: nodes) - Self.pin(of: second, nodes: nodes)) < 0
                }
                graph.order.replaceSubrange(graph.rankStart[rank]..<graph.rankStart[rank + 1], with: layer)
            }
        }
        // Preserve port order to avoid crossings outside the group.
        for rank in [0, graph.maximumRank] {
            if Self.sortRank(&graph, rank: rank, layer: &layer, spare: &spare, by: { vertex in Self.portHint(of: vertex, nodes: nodes) }) {
                graph.isRankFixed[rank] = true
            }
        }
        workspace.recycle(consume layer)
        workspace.recycle(consume spare)
        graph.settlePositions()
    }

    private static func pin(of vertex: Int, nodes: [LayeredFlatNode]) -> Int { vertex < nodes.count ? nodes[vertex].pin : 0 }

    private static func portHint(of vertex: Int, nodes: [LayeredFlatNode]) -> Double {
        vertex < nodes.count && nodes[vertex].kind.isPort ? nodes[vertex].portHint : .nan
    }

    private func depthFirstOrder(_ graph: inout LayeredFlatGraph) {
        let vertexCount = graph.vertexCount
        var byRank = workspace.integers(count: vertexCount, repeating: 0)
        var fill = workspace.emptyIntegers(capacity: graph.maximumRank + 1)
        fill.append(contentsOf: graph.rankStart[0...graph.maximumRank])
        for vertex in 0..<vertexCount {
            byRank[fill[graph.vertexRank[vertex]]] = vertex
            fill[graph.vertexRank[vertex]] += 1
        }
        for rank in 0...graph.maximumRank { fill[rank] = graph.rankStart[rank] }
        var visited = workspace.flags(count: vertexCount, repeating: false)
        var stack = workspace.emptyIntegers(capacity: vertexCount)
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
        workspace.recycle(consume byRank)
        workspace.recycle(consume fill)
        workspace.recycle(consume visited)
        workspace.recycle(consume stack)
    }

    /// Sorts a rank by `key` when it has two vertices or more and every one has a key, through `layer` and `spare`;
    /// whether it did.
    private static func sortRank(_ graph: inout LayeredFlatGraph, rank: Int, layer: inout [Int], spare: inout [Int],
                                 by key: (Int) -> Double) -> Bool {
        let start = graph.rankStart[rank]
        let end = graph.rankStart[rank + 1]
        if end - start < 2 { return false }
        for index in start..<end where key(graph.order[index]).isNaN { return false }
        layer.removeAll(keepingCapacity: true)
        layer.append(contentsOf: graph.order[start..<end])
        layer.sortStably(spare: &spare) { first, second in key(first) - key(second) < 0 }
        graph.order.replaceSubrange(start..<end, with: layer)
        return true
    }
}
