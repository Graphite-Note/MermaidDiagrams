/**
 * File: LayeredFlatPositioning.swift
 * ----------------------------------
 * Layer: Core
 * Description: Pele's positions across the flow: Brandes and Köpf's four aligned layouts, balanced (layered.ts position).
 *
 * Authors: Bahey Shalash
 * Version: 0.5
 * Date: 25/11/2026
 */

/// Pele's `position`: each vertex aligned with a median neighbour above or below, leftmost or rightmost first, every
/// block compacted against its neighbours, the four layouts shifted onto the narrowest and each vertex placed at the
/// mean of the middle two.
enum LayeredFlatPositioning {
    /// Each vertex's position across the flow, in a span of `arena` taken before the working spans, which are given
    /// back.
    static func positions(_ graph: LayeredFlatGraph, options: LayeredFlatOptions, arena: DiagramScratchArena) -> ScratchSpan<Double> {
        let vertexCount = graph.vertexCount
        let across: ScratchSpan<Double> = arena.uninitializedSpan(count: vertexCount)
        let mark = arena.mark()
        defer { arena.release(to: mark) }
        let gap: ScratchSpan<Double> = arena.uninitializedSpan(count: vertexCount)
        for vertex in 0..<vertexCount { gap[unchecked: vertex] = graph.halfRoom(of: vertex, options: options) }
        sortNeighbours(graph)
        let conflict = conflictingSegments(graph, arena: arena)
        // The four layouts one after the other, made with one set of working spans.
        let results = arena.span(count: 4 * vertexCount, repeating: 0.0)
        let work = LayeredPositioningWork(vertexCount: vertexCount, arena: arena)
        for variant in 0..<4 {
            let isRightward = variant & 1 == 1
            work.align(graph, conflict: conflict, isUpward: variant < 2, isRightward: isRightward)
            work.compact(graph, gap: gap, isRightward: isRightward, into: results, at: variant * vertexCount)
        }
        balanced(results, vertexCount: vertexCount, widths: graph.vertexWidth, into: across)
        return across
    }

    /// Neighbours in order across their rank, so that the medians can be read off directly. Each run's order is a total
    /// one (ties broken by segment), so any sort gives it.
    private static func sortNeighbours(_ graph: LayeredFlatGraph) {
        let position = graph.position
        let segmentTo = graph.segmentTo
        let segmentFrom = graph.segmentFrom
        for vertex in 0..<graph.vertexCount where graph.successorStart[vertex + 1] - graph.successorStart[vertex] > 1 {
            var run = graph.successorSegments.part(graph.successorStart[vertex]..<graph.successorStart[vertex + 1]).buffer
            run.sort { first, second in
                position[segmentTo[first]] != position[segmentTo[second]] ? position[segmentTo[first]] < position[segmentTo[second]] : first < second
            }
        }
        for vertex in 0..<graph.vertexCount where graph.predecessorStart[vertex + 1] - graph.predecessorStart[vertex] > 1 {
            var run = graph.predecessorSegments.part(graph.predecessorStart[vertex]..<graph.predecessorStart[vertex + 1]).buffer
            run.sort { first, second in
                position[segmentFrom[first]] != position[segmentFrom[second]] ? position[segmentFrom[first]] < position[segmentFrom[second]]
                    : first < second
            }
        }
    }

    /// The segments between two nodes, or a node and a bend, that cross a segment between two bends: an alignment
    /// along them would cross the long edge's inner segment.
    private static func conflictingSegments(_ graph: LayeredFlatGraph, arena: DiagramScratchArena) -> ScratchSpan<Bool> {
        let conflict = arena.span(count: graph.segmentCount, repeating: false)
        guard graph.maximumRank >= 1 else { return conflict }
        // The graph's spans read once: they live in the arena, where a store to `conflict` could be to them as far as
        // the compiler knows.
        let rankStart = graph.rankStart, order = graph.order, vertexKind = graph.vertexKind, positionInRank = graph.position
        let segmentFrom = graph.segmentFrom, predecessorStart = graph.predecessorStart, predecessorSegments = graph.predecessorSegments
        for rank in 1...graph.maximumRank {
            let previousLength = rankStart[rank] - rankStart[rank - 1]
            let start = rankStart[rank]
            let end = rankStart[rank + 1]
            var lowerBound = 0
            var scan = start
            for index in start..<end {
                let vertex = order[index]
                var inner = -1
                if vertexKind[vertex].isPassingPoint {
                    let upper = segmentFrom[predecessorSegments[predecessorStart[vertex]]]
                    if vertexKind[upper].isPassingPoint { inner = upper }
                }
                let upperBound = inner >= 0 ? positionInRank[inner] : previousLength
                guard inner >= 0 || index == end - 1 else { continue }
                for scanned in scan...index {
                    let lower = order[scanned]
                    let lowerIsPassing = vertexKind[lower].isPassingPoint
                    for position in predecessorStart[lower]..<predecessorStart[lower + 1] {
                        let segment = predecessorSegments[position]
                        let upperPosition = positionInRank[segmentFrom[segment]]
                        if (upperPosition < lowerBound || upperBound < upperPosition)
                            && !(lowerIsPassing && vertexKind[segmentFrom[segment]].isPassingPoint) { conflict[segment] = true }
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
    private static func balanced(_ results: ScratchSpan<Double>, vertexCount: Int, widths: ScratchSpan<Double>, into balanced: ScratchSpan<Double>) {
        precondition(vertexCount >= 0 && results.count == 4 * vertexCount && widths.count >= vertexCount && balanced.count >= vertexCount,
                     "Four layouts and a width and a place for every vertex")
        var narrowest = 0
        var bestWidth = Double.infinity
        var lows = SIMD4<Double>()
        var highs = SIMD4<Double>()
        for variant in 0..<4 {
            let base = variant * vertexCount
            var low = Double.infinity
            var high = -Double.infinity
            for vertex in 0..<vertexCount {
                low = min(low, results[unchecked: base + vertex] - widths[unchecked: vertex] / 2)
                high = max(high, results[unchecked: base + vertex] + widths[unchecked: vertex] / 2)
            }
            lows[variant] = low
            highs[variant] = high
            if high - low < bestWidth {
                bestWidth = high - low
                narrowest = variant
            }
        }
        for variant in 0..<4 {
            let delta = variant & 1 == 0 ? lows[narrowest] - lows[variant] : highs[narrowest] - highs[variant]
            if delta == 0 { continue }
            let base = variant * vertexCount
            for vertex in 0..<vertexCount { results[unchecked: base + vertex] = results[unchecked: base + vertex] + delta }
        }
        for vertex in 0..<vertexCount {
            let middle = middleTwo(results[unchecked: vertex], results[unchecked: vertexCount + vertex],
                                   results[unchecked: 2 * vertexCount + vertex], results[unchecked: 3 * vertexCount + vertex])
            balanced[unchecked: vertex] = (middle.second + middle.third) / 2
        }
    }

    /// The second and third of four values sorted as `Array.sorted()` sorts four: by insertion, each value swapped
    /// before the one ahead of it while it is less, so that equal values (zeros of either sign too) end where they would.
    static func middleTwo(_ first: Double, _ second: Double, _ third: Double, _ fourth: Double)
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
