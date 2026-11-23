/**
 * File: LayeredFlatRanking.swift
 * ------------------------------
 * Layer: Core
 * Description: The first two steps of Pele's layered layout: edges that close cycles turned around, then ranks.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 23/11/2026
 */

/// Pele's `orient` and `rank` (layout/layered.ts), step for step.
enum LayeredFlatRanking {
    /// Turns around the edges that close a cycle, found by a depth-first walk from each node in declaration order, and
    /// the edges that run into a start port or out of an end port.
    static func orient(nodes: [LayeredFlatNode], edges: inout [LayeredFlatEdge]) {
        let nodeCount = nodes.count
        var start = [Int](repeating: 0, count: nodeCount + 1)
        for index in edges.indices {
            edges[index].isReversed = nodes[edges[index].head].kind == .startPort || nodes[edges[index].tail].kind == .endPort
            if !edges[index].isReversed { start[edges[index].tail + 1] += 1 }
        }
        for node in 0..<nodeCount { start[node + 1] += start[node] }
        var outgoing = [Int](repeating: 0, count: start[nodeCount])
        var fill = Array(start[0..<nodeCount])
        for index in edges.indices where !edges[index].isReversed {
            outgoing[fill[edges[index].tail]] = index
            fill[edges[index].tail] += 1
        }
        // 0 unvisited, 1 on the walk, 2 done.
        var state = [UInt8](repeating: 0, count: nodeCount)
        var cursor = Array(start[0..<nodeCount])
        var stack: [Int] = []
        for root in 0..<nodeCount where state[root] == 0 {
            stack.append(root)
            state[root] = 1
            while let node = stack.last {
                if cursor[node] < start[node + 1] {
                    let edgeIndex = outgoing[cursor[node]]
                    cursor[node] += 1
                    let head = edges[edgeIndex].head
                    if state[head] == 1 {
                        edges[edgeIndex].isReversed = true
                    } else if state[head] == 0 {
                        state[head] = 1
                        stack.append(head)
                    }
                } else {
                    state[node] = 2
                    stack.removeLast()
                }
            }
        }
    }

    /// The edges as they run after `orient`, with their lengths, and each node's edges out and in.
    private struct OrientedEdges {
        var from: [Int]
        var to: [Int]
        var length: [Int]
        var outStart: [Int]
        var outEdges: [Int]
        var inStart: [Int]
        var inEdges: [Int]

        init(nodeCount: Int, edges: [LayeredFlatEdge], step: Int) {
            from = edges.map { edge in edge.isReversed ? edge.head : edge.tail }
            to = edges.map { edge in edge.isReversed ? edge.tail : edge.head }
            length = edges.map { edge in max(1, edge.minimumLength) * step }
            outStart = [Int](repeating: 0, count: nodeCount + 1)
            inStart = [Int](repeating: 0, count: nodeCount + 1)
            for index in edges.indices {
                outStart[from[index] + 1] += 1
                inStart[to[index] + 1] += 1
            }
            for node in 0..<nodeCount {
                outStart[node + 1] += outStart[node]
                inStart[node + 1] += inStart[node]
            }
            outEdges = [Int](repeating: 0, count: edges.count)
            inEdges = [Int](repeating: 0, count: edges.count)
            var outFill = Array(outStart[0..<nodeCount])
            var inFill = Array(inStart[0..<nodeCount])
            for index in edges.indices {
                outEdges[outFill[from[index]]] = index
                outFill[from[index]] += 1
                inEdges[inFill[to[index]]] = index
                inFill[to[index]] += 1
            }
        }
    }

    /// Gives every node its rank: the longest path from the nodes no edge enters, then eight passes that move each node
    /// towards the side with more edges, ports put above or below everything else.
    static func rank(nodes: inout [LayeredFlatNode], edges: [LayeredFlatEdge], step: Int) {
        let nodeCount = nodes.count
        let oriented = OrientedEdges(nodeCount: nodeCount, edges: edges, step: step)
        var ranks = [Int](repeating: 0, count: nodeCount)
        // Start ports go above every node later, so they don't push their targets down a rank.
        for node in 0..<nodeCount where nodes[node].kind == .startPort { ranks[node] = -step }
        var remainingIn = (0..<nodeCount).map { node in oriented.inStart[node + 1] - oriented.inStart[node] }
        var topological: [Int] = (0..<nodeCount).filter { node in remainingIn[node] == 0 }
        var queueIndex = 0
        while queueIndex < topological.count {
            let node = topological[queueIndex]
            queueIndex += 1
            for position in oriented.outStart[node]..<oriented.outStart[node + 1] {
                let edgeIndex = oriented.outEdges[position]
                let head = oriented.to[edgeIndex]
                if ranks[node] + oriented.length[edgeIndex] > ranks[head] { ranks[head] = ranks[node] + oriented.length[edgeIndex] }
                remainingIn[head] -= 1
                if remainingIn[head] == 0 { topological.append(head) }
            }
        }
        balance(&ranks, topological: topological, oriented: oriented)
        normalize(&nodes, ranks: ranks, step: step)
    }

    /// Longest-path ranking leaves loosely attached nodes far from their neighbours: each node moves toward the side
    /// that has more edges, in up to eight passes over the nodes in reverse topological order.
    private static func balance(_ ranks: inout [Int], topological: [Int], oriented: OrientedEdges) {
        for _ in 0..<8 {
            var changed = false
            for node in topological.reversed() {
                let incoming = oriented.inStart[node + 1] - oriented.inStart[node]
                let outgoing = oriented.outStart[node + 1] - oriented.outStart[node]
                if incoming == 0 && outgoing == 0 { continue }
                var lowest = Int.min
                var highest = Int.max
                for position in oriented.inStart[node]..<oriented.inStart[node + 1] {
                    let edgeIndex = oriented.inEdges[position]
                    lowest = max(lowest, ranks[oriented.from[edgeIndex]] + oriented.length[edgeIndex])
                }
                for position in oriented.outStart[node]..<oriented.outStart[node + 1] {
                    let edgeIndex = oriented.outEdges[position]
                    highest = min(highest, ranks[oriented.to[edgeIndex]] - oriented.length[edgeIndex])
                }
                var next = ranks[node]
                if outgoing > incoming && highest != Int.max { next = highest } else if incoming > outgoing && lowest != Int.min { next = lowest }
                if next != ranks[node] {
                    ranks[node] = next
                    changed = true
                }
            }
            if !changed { break }
        }
    }

    /// Puts start ports a step above the highest node and end ports a step below the lowest, and the ranks from 0.
    private static func normalize(_ nodes: inout [LayeredFlatNode], ranks: [Int], step: Int) {
        var lowest = Int.max
        var highest = Int.min
        var hasStartPorts = false
        for node in nodes.indices {
            if nodes[node].kind == .startPort { hasStartPorts = true }
            if nodes[node].kind.isPort { continue }
            lowest = min(lowest, ranks[node])
            highest = max(highest, ranks[node])
        }
        if lowest == Int.max {
            lowest = 0
            highest = 0
        }
        var ranks = ranks
        for node in nodes.indices {
            if nodes[node].kind == .startPort { ranks[node] = lowest - step } else if nodes[node].kind == .endPort { ranks[node] = highest + step }
        }
        if hasStartPorts { lowest -= step }
        for node in nodes.indices { nodes[node].rank = ranks[node] - lowest }
    }
}
