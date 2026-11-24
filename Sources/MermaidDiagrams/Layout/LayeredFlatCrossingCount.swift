/**
 * File: LayeredFlatCrossingCount.swift
 * ------------------------------------
 * Layer: Core
 * Description: Counts the crossings of an order of Pele's layered layout, with a tree over each rank's places.
 *
 * Authors: Bahey Shalash
 * Version: 0.4
 * Date: 24/11/2026
 */

/// Pele's `reduceCrossings` (layout/layered.ts): the counting of crossings here, the sweeps, swaps and attempts in
/// `LayeredFlatCrossingReduction.swift`.
struct LayeredFlatCrossingReduction {
    var graph: LayeredFlatGraph
    /// The pin of each node.
    let pins: ScratchSpan<Int>
    let widest: Int
    /// With offsets, edges that reach one node at different offsets take separate places along it: each segment's
    /// place in the rank below, its place among its node's, and how many places each vertex has.
    let usesPlaces: Bool
    let place: ScratchSpan<Int>
    let placeWithinNode: ScratchSpan<Int>
    let placeCount: ScratchSpan<Int>
    /// The segments leaving each vertex, sorted by their offsets where they differ, and the vertices where they did.
    let leaving: ScratchSpan<Int>
    let hasMixedOffsets: ScratchSpan<Bool>
    let tree: ScratchSpan<Int>
    let targets: ScratchSpan<Int>
    let barycenter: ScratchSpan<Double>
    /// The vertices of the rank a sweep is moving, kept between ranks so that each sweep reuses one list.
    var movingVertices: ScratchList<Int>
    var groupDepth = ScratchSpan<Int>.empty
    var groupSum = ScratchSpan<Double>.empty
    var groupCount = ScratchSpan<Int>.empty
    var groupFirst = ScratchSpan<Int>.empty
    let arena: DiagramScratchArena

    /// The reduction's lists come from `arena`; the caller gives them back once the reduction is finished.
    init(graph: LayeredFlatGraph, nodes: ScratchSpan<LayeredFlatNode>, arena: DiagramScratchArena) {
        self.arena = arena
        self.graph = graph
        let pins: ScratchSpan<Int> = arena.uninitializedSpan(count: nodes.count)
        for node in nodes.indices { pins[node] = nodes[node].pin }
        self.pins = pins
        widest = Self.widestRank(of: self.graph)
        let segmentCount = self.graph.segmentCount
        let vertexCount = self.graph.vertexCount
        let hasOffsets = self.graph.hasOffsets
        usesPlaces = hasOffsets
        place = arena.span(count: hasOffsets ? segmentCount : 0, repeating: 0)
        placeWithinNode = arena.span(count: hasOffsets ? segmentCount : 0, repeating: 0)
        placeCount = arena.span(count: hasOffsets ? vertexCount : 0, repeating: 0)
        // Without offsets the segments leaving each vertex are read as the graph lists them, never sorted.
        leaving = hasOffsets ? arena.copy(of: self.graph.successorSegments) : self.graph.successorSegments
        hasMixedOffsets = arena.span(count: hasOffsets ? vertexCount : 0, repeating: false)
        var size = 1
        while size < (hasOffsets ? widest + segmentCount : widest) { size <<= 1 }
        tree = arena.span(count: 2 * size, repeating: 0)
        targets = arena.span(count: segmentCount, repeating: 0)
        barycenter = arena.span(count: vertexCount, repeating: 0)
        movingVertices = arena.list(capacity: widest, of: Int.self)
        if hasOffsets { orderPlacesByOffset() }
    }

    /// How many vertices the graph's widest rank holds.
    static func widestRank(of graph: LayeredFlatGraph) -> Int {
        var widest = 0
        for rank in 0...graph.maximumRank { widest = max(widest, graph.rankStart[rank + 1] - graph.rankStart[rank]) }
        return widest
    }

    /// Sorts `list[start..<end]` by `offsets` when they differ there; whether they did.
    private static func sortedByOffset(_ list: ScratchSpan<Int>, start: Int, end: Int, offsets: ScratchSpan<Double>,
                                       arena: DiagramScratchArena) -> Bool {
        guard start + 1 < end else { return false }
        for index in (start + 1)..<end where offsets[list[index]] != offsets[list[start]] {
            list.sortStably(start..<end, in: arena) { first, second in offsets[first] - offsets[second] < 0 }
            return true
        }
        return false
    }

