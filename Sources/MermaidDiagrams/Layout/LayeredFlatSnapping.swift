/**
 * File: LayeredFlatSnapping.swift
 * -------------------------------
 * Layer: Core
 * Description: Brings nearly straight edges of Pele's layered layout into line, moving blocks of what is in line.
 *
 * Authors: Bahey Shalash
 * Version: 0.4
 * Date: 24/11/2026
 */

/// Pele's `snap` (layout/layered.ts): a node or bend moves a little across the flow, with everything already in line
/// with it, where the vertices beside it leave room; what is in line stays in line, so each move straightens one more
/// edge. The blocks are joined smaller into larger, as a union of member lists.
struct LayeredFlatSnapping {
    /// The graph's spans, whose offsets and order the snapping reads.
    let graph: LayeredFlatGraph
    let options: LayeredFlatOptions
    let emptyRanks: ScratchSpan<Bool>?
    /// Each edge from one point held in place to the next: its upper and lower vertices and offsets.
    private var upper: ScratchList<Int>
    private var lower: ScratchList<Int>
    private var upperOffset: ScratchList<Double>
    private var lowerOffset: ScratchList<Double>
    private let block: ScratchSpan<Int>
    /// The members of each block as a list in the order they joined: its first and last member and how many it has,
    /// and each member's next (-1 after the last).
    private let firstMember: ScratchSpan<Int>
    private let lastMember: ScratchSpan<Int>
    private let memberCount: ScratchSpan<Int>
    private let nextMember: ScratchSpan<Int>
    let arena: DiagramScratchArena

    /// The snapping's lists come from `arena`; the caller gives them back once the snapping is finished.
    init(graph: LayeredFlatGraph, options: LayeredFlatOptions, emptyRanks: ScratchSpan<Bool>?, arena: DiagramScratchArena) {
        self.options = options
        self.emptyRanks = emptyRanks
        self.arena = arena
        let vertexCount = graph.vertexCount
        block = arena.uninitializedSpan(count: vertexCount)
        firstMember = arena.uninitializedSpan(count: vertexCount)
        lastMember = arena.uninitializedSpan(count: vertexCount)
        for vertex in 0..<vertexCount {
            block[vertex] = vertex
            firstMember[vertex] = vertex
            lastMember[vertex] = vertex
        }
        memberCount = arena.span(count: vertexCount, repeating: 1)
        nextMember = arena.span(count: vertexCount, repeating: -1)
        upper = arena.list(capacity: graph.segmentCount, of: Int.self)
        lower = arena.list(capacity: graph.segmentCount, of: Int.self)
        upperOffset = arena.list(capacity: graph.segmentCount, of: Double.self)
        lowerOffset = arena.list(capacity: graph.segmentCount, of: Double.self)
        for segment in 0..<graph.segmentCount {
            let from = graph.segmentFrom[segment]
            if emptyRanks != nil && graph.vertexKind[from] == .bend && emptyRanks?[graph.vertexRank[from]] == true { continue }
            let followed = graph.followed(segment, isUpward: false, emptyRanks: emptyRanks)
            upper.append(from)
            lower.append(graph.segmentTo[followed])
            upperOffset.append(graph.segmentFromOffset[segment])
            lowerOffset.append(graph.segmentToOffset[followed])
        }
        self.graph = graph
    }

    private func offAxis(_ edge: Int, across: ScratchSpan<Double>) -> Double {
        across[lower[edge]] + lowerOffset[edge] - across[upper[edge]] - upperOffset[edge]
    }

    private func join(_ first: Int, _ second: Int) {
        var keep = block[first]
        var drop = block[second]
        if keep == drop { return }
        if memberCount[keep] < memberCount[drop] { swap(&keep, &drop) }
        var vertex = firstMember[drop]
        while vertex >= 0 {
            block[vertex] = keep
            vertex = nextMember[vertex]
        }
        nextMember[lastMember[keep]] = firstMember[drop]
        lastMember[keep] = lastMember[drop]
        memberCount[keep] += memberCount[drop]
        firstMember[drop] = -1
        lastMember[drop] = -1
        memberCount[drop] = 0
    }

