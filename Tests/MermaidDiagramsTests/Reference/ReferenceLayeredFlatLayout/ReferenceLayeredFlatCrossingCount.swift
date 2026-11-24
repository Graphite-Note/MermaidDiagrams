/**
 * File: ReferenceLayeredFlatCrossingCount.swift
 * ---------------------------------------------
 * Layer: Tests
 * Description: The 0.7.0 layered layout kept as the reference the span layout is checked against: counts the crossings
 *              of an order of Pele's layered layout, with a tree over each rank's places.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 24/11/2026
 */

@testable import MermaidDiagrams

/// Pele's `reduceCrossings` (layout/layered.ts): the counting of crossings here, the sweeps, swaps and attempts in
/// `ReferenceLayeredFlatCrossingReduction.swift`.
struct ReferenceLayeredFlatCrossingReduction {
    var graph: ReferenceLayeredFlatGraph
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
    /// The vertices of the rank a sweep is moving, kept between ranks so that each sweep reuses one list.
    var movingVertices: [Int] = []
    /// The second list the sweeps' merge sort writes into.
    var sortSpare: [Int] = []
    var groupDepth: [Int] = []
    var groupSum: [Double] = []
    var groupCount: [Int] = []
    var groupFirst: [Int] = []
    /// The rank being arranged by groups.
    var arrangedRow: [Int] = []
    let workspace: ReferenceLayeredFlatWorkspace

    init(graph: consuming ReferenceLayeredFlatGraph, nodes: [LayeredFlatNode], workspace: ReferenceLayeredFlatWorkspace) {
        self.workspace = workspace
        self.graph = graph
        var pins = workspace.emptyIntegers(capacity: nodes.count)
        for node in nodes { pins.append(node.pin) }
        self.pins = pins
        widest = Self.widestRank(of: self.graph)
        let segmentCount = self.graph.segmentCount
        let vertexCount = self.graph.vertexCount
        let hasOffsets = self.graph.hasOffsets
        usesPlaces = hasOffsets
        place = workspace.integers(count: hasOffsets ? segmentCount : 0, repeating: 0)
        placeWithinNode = workspace.integers(count: hasOffsets ? segmentCount : 0, repeating: 0)
        placeCount = workspace.integers(count: hasOffsets ? vertexCount : 0, repeating: 0)
        if hasOffsets {
            leaving = workspace.emptyIntegers(capacity: segmentCount)
            leaving.append(contentsOf: self.graph.successorSegments)
        } else {
            leaving = self.graph.successorSegments
        }
        hasMixedOffsets = workspace.flags(count: hasOffsets ? vertexCount : 0, repeating: false)
        var size = 1
        while size < (hasOffsets ? widest + segmentCount : widest) { size <<= 1 }
        tree = workspace.integers(count: 2 * size, repeating: 0)
        targets = workspace.integers(count: segmentCount, repeating: 0)
        barycenter = workspace.numbers(count: vertexCount, repeating: 0)
        movingVertices = workspace.emptyIntegers(capacity: 0)
        sortSpare = workspace.emptyIntegers(capacity: 0)
        if hasOffsets { orderPlacesByOffset() }
    }

    /// The ordered graph, the reduction's own lists given back to the workspace.
    consuming func finished() -> ReferenceLayeredFlatGraph {
        workspace.recycle(pins)
        workspace.recycle(place)
        workspace.recycle(placeWithinNode)
        workspace.recycle(placeCount)
        if usesPlaces { workspace.recycle(leaving) }
        workspace.recycle(hasMixedOffsets)
        workspace.recycle(tree)
        workspace.recycle(targets)
        workspace.recycle(barycenter)
        workspace.recycle(movingVertices)
        workspace.recycle(sortSpare)
        workspace.recycle(groupDepth)
        workspace.recycle(groupSum)
        workspace.recycle(groupCount)
        workspace.recycle(groupFirst)
        workspace.recycle(arrangedRow)
        return graph
    }

    /// How many vertices the graph's widest rank holds.
    static func widestRank(of graph: ReferenceLayeredFlatGraph) -> Int {
        var widest = 0
        for rank in 0...graph.maximumRank { widest = max(widest, graph.rankStart[rank + 1] - graph.rankStart[rank]) }
        return widest
    }

    /// Sorts `list[start..<end]` by `offsets` when they differ there, through `run` and `spare`; whether they did.
    private static func sortedByOffset(_ list: inout [Int], start: Int, end: Int, offsets: [Double], run: inout [Int],
                                       spare: inout [Int]) -> Bool {
        guard start + 1 < end else { return false }
        for index in (start + 1)..<end where offsets[list[index]] != offsets[list[start]] {
            run.removeAll(keepingCapacity: true)
            run.append(contentsOf: list[start..<end])
            run.sortStably(spare: &spare) { first, second in offsets[first] - offsets[second] < 0 }
            list.replaceSubrange(start..<end, with: run)
            return true
        }
        return false
    }

    /// Local offset indices and counts, which do not depend on the order.
    private mutating func orderPlacesByOffset() {
        var arriving = workspace.emptyIntegers(capacity: graph.segmentCount)
        arriving.append(contentsOf: graph.predecessorSegments)
        var run = workspace.emptyIntegers(capacity: 0)
        var spare = workspace.emptyIntegers(capacity: 0)
        defer {
            workspace.recycle(arriving)
            workspace.recycle(run)
            workspace.recycle(spare)
        }
        for vertex in 0..<graph.vertexCount {
            placeCount[vertex] = 1
            let start = graph.predecessorStart[vertex]
            let end = graph.predecessorStart[vertex + 1]
            if Self.sortedByOffset(&arriving, start: start, end: end, offsets: graph.segmentToOffset, run: &run, spare: &spare) {
                for index in (start + 1)..<end {
                    if graph.segmentToOffset[arriving[index]] != graph.segmentToOffset[arriving[index - 1]] { placeCount[vertex] += 1 }
                    placeWithinNode[arriving[index]] = placeCount[vertex] - 1
                }
            }
            if Self.sortedByOffset(&leaving, start: graph.successorStart[vertex], end: graph.successorStart[vertex + 1],
                                   offsets: graph.segmentFromOffset, run: &run, spare: &spare) {
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
            let targets = targets
            // The tree's places are below 2 * leaves, which the tree was made long enough for.
            tree.withUnsafeMutableBufferPointer { tree in
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
