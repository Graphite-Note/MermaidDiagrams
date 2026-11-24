/**
 * File: LayeredFlatCompaction.swift
 * ---------------------------------
 * Layer: Core
 * Description: Aligns and compacts the blocks of Brandes and Köpf's four alignments (layered.ts position), with one set
 *              of working spans of the scratch arena that the four reuse.
 *
 * Authors: Bahey Shalash
 * Version: 0.4
 * Date: 24/11/2026
 */

/// The working spans of one alignment and its compaction, taken once from the arena and refilled for each of the four.
/// Every index is a vertex, a block edge (at most one per vertex) or a place in a list of vertices, all below the vertex
/// count the spans were made for.
struct LayeredPositioningWork {
    let vertexCount: Int
    /// Each vertex's block root and the vertex it is aligned to.
    let root: ScratchSpan<Int>
    let align: ScratchSpan<Int>
    /// Offset of each vertex from its block's root, so that aligned edges meet at their attachment points.
    let shift: ScratchSpan<Double>
    /// The blocks as a graph: an edge from each block to the next in every rank, as wide as the room the two vertices
    /// need, and each block's edges out. A rank of n vertices gives n - 1 edges: at most one edge per vertex.
    private var edgeCount = 0
    private let edgeFrom: ScratchSpan<Int>
    private let edgeTo: ScratchSpan<Int>
    private let edgeWidth: ScratchSpan<Double>
    private let remainingIn: ScratchSpan<Int>
    /// Where each block's edges out start in `outEdges`, with the end of the last after them.
    private let outStart: ScratchSpan<Int>
    private let outFill: ScratchSpan<Int>
    private let outEdges: ScratchSpan<Int>
    private let across: ScratchSpan<Double>
    /// The blocks in topological order, each once.
    private let topological: ScratchSpan<Int>

    init(vertexCount: Int, arena: DiagramScratchArena) {
        self.vertexCount = vertexCount
        root = arena.span(count: vertexCount, repeating: 0)
        align = arena.span(count: vertexCount, repeating: 0)
        edgeFrom = arena.span(count: vertexCount, repeating: 0)
        edgeTo = arena.span(count: vertexCount, repeating: 0)
        remainingIn = arena.span(count: vertexCount, repeating: 0)
        outFill = arena.span(count: vertexCount, repeating: 0)
        outEdges = arena.span(count: vertexCount, repeating: 0)
        topological = arena.span(count: vertexCount, repeating: 0)
        outStart = arena.span(count: vertexCount + 1, repeating: 0)
        shift = arena.span(count: vertexCount, repeating: 0.0)
        edgeWidth = arena.span(count: vertexCount, repeating: 0.0)
        across = arena.span(count: vertexCount, repeating: 0.0)
    }

    /// Aligns each vertex with its median neighbour above (upward) or below, sweeping each rank left to right or right
    /// to left.
    func align(_ graph: LayeredFlatGraph, conflict: ScratchSpan<Bool>, isUpward: Bool, isRightward: Bool) {
        resetAlignment()
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
                    if align[vertex] == vertex && previousIndex < index && !conflict[segment] {
                        align[neighbour] = vertex
                        root[vertex] = root[neighbour]
                        align[vertex] = root[vertex]
                        shift[vertex] = shift[neighbour] + otherOffset[segment] - ownOffset[segment]
                        previousIndex = index
                    }
                }
            }
        }
    }

    /// Every vertex a block of its own.
    private func resetAlignment() {
        for vertex in 0..<vertexCount {
            root[vertex] = vertex
            align[vertex] = vertex
            shift[vertex] = 0
        }
    }

    /// The positions of the present alignment, written to `results` from `base`: its block graph laid out longest path
    /// first, then each block pulled towards its successors.
    mutating func compact(_ graph: LayeredFlatGraph, gap: ScratchSpan<Double>, isRightward: Bool, into results: ScratchSpan<Double>, at base: Int) {
        buildBlockGraph(graph, gap: gap, isRightward: isRightward)
        var topologicalCount = 0
        for vertex in 0..<vertexCount {
            across[vertex] = 0
            if root[vertex] == vertex && remainingIn[vertex] == 0 {
                topological[topologicalCount] = vertex
                topologicalCount += 1
            }
        }
        var queueIndex = 0
        while queueIndex < topologicalCount {
            let block = topological[queueIndex]
            queueIndex += 1
            for position in outStart[block]..<outStart[block + 1] {
                let edge = outEdges[position]
                let next = edgeTo[edge]
                if across[block] + edgeWidth[edge] > across[next] { across[next] = across[block] + edgeWidth[edge] }
                remainingIn[next] -= 1
                if remainingIn[next] == 0 {
                    topological[topologicalCount] = next
                    topologicalCount += 1
                }
            }
        }
        for block in topological.part(0..<topologicalCount).reversed() {
            var least = Double.infinity
            for position in outStart[block]..<outStart[block + 1] {
                let edge = outEdges[position]
                least = min(least, across[edgeTo[edge]] - edgeWidth[edge])
            }
            if least != .infinity && least > across[block] { across[block] = least }
        }
        for vertex in 0..<vertexCount {
            results[base + vertex] = (isRightward ? -across[root[vertex]] : across[root[vertex]]) + shift[vertex]
        }
    }

    /// The block graph of the present alignment: an edge from each block to the next in every rank.
    private mutating func buildBlockGraph(_ graph: LayeredFlatGraph, gap: ScratchSpan<Double>, isRightward: Bool) {
        edgeCount = 0
        for vertex in 0..<vertexCount { remainingIn[vertex] = 0 }
        for vertex in 0...vertexCount { outStart[vertex] = 0 }
        for rank in 0...graph.maximumRank {
            let end = graph.rankStart[rank + 1]
            for index in (graph.rankStart[rank] + 1)..<max(graph.rankStart[rank] + 1, end) {
                let first = isRightward ? graph.order[index] : graph.order[index - 1]
                let second = isRightward ? graph.order[index - 1] : graph.order[index]
                let separation = gap[first] + gap[second]
                edgeFrom[edgeCount] = root[first]
                edgeTo[edgeCount] = root[second]
                edgeWidth[edgeCount] = isRightward ? separation - shift[first] + shift[second] : separation + shift[first] - shift[second]
                edgeCount += 1
                remainingIn[root[second]] += 1
                outStart[root[first] + 1] += 1
            }
        }
        for vertex in 0..<vertexCount {
            outStart[vertex + 1] += outStart[vertex]
            outFill[vertex] = outStart[vertex]
        }
        for edge in 0..<edgeCount {
            outEdges[outFill[edgeFrom[edge]]] = edge
            outFill[edgeFrom[edge]] += 1
        }
    }
}