    /// Whether every member of block `identifier` is a bend.
    private func holdsOnlyBends(_ identifier: Int) -> Bool {
        var vertex = firstMember[identifier]
        while vertex >= 0 {
            if graph.vertexKind[vertex] != .bend { return false }
            vertex = nextMember[vertex]
        }
        return true
    }

    /// Whether every vertex of block `identifier` can move by `shift` and keep its room from those beside it.
    private func canMove(_ identifier: Int, by shift: Double, across: ScratchSpan<Double>) -> Bool {
        var member = firstMember[identifier]
        while member >= 0 {
            let vertex = member
            member = nextMember[member]
            let start = graph.rankStart[graph.vertexRank[vertex]]
            let end = graph.rankStart[graph.vertexRank[vertex] + 1]
            let index = start + graph.position[vertex]
            let room = graph.halfRoom(of: vertex, options: options)
            if index > start {
                let before = graph.order[index - 1]
                if block[before] != identifier && across[vertex] + shift - across[before] < room + graph.halfRoom(of: before, options: options) - 0.01 { return false }
            }
            if index + 1 < end {
                let after = graph.order[index + 1]
                if block[after] != identifier && across[after] - across[vertex] - shift < room + graph.halfRoom(of: after, options: options) - 0.01 { return false }
            }
        }
        return true
    }

    func snap(_ across: ScratchSpan<Double>) {
        var near = arena.list(capacity: upper.count, of: Int.self)
        for edge in upper.indices {
            let distance = abs(offAxis(edge, across: across))
            if distance < 0.01 { join(upper[edge], lower[edge]) } else if distance <= LayeredFlatConstants.bendSnap { near.append(edge) }
        }
        if near.isEmpty { return }
        // Sorted by the places before any edge snaps: nothing moves while the sort reads them.
        near.sortStably(in: arena) { first, second in
            let difference = abs(offAxis(first, across: across)) - abs(offAxis(second, across: across))
            return (difference != 0 ? difference : Double(first - second)) < 0
        }
        for edge in near { snapEdge(edge, across: across) }
    }

    private func snapEdge(_ edge: Int, across: ScratchSpan<Double>) {
        let distance = offAxis(edge, across: across)
        if abs(distance) < 0.01 {
            join(upper[edge], lower[edge])
            return
        }
        if abs(distance) > LayeredFlatConstants.bendSnap || block[upper[edge]] == block[lower[edge]] { return }
        // The smaller of the two blocks moves, if it can; else the other.
        let upperBlock = block[upper[edge]]
        let lowerBlock = block[lower[edge]]
        let first = memberCount[upperBlock] <= memberCount[lowerBlock] ? upperBlock : lowerBlock
        for attempt in 0..<2 {
            let identifier = attempt == 0 ? first : (first == upperBlock ? lowerBlock : upperBlock)
            let shift = identifier == upperBlock ? distance : -distance
            if abs(distance) > LayeredFlatConstants.nodeSnap && !holdsOnlyBends(identifier) { continue }
            if !canMove(identifier, by: shift, across: across) { continue }
            var vertex = firstMember[identifier]
            while vertex >= 0 {
                across[vertex] += shift
                vertex = nextMember[vertex]
            }
            join(upper[edge], lower[edge])
            break
        }
    }
}

extension LayeredFlatGraph {
    /// The ranks between the first and the last that hold nothing but bends of edges, or nil when none does.
    func emptyRanks(arena: DiagramScratchArena) -> ScratchSpan<Bool>? {
        guard maximumRank > 1 else { return nil }
        let empty = arena.span(count: maximumRank + 1, repeating: false)
        var any = false
        for rank in 1..<maximumRank {
            var only = rankStart[rank + 1] > rankStart[rank]
            for index in rankStart[rank]..<rankStart[rank + 1] where vertexKind[order[index]] != .bend { only = false }
            if only {
                empty[rank] = true
                any = true
            }
        }
        return any ? empty : nil
    }
}