    /// Local offset indices and counts, which do not depend on the order.
    private func orderPlacesByOffset() {
        let mark = arena.mark()
        defer { arena.release(to: mark) }
        let arriving = arena.copy(of: graph.predecessorSegments)
        for vertex in 0..<graph.vertexCount {
            placeCount[vertex] = 1
            let start = graph.predecessorStart[vertex]
            let end = graph.predecessorStart[vertex + 1]
            if Self.sortedByOffset(arriving, start: start, end: end, offsets: graph.segmentToOffset, arena: arena) {
                for index in (start + 1)..<end {
                    if graph.segmentToOffset[arriving[index]] != graph.segmentToOffset[arriving[index - 1]] { placeCount[vertex] += 1 }
                    placeWithinNode[arriving[index]] = placeCount[vertex] - 1
                }
            }
            if Self.sortedByOffset(leaving, start: graph.successorStart[vertex], end: graph.successorStart[vertex + 1],
                                   offsets: graph.segmentFromOffset, arena: arena) {
                hasMixedOffsets[vertex] = true
            }
        }
    }

    /// The crossings of the present order, summed over the gaps between ranks.
    func count() -> Int {
        var total = 0
        for rank in 0..<graph.maximumRank {
            let southLength = southPlaces(below: rank)
            if southLength < 2 { continue }
            let targetCount = fillTargets(rank: rank)
            if targetCount < 2 { continue }
            var leaves = 1
            while leaves < southLength { leaves <<= 1 }
            // The tree's places are below 2 * leaves, which the tree was made long enough for.
            let tree = tree.start
            for index in 0..<(2 * leaves) { tree[index] = 0 }
            for target in targets.part(0..<targetCount) {
                var index = target + leaves
                tree[index] += 1
                while index > 1 {
                    if index & 1 == 0 { total += tree[index + 1] }
                    index >>= 1
                    tree[index] += 1
                }
            }
        }
        return total
    }

    /// How many places the rank below `rank` has, each segment arriving there given its place.
    private func southPlaces(below rank: Int) -> Int {
        guard usesPlaces else { return graph.rankStart[rank + 2] - graph.rankStart[rank + 1] }
        var next = 0
        for index in graph.rankStart[rank + 1]..<graph.rankStart[rank + 2] {
            let vertex = graph.order[index]
            for position in graph.predecessorStart[vertex]..<graph.predecessorStart[vertex + 1] {
                let segment = graph.predecessorSegments[position]
                place[segment] = next + placeWithinNode[segment]
            }
            next += placeCount[vertex]
        }
        return next
    }

    /// The places that the segments leaving `rank` reach, vertex by vertex across it, each vertex's sorted.
    private func fillTargets(rank: Int) -> Int {
        var targetCount = 0
        for index in graph.rankStart[rank]..<graph.rankStart[rank + 1] {
            let vertex = graph.order[index]
            let from = graph.successorStart[vertex]
            let firstTarget = targetCount
            for position in from..<graph.successorStart[vertex + 1] {
                targets[targetCount] = usesPlaces ? place[leaving[position]] : graph.position[graph.segmentTo[graph.successorSegments[position]]]
                targetCount += 1
            }
            if targetCount - firstTarget < 2 { continue }
            if usesPlaces && hasMixedOffsets[vertex] {
                sortWithinEqualOffsets(firstTarget: firstTarget, end: targetCount, from: from)
            } else {
                targets.part(firstTarget..<targetCount).sortAscending()
            }
        }
        return targetCount
    }

    /// Sorts the targets of edges that leave at one offset by destination, so that shared ends count no crossing.
    private func sortWithinEqualOffsets(firstTarget: Int, end: Int, from: Int) {
        for current in (firstTarget + 1)..<end {
            let item = targets[current]
            let offset = graph.segmentFromOffset[leaving[from + current - firstTarget]]
            var before = current - 1
            while before >= firstTarget && graph.segmentFromOffset[leaving[from + before - firstTarget]] == offset && targets[before] > item {
                targets[before + 1] = targets[before]
                before -= 1
            }
            targets[before + 1] = item
        }
    }
}
