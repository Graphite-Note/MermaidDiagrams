/**
 * File: LayeredArenaRankingCheck.swift
 * ------------------------------------
 * Layer: Profiling (redesign prototype)
 * Description: Checks the arena ranking against LayeredFlatRanking on the captured graphs and times both.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 24/11/2026
 */

import Foundation

public enum LayeredArenaRankingCheck {
    struct Prepared {
        var nodes: [LayeredFlatNode]
        var edges: [LayeredFlatEdge]
        var step: Int
    }

    static func prepared() -> [Prepared] {
        LayeredStageReplay.flat.map { (graph, _, _) in
            let nodes = graph.nodeSizes.map { size in LayeredFlatNode(width: Double(size.across), height: Double(size.along)) }
            let edges = graph.edges.map { edge in
                LayeredFlatEdge(tail: edge.source, head: edge.target, minimumLength: edge.minimumRankSpan,
                                labelWidth: Double(edge.labelSize?.across ?? 0), labelHeight: Double(edge.labelSize?.along ?? 0))
            }
            var step = 1
            if edges.contains(where: { edge in edge.labelWidth > 0 }) { step = 2 } else {
                let pairs = edges.map { edge in min(edge.tail, edge.head) * nodes.count + max(edge.tail, edge.head) }.sorted()
                for index in pairs.indices.dropFirst() where pairs[index] == pairs[index - 1] { step = 2 }
            }
            return Prepared(nodes: nodes, edges: edges, step: step)
        }
    }

    @inline(never) static func arenaRanks(_ graph: Prepared, arena: LayeredScratchArena) -> (ScratchSpan<Int32>, LayeredArenaEdges) {
        let nodeCount = graph.nodes.count
        let kinds = arena.span(nodeCount, repeating: LayeredVertexKind.node)
        for node in 0..<nodeCount { kinds[node] = graph.nodes[node].kind }
        let edgeCount = graph.edges.count
        let edges = LayeredArenaEdges(count: edgeCount, tail: arena.span(edgeCount, repeating: 0), head: arena.span(edgeCount, repeating: 0),
                                      minimumLength: arena.span(edgeCount, repeating: 0), isReversed: arena.span(edgeCount, repeating: false))
        for index in 0..<edgeCount {
            edges.tail[index] = Int32(graph.edges[index].tail)
            edges.head[index] = Int32(graph.edges[index].head)
            edges.minimumLength[index] = Int32(graph.edges[index].minimumLength)
        }
        let ranks = LayeredArenaRanking.orientAndRank(nodeCount: nodeCount, kinds: kinds, edges: edges, step: Int32(graph.step), arena: arena)
        return (ranks, edges)
    }

    @inline(never) static func pooledRanks(_ graph: Prepared, workspace: LayeredFlatWorkspace) -> ([LayeredFlatNode], [LayeredFlatEdge]) {
        var nodes = graph.nodes
        var edges = graph.edges
        LayeredFlatRanking.orient(nodes: nodes, edges: &edges, workspace: workspace)
        LayeredFlatRanking.rank(nodes: &nodes, edges: edges, step: graph.step, workspace: workspace)
        return (nodes, edges)
    }

    @inline(never) static func copiesOnly(_ graph: Prepared) -> ([LayeredFlatNode], [LayeredFlatEdge]) {
        var nodes = graph.nodes
        var edges = graph.edges
        if !edges.isEmpty { edges[0].isReversed = false }
        if !nodes.isEmpty { nodes[0].rank = 0 }
        return (nodes, edges)
    }

    /// Returns a report: how many graphs agree, and the time a graph of each way.
    public static func run(rounds: Int) -> String {
        let graphs = prepared().filter { graph in graph.nodes.count >= 2 }
        let arena = LayeredScratchArena()
        let workspace = LayeredFlatWorkspace()
        var disagreeing = 0
        for graph in graphs {
            let (nodes, edges) = pooledRanks(graph, workspace: workspace)
            let (ranks, arenaEdges) = arenaRanks(graph, arena: arena)
            let ranksAgree = nodes.indices.allSatisfy { node in nodes[node].rank == Int(ranks[node]) }
            let reversalsAgree = edges.indices.allSatisfy { edge in edges[edge].isReversed == arenaEdges.isReversed[edge] }
            if !ranksAgree || !reversalsAgree { disagreeing += 1 }
            arena.reset()
        }
        func time(_ body: () -> Void) -> Double {
            let start = clock_gettime_nsec_np(CLOCK_UPTIME_RAW)
            for _ in 0..<rounds { body() }
            return Double(clock_gettime_nsec_np(CLOCK_UPTIME_RAW) - start) / 1_000 / Double(rounds * max(graphs.count, 1))
        }
        var sink = 0
        var pooled = [Double](), copies = [Double](), arenaTimes = [Double](), freshPooled = [Double]()
        for _ in 0..<5 {
            pooled.append(time { for graph in graphs { sink &+= pooledRanks(graph, workspace: workspace).0.count } })
            freshPooled.append(time { for graph in graphs { sink &+= pooledRanks(graph, workspace: LayeredFlatWorkspace()).0.count } })
            copies.append(time { for graph in graphs { sink &+= copiesOnly(graph).0.count } })
            arenaTimes.append(time { for graph in graphs { sink &+= Int(arenaRanks(graph, arena: arena).0.count); arena.reset() } })
        }
        func median(_ values: [Double]) -> String { String(format: "%.3f", values.sorted()[values.count / 2]) }
        let nodeTotal = graphs.reduce(0) { $0 + $1.nodes.count }, edgeTotal = graphs.reduce(0) { $0 + $1.edges.count }
        return "\(graphs.count) graphs of 2 nodes or more (\(nodeTotal) nodes, \(edgeTotal) edges), \(disagreeing) disagreeing; µs a graph, median of 5: "
            + "pooled, workspace kept \(median(pooled)) (of it copying the inputs \(median(copies))), pooled, new workspace \(median(freshPooled)), arena \(median(arenaTimes)) [\(sink & 1)]"
    }
}
