/**
 * File: LayeredFlatPositioning.swift
 * ----------------------------------
 * Layer: Core
 * Description: Pele's positions across the flow: Brandes and Köpf's four aligned layouts, balanced (layered.ts position).
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 23/11/2026
 */

/// Pele's `position`: each vertex aligned with a median neighbour above or below, leftmost or rightmost first, every
/// block compacted against its neighbours, the four layouts shifted onto the narrowest and each vertex placed at the
/// mean of the middle two.
enum LayeredFlatPositioning {
    /// The working arrays of one of the four alignments.
    private struct Alignment {
        var root: [Int]
        var align: [Int]
        /// Offset of each vertex from its block's root, so that aligned edges meet at their attachment points.
        var shift: [Double]

        init(vertexCount: Int) {
            root = Array(0..<vertexCount)
            align = Array(0..<vertexCount)
            shift = [Double](repeating: 0, count: vertexCount)
        }
    }

    static func positions(_ graph: inout LayeredFlatGraph, options: LayeredFlatOptions) -> [Double] {
        let gap = (0..<graph.vertexCount).map { vertex in graph.halfRoom(of: vertex, options: options) }
        sortNeighbours(&graph)
        let conflict = conflictingSegments(graph)
        var results: [[Double]] = []
        for variant in 0..<4 {
            let isUpward = variant < 2
            let isRightward = variant & 1 == 1
            let alignment = aligned(graph, conflict: conflict, isUpward: isUpward, isRightward: isRightward)
            results.append(compacted(graph, root: alignment.root, shift: alignment.shift, gap: gap, isRightward: isRightward))
        }
        return balanced(results, widths: graph.vertexWidth)
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

    /// Aligns each vertex with its median neighbour above (upward) or below, sweeping each rank left to right or right to left.
    private static func aligned(_ graph: LayeredFlatGraph, conflict: [Bool], isUpward: Bool, isRightward: Bool) -> Alignment {
        var alignment = Alignment(vertexCount: graph.vertexCount)
        let starts = isUpward ? graph.predecessorStart : graph.successorStart
        let list = isUpward ? graph.predecessorSegments : graph.successorSegments
        let other = isUpward ? graph.segmentFrom : graph.segmentTo
        let ownOffset = isUpward ? graph.segmentToOffset : graph.segmentFromOffset
        let otherOffset = isUpward ? graph.segmentFromOffset : graph.segmentToOffset
        for step in 0...graph.maximumRank {
            let rank = isUpward ? step : graph.maximumRank - step
            let start = graph.rankStart[rank]
            let end = graph.rankStart[rank + 1]
            let adjacent = isUpward ? rank - 1 : rank + 1
            let adjacentLast = adjacent >= 0 && adjacent <= graph.maximumRank ? graph.rankStart[adjacent + 1] - graph.rankStart[adjacent] - 1 : 0
            var previousIndex = -1
            for offset in 0..<(end - start) {
                let vertex = graph.order[isRightward ? end - 1 - offset : start + offset]
                let from = starts[vertex]
                let degree = starts[vertex + 1] - from
                if degree == 0 { continue }
                let low = from + ((degree - 1) >> 1)
                let high = from + (degree >> 1)
                for pass in 0..<2 {
                    if pass == 1 && low == high { break }
                    let segment = list[(pass == 0) != isRightward ? low : high]
                    let neighbour = other[segment]
                    let index = isRightward ? adjacentLast - graph.position[neighbour] : graph.position[neighbour]
                    if alignment.align[vertex] == vertex && previousIndex < index && !conflict[segment] {
                        alignment.align[neighbour] = vertex
                        alignment.root[vertex] = alignment.root[neighbour]
                        alignment.align[vertex] = alignment.root[vertex]
                        alignment.shift[vertex] = alignment.shift[neighbour] + otherOffset[segment] - ownOffset[segment]
                        previousIndex = index
                    }
                }
            }
        }
        return alignment
    }
}
