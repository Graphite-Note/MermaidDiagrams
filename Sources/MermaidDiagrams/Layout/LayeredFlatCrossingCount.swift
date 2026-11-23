/**
 * File: LayeredFlatCrossingCount.swift
 * ------------------------------------
 * Layer: Core
 * Description: Counts the crossings of an order of Pele's layered layout, with a tree over each rank's places.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 23/11/2026
 */

/// Pele's `reduceCrossings` (layout/layered.ts): the counting of crossings here, the sweeps, swaps and attempts in
/// `LayeredFlatCrossingReduction.swift`.
struct LayeredFlatCrossingReduction {
    var graph: LayeredFlatGraph
    /// The pin of each node.
    let pins: [Int]
    let widest: Int
    /// With offsets, edges that reach one node at different offsets take separate places along it: each segment's
    /// place in the rank below, its place among its node's, and how many places each vertex has.
    let usesPlaces: Bool
    var place: [Int]
    var placeWithinNode: [Int]
    var placeCount: [Int]
    /// The segments leaving each vertex, sorted by their offsets where they differ, and the vertices where they did.
    var leaving: [Int]
    var hasMixedOffsets: [Bool]
    var tree: [Int]
    var targets: [Int]
    var barycenter: [Double]
    var groupDepth: [Int] = []
    var groupSum: [Double] = []
    var groupCount: [Int] = []
    var groupFirst: [Int] = []

    init(graph: LayeredFlatGraph, nodes: [LayeredFlatNode]) {
        self.graph = graph
        pins = nodes.map(\.pin)
        widest = (0...graph.maximumRank).map { rank in graph.rankStart[rank + 1] - graph.rankStart[rank] }.max() ?? 0
        let segmentCount = graph.segmentCount
        usesPlaces = graph.hasOffsets
        place = [Int](repeating: 0, count: graph.hasOffsets ? segmentCount : 0)
        placeWithinNode = [Int](repeating: 0, count: graph.hasOffsets ? segmentCount : 0)
        placeCount = [Int](repeating: 0, count: graph.hasOffsets ? graph.vertexCount : 0)
        leaving = graph.successorSegments
        hasMixedOffsets = [Bool](repeating: false, count: graph.hasOffsets ? graph.vertexCount : 0)
        var size = 1
        while size < (graph.hasOffsets ? widest + segmentCount : widest) { size <<= 1 }
        tree = [Int](repeating: 0, count: 2 * size)
        targets = [Int](repeating: 0, count: segmentCount)
        barycenter = [Double](repeating: 0, count: graph.vertexCount)
        if graph.hasOffsets { orderPlacesByOffset() }
    }

    /// Sorts `list[start..<end]` by `offsets` when they differ there; whether they did.
    private static func sortedByOffset(_ list: inout [Int], start: Int, end: Int, offsets: [Double]) -> Bool {
        guard start + 1 < end else { return false }
        for index in (start + 1)..<end where offsets[list[index]] != offsets[list[start]] {
            var run = Array(list[start..<end])
            run.sortStably { first, second in offsets[first] - offsets[second] }
            list.replaceSubrange(start..<end, with: run)
            return true
        }
        return false
    }

    /// Local offset indices and counts, which do not depend on the order.
    private mutating func orderPlacesByOffset() {
        var arriving = graph.predecessorSegments
        for vertex in 0..<graph.vertexCount {
            placeCount[vertex] = 1
            let start = graph.predecessorStart[vertex]
            let end = graph.predecessorStart[vertex + 1]
            if Self.sortedByOffset(&arriving, start: start, end: end, offsets: graph.segmentToOffset) {
                for index in (start + 1)..<end {
                    if graph.segmentToOffset[arriving[index]] != graph.segmentToOffset[arriving[index - 1]] { placeCount[vertex] += 1 }
                    placeWithinNode[arriving[index]] = placeCount[vertex] - 1
                }
            }
            if Self.sortedByOffset(&leaving, start: graph.successorStart[vertex], end: graph.successorStart[vertex + 1],
                                   offsets: graph.segmentFromOffset) {
                hasMixedOffsets[vertex] = true
            }
        }
    }

    /// The crossings of the present order, summed over the gaps between ranks.
    mutating func count() -> Int {
        var total = 0
        for rank in 0..<graph.maximumRank {
            let southLength = southPlaces(below: rank)
            if southLength < 2 { continue }
            let targetCount = fillTargets(rank: rank)
            if targetCount < 2 { continue }
            var leaves = 1
            while leaves < southLength { leaves <<= 1 }
            for index in 0..<(2 * leaves) { tree[index] = 0 }
            for target in targets[0..<targetCount] {
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
    private mutating func southPlaces(below rank: Int) -> Int {
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
    private mutating func fillTargets(rank: Int) -> Int {
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
                targets[firstTarget..<targetCount].sort()
            }
        }
        return targetCount
    }

    /// Sorts the targets of edges that leave at one offset by destination, so that shared ends count no crossing.
    private mutating func sortWithinEqualOffsets(firstTarget: Int, end: Int, from: Int) {
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
