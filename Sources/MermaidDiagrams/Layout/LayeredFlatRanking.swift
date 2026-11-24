/**
 * File: LayeredFlatRanking.swift
 * ------------------------------
 * Layer: Core
 * Description: The first two steps of Pele's layered layout: edges that close cycles turned around, then ranks.
 *
 * Authors: Bahey Shalash
 * Version: 0.4
 * Date: 24/11/2026
 */

/// Pele's `orient` and `rank` (layout/layered.ts), step for step, on spans of a scratch arena; every working list is
/// given back to the arena before a step returns.
enum LayeredFlatRanking {
    /// Turns around the edges that close a cycle, found by a depth-first walk from each node in declaration order, and
    /// the edges that run into a start port or out of an end port.
    static func orient(nodes: ScratchSpan<LayeredFlatNode>, edges: ScratchSpan<LayeredSpanEdge>, arena: DiagramScratchArena) {
        let mark = arena.mark()
        defer { arena.release(to: mark) }
        let nodeCount = nodes.count
        let start = arena.span(count: nodeCount + 1, repeating: 0)
        for index in edges.indices {
            edges[index].isReversed = nodes[edges[index].head].kind == .startPort || nodes[edges[index].tail].kind == .endPort
            if !edges[index].isReversed { start[edges[index].tail + 1] += 1 }
        }
        for node in 0..<nodeCount { start[node + 1] += start[node] }
        let outgoing = arena.span(count: start[nodeCount], repeating: 0)
        // Each node's fill of its edges out, then its cursor over them.
        let cursor = arena.copy(of: start.part(0..<nodeCount))
        for index in edges.indices where !edges[index].isReversed {
            outgoing[cursor[edges[index].tail]] = index
            cursor[edges[index].tail] += 1
        }
        reverseCycles(edges: edges, start: start, outgoing: outgoing, cursor: cursor, arena: arena)
    }

