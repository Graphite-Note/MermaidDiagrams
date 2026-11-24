/**
 * File: LayeredArenaRanking.swift
 * -------------------------------
 * Layer: Core (redesign prototype)
 * Description: Pele's orient and rank over the scratch arena: the same steps as LayeredFlatRanking in the same order,
 *              every list a span of 32-bit indices, so the numbers are the same and nothing is counted or allocated.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 24/11/2026
 */

/// The flat graph's edges as the redesigned layout keeps them: one span per field, indexed by edge.
struct LayeredArenaEdges {
    let count: Int
    let tail: ScratchSpan<Int32>
    let head: ScratchSpan<Int32>
    let minimumLength: ScratchSpan<Int32>
    let isReversed: ScratchSpan<Bool>
}

enum LayeredArenaRanking {
    /// Ranks of `nodeCount` nodes of kinds `kinds`, edges turned around where `orient` turns them.
    static func orientAndRank(nodeCount: Int, kinds: ScratchSpan<LayeredVertexKind>, edges: LayeredArenaEdges, step: Int32,
                              arena: LayeredScratchArena) -> ScratchSpan<Int32> {
        orient(nodeCount: nodeCount, kinds: kinds, edges: edges, arena: arena)
        return rank(nodeCount: nodeCount, kinds: kinds, edges: edges, step: step, arena: arena)
    }

    static func orient(nodeCount: Int, kinds: ScratchSpan<LayeredVertexKind>, edges: LayeredArenaEdges, arena: LayeredScratchArena) {
        let start = arena.span(nodeCount + 1, repeating: Int32(0))
        for index in 0..<edges.count {
            let reversed = kinds[Int(edges.head[index])] == .startPort || kinds[Int(edges.tail[index])] == .endPort
            edges.isReversed[index] = reversed
            if !reversed { start[Int(edges.tail[index]) + 1] &+= 1 }
        }
        for node in 0..<nodeCount { start[node + 1] &+= start[node] }
        let outgoing = arena.span(Int(start[nodeCount]), repeating: Int32(0))
        let cursor = arena.span(nodeCount, repeating: Int32(0))
        for node in 0..<nodeCount { cursor[node] = start[node] }
        for index in 0..<edges.count where !edges.isReversed[index] {
            let tail = Int(edges.tail[index])
            outgoing[Int(cursor[tail])] = Int32(index)
            cursor[tail] &+= 1
        }
        // The depth-first walk: 0 unvisited, 1 on the walk, 2 done.
        let state = arena.span(nodeCount, repeating: UInt8(0))
        for node in 0..<nodeCount { cursor[node] = start[node] }
        var stack = arena.list(capacity: nodeCount, of: Int32.self)
        for root in 0..<nodeCount where state[root] == 0 {
            stack.append(Int32(root))
            state[root] = 1
            while stack.count > 0 {
                let node = Int(stack[stack.count - 1])
                if cursor[node] < start[node + 1] {
                    let edgeIndex = Int(outgoing[Int(cursor[node])])
                    cursor[node] &+= 1
                    let head = Int(edges.head[edgeIndex])
                    if state[head] == 1 {
                        edges.isReversed[edgeIndex] = true
                    } else if state[head] == 0 {
                        state[head] = 1
                        stack.append(Int32(head))
                    }
                } else {
                    state[node] = 2
                    _ = stack.removeLast()
                }
            }
        }
    }

