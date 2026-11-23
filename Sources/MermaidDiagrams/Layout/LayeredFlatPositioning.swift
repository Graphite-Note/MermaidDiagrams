/**
 * File: LayeredFlatPositioning.swift
 * ----------------------------------
 * Layer: Core
 * Description: Pele's positions across the flow: Brandes and Köpf's four aligned layouts, balanced (layered.ts position).
 *
 * Authors: Bahey Shalash
 * Version: 0.2
 * Date: 23/11/2026
 */

/// Pele's `position`: each vertex aligned with a median neighbour above or below, leftmost or rightmost first, every
/// block compacted against its neighbours, the four layouts shifted onto the narrowest and each vertex placed at the
/// mean of the middle two.
enum LayeredFlatPositioning {
    static func positions(_ graph: inout LayeredFlatGraph, options: LayeredFlatOptions) -> [Double] {
        let vertexCount = graph.vertexCount
        var gap = [Double](repeating: 0, count: vertexCount)
        for vertex in 0..<vertexCount { gap[vertex] = graph.halfRoom(of: vertex, options: options) }
        sortNeighbours(&graph)
        let conflict = conflictingSegments(graph)
        // The four layouts one after the other, made with one set of working arrays.
        var results = [Double](repeating: 0, count: 4 * vertexCount)
        var work = LayeredPositioningWork(vertexCount: vertexCount)
        for variant in 0..<4 {
            let isRightward = variant & 1 == 1
            work.align(graph, conflict: conflict, isUpward: variant < 2, isRightward: isRightward)
            work.compact(graph, gap: gap, isRightward: isRightward, into: &results, at: variant * vertexCount)
        }
        return balanced(&results, vertexCount: vertexCount, widths: graph.vertexWidth)
    }

    /// Neighbours in order across their rank, so that the medians can be read off directly.
    private static func sortNeighbours(_ graph: inout LayeredFlatGraph) {
        let position = graph.position
        func sortRuns(_ list: inout [Int], starts: [Int], key: (Int) -> Int) {
            for vertex in 0..<graph.vertexCount where starts[vertex + 1] - starts[vertex] > 1 {
                var run = Array(list[starts[vertex]..<starts[vertex + 1]])
                run.sort { first, second in key(first) != key(second) ? key(first) < key(second) : first < second }
                list.replaceSubrange(starts[vertex]..<starts[vertex + 1], with: run)
            }
        }
        let segmentTo = graph.segmentTo
        let segmentFrom = graph.segmentFrom
        sortRuns(&graph.successorSegments, starts: graph.successorStart) { segment in position[segmentTo[segment]] }
        sortRuns(&graph.predecessorSegments, starts: graph.predecessorStart) { segment in position[segmentFrom[segment]] }
    }

    /// The segments between two nodes, or a node and a bend, that cross a segment between two bends: an alignment
    /// along them would cross the long edge's inner segment.
    private static func conflictingSegments(_ graph: LayeredFlatGraph) -> [Bool] {
        var conflict = [Bool](repeating: false, count: graph.segmentCount)
        guard graph.maximumRank >= 1 else { return conflict }
        for rank in 1...graph.maximumRank {
            let previousLength = graph.rankStart[rank] - graph.rankStart[rank - 1]
            let start = graph.rankStart[rank]
            let end = graph.rankStart[rank + 1]
            var lowerBound = 0
            var scan = start
            for index in start..<end {
                let vertex = graph.order[index]
                var inner = -1
                if graph.vertexKind[vertex].isPassingPoint {
                    let upper = graph.segmentFrom[graph.predecessorSegments[graph.predecessorStart[vertex]]]
                    if graph.vertexKind[upper].isPassingPoint { inner = upper }
                }
                let upperBound = inner >= 0 ? graph.position[inner] : previousLength
                guard inner >= 0 || index == end - 1 else { continue }
                for scanned in scan...index {
                    let lower = graph.order[scanned]
                    let lowerIsPassing = graph.vertexKind[lower].isPassingPoint
                    for position in graph.predecessorStart[lower]..<graph.predecessorStart[lower + 1] {
                        let segment = graph.predecessorSegments[position]
                        let upperPosition = graph.position[graph.segmentFrom[segment]]
                        if (upperPosition < lowerBound || upperBound < upperPosition)
                            && !(lowerIsPassing && graph.vertexKind[graph.segmentFrom[segment]].isPassingPoint) { conflict[segment] = true }
                    }
                }
                scan = index + 1
                lowerBound = upperBound
            }
        }
        return conflict
    }

    /// The four layouts moved onto the narrowest (the leftward ones by their left edges, the rightward by their right),
    /// each vertex at the mean of its middle two positions. `results` holds the four layouts one after the other.
    private static func balanced(_ results: inout [Double], vertexCount: Int, widths: [Double]) -> [Double] {
        var narrowest = 0
        var bestWidth = Double.infinity
        var lows: [Double] = []
        var highs: [Double] = []
        lows.reserveCapacity(4)
        highs.reserveCapacity(4)
        for variant in 0..<4 {
            let base = variant * vertexCount
            var low = Double.infinity
            var high = -Double.infinity
            for vertex in 0..<vertexCount {
                low = min(low, results[base + vertex] - widths[vertex] / 2)
                high = max(high, results[base + vertex] + widths[vertex] / 2)
            }
            lows.append(low)
            highs.append(high)
            if high - low < bestWidth {
                bestWidth = high - low
                narrowest = variant
            }
        }
        for variant in 0..<4 {
            let delta = variant & 1 == 0 ? lows[narrowest] - lows[variant] : highs[narrowest] - highs[variant]
            if delta == 0 { continue }
            let base = variant * vertexCount
            for vertex in 0..<vertexCount { results[base + vertex] = results[base + vertex] + delta }
        }
        var balanced = [Double](repeating: 0, count: vertexCount)
        for vertex in 0..<vertexCount {
            let middle = middleTwo(results[vertex], results[vertexCount + vertex], results[2 * vertexCount + vertex],
                                   results[3 * vertexCount + vertex])
            balanced[vertex] = (middle.second + middle.third) / 2
        }
        return balanced
    }

    /// The second and third of four values sorted as `Array.sorted()` sorts four: by insertion, each value swapped
    /// before the one ahead of it while it is less, so that equal values (zeros of either sign too) end where they would.
    private static func middleTwo(_ first: Double, _ second: Double, _ third: Double, _ fourth: Double)
        -> (second: Double, third: Double) {
        var first = first, second = second, third = third, fourth = fourth
        if second < first { swap(&first, &second) }
        if third < second {
            swap(&second, &third)
            if second < first { swap(&first, &second) }
        }
        if fourth < third {
            swap(&third, &fourth)
            if third < second {
                swap(&second, &third)
                if second < first { swap(&first, &second) }
            }
        }
        return (second, third)
    }
}