    /// The depth-first walk of `orient`: an edge that reaches a node still on the walk closes a cycle and is turned
    /// around. `start` and `outgoing` list each node's edges out; `cursor` is each node's place in its list.
    private static func reverseCycles(edges: ScratchSpan<LayeredSpanEdge>, start: ScratchSpan<Int>, outgoing: ScratchSpan<Int>,
                                      cursor: ScratchSpan<Int>, arena: DiagramScratchArena) {
        let nodeCount = cursor.count
        // 0 unvisited, 1 on the walk, 2 done.
        let state = arena.span(count: nodeCount, repeating: UInt8(0))
        for node in 0..<nodeCount { cursor[node] = start[node] }
        var stack = arena.list(capacity: nodeCount, of: Int.self)
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
                    _ = stack.removeLast()
                }
            }
        }
    }

    /// The edges as they run after `orient`, with their lengths, and each node's edges out and in.
    private struct OrientedEdges {
        let from: ScratchSpan<Int>
        let to: ScratchSpan<Int>
        let length: ScratchSpan<Int>
        let outStart: ScratchSpan<Int>
        let outEdges: ScratchSpan<Int>
        let inStart: ScratchSpan<Int>
        let inEdges: ScratchSpan<Int>

        init(nodeCount: Int, edges: ScratchSpan<LayeredSpanEdge>, step: Int, arena: DiagramScratchArena) {
            from = arena.uninitializedSpan(count: edges.count)
            to = arena.uninitializedSpan(count: edges.count)
            length = arena.uninitializedSpan(count: edges.count)
            for index in edges.indices {
                let edge = edges[index]
                from[index] = edge.isReversed ? edge.head : edge.tail
                to[index] = edge.isReversed ? edge.tail : edge.head
                length[index] = max(1, edge.minimumLength) * step
            }
            outStart = arena.span(count: nodeCount + 1, repeating: 0)
            inStart = arena.span(count: nodeCount + 1, repeating: 0)
            for index in edges.indices {
                outStart[from[index] + 1] += 1
                inStart[to[index] + 1] += 1
            }
            for node in 0..<nodeCount {
                outStart[node + 1] += outStart[node]
                inStart[node + 1] += inStart[node]
            }
            outEdges = arena.span(count: edges.count, repeating: 0)
            inEdges = arena.span(count: edges.count, repeating: 0)
            let outFill = arena.copy(of: outStart.part(0..<nodeCount))
            let inFill = arena.copy(of: inStart.part(0..<nodeCount))
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
    static func rank(nodes: ScratchSpan<LayeredFlatNode>, edges: ScratchSpan<LayeredSpanEdge>, step: Int, arena: DiagramScratchArena) {
        let mark = arena.mark()
        defer { arena.release(to: mark) }
        let nodeCount = nodes.count
        let oriented = OrientedEdges(nodeCount: nodeCount, edges: edges, step: step, arena: arena)
        let ranks = arena.span(count: nodeCount, repeating: 0)
        // Start ports go above every node later, so they don't push their targets down a rank.
        for node in 0..<nodeCount where nodes[node].kind == .startPort { ranks[node] = -step }
        let remainingIn: ScratchSpan<Int> = arena.uninitializedSpan(count: nodeCount)
        for node in 0..<nodeCount { remainingIn[node] = oriented.inStart[node + 1] - oriented.inStart[node] }
        var topological = arena.list(capacity: nodeCount, of: Int.self)
        for node in 0..<nodeCount where remainingIn[node] == 0 { topological.append(node) }
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
        balance(ranks, topological: topological.elements, oriented: oriented)
        normalize(nodes, ranks: ranks, step: step)
    }

    /// Longest-path ranking leaves loosely attached nodes far from their neighbours: each node moves toward the side
    /// that has more edges, in up to eight passes over the nodes in reverse topological order.
    private static func balance(_ ranks: ScratchSpan<Int>, topological: ScratchSpan<Int>, oriented: OrientedEdges) {
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
    private static func normalize(_ nodes: ScratchSpan<LayeredFlatNode>, ranks: ScratchSpan<Int>, step: Int) {
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
        for node in nodes.indices {
            if nodes[node].kind == .startPort { ranks[node] = lowest - step } else if nodes[node].kind == .endPort { ranks[node] = highest + step }
        }
        if hasStartPorts { lowest -= step }
        for node in nodes.indices { nodes[node].rank = ranks[node] - lowest }
    }

    /// `orient` then `rank`, as a compound layout ranks a level.
    static func orientAndRank(nodes: ScratchSpan<LayeredFlatNode>, edges: ScratchSpan<LayeredSpanEdge>, step: Int, arena: DiagramScratchArena) {
        #if DEBUG
        LayeredLayoutRecording.current?.rankings.append((Array(nodes), edges.map(LayeredFlatEdge.init)))
        #endif
        orient(nodes: nodes, edges: edges, arena: arena)
        rank(nodes: nodes, edges: edges, step: step, arena: arena)
    }

    /// `orientAndRank` on lists, with the calling thread's arena.
    static func orientAndRank(nodes: inout [LayeredFlatNode], edges: inout [LayeredFlatEdge], step: Int) {
        DiagramScratchArena.withCurrentThread { arena in
            let nodeSpan: ScratchSpan<LayeredFlatNode> = arena.uninitializedSpan(count: nodes.count)
            for node in nodes.indices { nodeSpan[node] = nodes[node] }
            let edgeSpan: ScratchSpan<LayeredSpanEdge> = arena.uninitializedSpan(count: edges.count)
            for edgeIndex in edges.indices { edgeSpan[edgeIndex] = LayeredSpanEdge(edges[edgeIndex]) }
            orientAndRank(nodes: nodeSpan, edges: edgeSpan, step: step, arena: arena)
            for node in nodes.indices { nodes[node].rank = nodeSpan[node].rank }
            for edgeIndex in edges.indices { edges[edgeIndex].isReversed = edgeSpan[edgeIndex].isReversed }
        }
    }
}