    static func rank(nodeCount: Int, kinds: ScratchSpan<LayeredVertexKind>, edges: LayeredArenaEdges, step: Int32,
                     arena: LayeredScratchArena) -> ScratchSpan<Int32> {
        let edgeCount = edges.count
        let from = arena.span(edgeCount, repeating: Int32(0))
        let to = arena.span(edgeCount, repeating: Int32(0))
        let length = arena.span(edgeCount, repeating: Int32(0))
        let outStart = arena.span(nodeCount + 1, repeating: Int32(0))
        let inStart = arena.span(nodeCount + 1, repeating: Int32(0))
        for index in 0..<edgeCount {
            let reversed = edges.isReversed[index]
            from[index] = reversed ? edges.head[index] : edges.tail[index]
            to[index] = reversed ? edges.tail[index] : edges.head[index]
            length[index] = max(1, edges.minimumLength[index]) &* step
            outStart[Int(from[index]) + 1] &+= 1
            inStart[Int(to[index]) + 1] &+= 1
        }
        for node in 0..<nodeCount {
            outStart[node + 1] &+= outStart[node]
            inStart[node + 1] &+= inStart[node]
        }
        let outEdges = arena.span(edgeCount, repeating: Int32(0))
        let inEdges = arena.span(edgeCount, repeating: Int32(0))
        let outFill = arena.span(nodeCount, repeating: Int32(0))
        let inFill = arena.span(nodeCount, repeating: Int32(0))
        for node in 0..<nodeCount {
            outFill[node] = outStart[node]
            inFill[node] = inStart[node]
        }
        for index in 0..<edgeCount {
            outEdges[Int(outFill[Int(from[index])])] = Int32(index)
            outFill[Int(from[index])] &+= 1
            inEdges[Int(inFill[Int(to[index])])] = Int32(index)
            inFill[Int(to[index])] &+= 1
        }
        let ranks = arena.span(nodeCount, repeating: Int32(0))
        for node in 0..<nodeCount where kinds[node] == .startPort { ranks[node] = -step }
        // remainingIn reuses outFill's room: it is no longer read.
        let remainingIn = outFill
        for node in 0..<nodeCount { remainingIn[node] = inStart[node + 1] &- inStart[node] }
        var topological = arena.list(capacity: nodeCount, of: Int32.self)
        for node in 0..<nodeCount where remainingIn[node] == 0 { topological.append(Int32(node)) }
        var queueIndex = 0
        while queueIndex < topological.count {
            let node = Int(topological[queueIndex])
            queueIndex += 1
            for position in Int(outStart[node])..<Int(outStart[node + 1]) {
                let edgeIndex = Int(outEdges[position])
                let head = Int(to[edgeIndex])
                if ranks[node] &+ length[edgeIndex] > ranks[head] { ranks[head] = ranks[node] &+ length[edgeIndex] }
                remainingIn[head] &-= 1
                if remainingIn[head] == 0 { topological.append(Int32(head)) }
            }
        }
        // balance
        for _ in 0..<8 {
            var changed = false
            var reverseIndex = topological.count - 1
            while reverseIndex >= 0 {
                let node = Int(topological[reverseIndex])
                reverseIndex -= 1
                let incoming = inStart[node + 1] &- inStart[node]
                let outgoing = outStart[node + 1] &- outStart[node]
                if incoming == 0 && outgoing == 0 { continue }
                var lowest = Int32.min
                var highest = Int32.max
                for position in Int(inStart[node])..<Int(inStart[node + 1]) {
                    let edgeIndex = Int(inEdges[position])
                    lowest = max(lowest, ranks[Int(from[edgeIndex])] &+ length[edgeIndex])
                }
                for position in Int(outStart[node])..<Int(outStart[node + 1]) {
                    let edgeIndex = Int(outEdges[position])
                    highest = min(highest, ranks[Int(to[edgeIndex])] &- length[edgeIndex])
                }
                var next = ranks[node]
                if outgoing > incoming && highest != Int32.max { next = highest } else if incoming > outgoing && lowest != Int32.min { next = lowest }
                if next != ranks[node] {
                    ranks[node] = next
                    changed = true
                }
            }
            if !changed { break }
        }
        // normalize
        var lowest = Int32.max
        var highest = Int32.min
        var hasStartPorts = false
        for node in 0..<nodeCount {
            if kinds[node] == .startPort { hasStartPorts = true }
            if kinds[node].isPort { continue }
            lowest = min(lowest, ranks[node])
            highest = max(highest, ranks[node])
        }
        if lowest == Int32.max {
            lowest = 0
            highest = 0
        }
        for node in 0..<nodeCount {
            if kinds[node] == .startPort { ranks[node] = lowest &- step } else if kinds[node] == .endPort { ranks[node] = highest &+ step }
        }
        if hasStartPorts { lowest &-= step }
        for node in 0..<nodeCount { ranks[node] = ranks[node] &- lowest }
        return ranks
    }
}
