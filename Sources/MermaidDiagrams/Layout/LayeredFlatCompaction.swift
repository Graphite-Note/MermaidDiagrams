/**
 * File: LayeredFlatCompaction.swift
 * ---------------------------------
 * Layer: Core
 * Description: Aligns and compacts the blocks of Brandes and Köpf's four alignments (layered.ts position), with one set
 *              of working spans of the scratch arena that the four reuse.
 *
 * Authors: Bahey Shalash
 * Version: 0.6
 * Date: 25/11/2026
 */

/// The working spans of one alignment and its compaction, taken once from the arena and refilled for each of the four.
/// Every index is a vertex, a block edge (at most one per vertex) or a place in a list of vertices, all below the vertex
/// count the spans were made for. A loop over every vertex reads the spans made as long unchecked; an index read from a
/// span is checked. Each pass reads the spans it uses into constants first: the graph's live in the arena, where a store
/// to another span could be to them as far as the compiler knows, so that it would read them again after every store.
struct LayeredPositioningWork {
    let vertexCount: Int
    /// Each vertex's block root and the vertex it is aligned to.
    let root: ScratchSpan<Int>
    let align: ScratchSpan<Int>
    /// Offset of each vertex from its block's root, so that aligned edges meet at their attachment points.
    let shift: ScratchSpan<Double>
    /// The blocks as a graph: an edge from each block to the next in every rank, as wide as the room the two vertices
    /// need, and each block's edges out. A rank of n vertices gives n - 1 edges: at most one edge per vertex.
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

    /// The spans are left as the arena hands them out: `align` sets the alignment (`resetAlignment` first) and
    /// `compact` builds the block graph and writes every value before it reads it.
    init(vertexCount: Int, arena: DiagramScratchArena) {
        self.vertexCount = vertexCount
        root = arena.uninitializedSpan(count: vertexCount)
        align = arena.uninitializedSpan(count: vertexCount)
        edgeFrom = arena.uninitializedSpan(count: vertexCount)
        edgeTo = arena.uninitializedSpan(count: vertexCount)
        remainingIn = arena.uninitializedSpan(count: vertexCount)
        outFill = arena.uninitializedSpan(count: vertexCount)
        outEdges = arena.uninitializedSpan(count: vertexCount)
        topological = arena.uninitializedSpan(count: vertexCount)
        outStart = arena.uninitializedSpan(count: vertexCount + 1)
        shift = arena.uninitializedSpan(count: vertexCount)
        edgeWidth = arena.uninitializedSpan(count: vertexCount)
        across = arena.uninitializedSpan(count: vertexCount)
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
        let root = root, align = align, shift = shift
        for vertex in 0..<vertexCount {
            root[unchecked: vertex] = vertex
            align[unchecked: vertex] = vertex
            shift[unchecked: vertex] = 0
        }
    }

    /// The positions of the present alignment, written to `results` from `base`: its block graph laid out longest path
    /// first, then each block pulled towards its successors.
    func compact(_ graph: LayeredFlatGraph, gap: ScratchSpan<Double>, isRightward: Bool, into results: ScratchSpan<Double>, at base: Int) {
        precondition(base >= 0 && results.count - base >= vertexCount, "Room for a layout of every vertex")
        buildBlockGraph(graph, gap: gap, isRightward: isRightward)
        let topologicalCount = layOutLongestPathFirst()
        let root = root, shift = shift, across = across, topological = topological
        let outStart = outStart, outEdges = outEdges, edgeTo = edgeTo, edgeWidth = edgeWidth
        for block in topological.part(0..<topologicalCount).reversed() {
            var least = Double.infinity
            for position in outStart[block]..<outStart[block + 1] {
                let edge = outEdges[position]
                least = min(least, across[edgeTo[edge]] - edgeWidth[edge])
            }
            if least != .infinity && least > across[block] { across[block] = least }
        }
        for vertex in 0..<vertexCount {
            let block = root[unchecked: vertex]
            results[unchecked: base + vertex] = (isRightward ? -across[block] : across[block]) + shift[unchecked: vertex]
        }
    }

    /// Each block as far across as its predecessors push it, the blocks visited in topological order, which
    /// `topological` keeps; returns how many blocks it holds.
    private func layOutLongestPathFirst() -> Int {
        let root = root, across = across, remainingIn = remainingIn, topological = topological
        let outStart = outStart, outEdges = outEdges, edgeTo = edgeTo, edgeWidth = edgeWidth
        var topologicalCount = 0
        for vertex in 0..<vertexCount {
            across[unchecked: vertex] = 0
            if root[unchecked: vertex] == vertex && remainingIn[unchecked: vertex] == 0 {
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
        return topologicalCount
    }

    /// The block graph of the present alignment: an edge from each block to the next in every rank.
    private func buildBlockGraph(_ graph: LayeredFlatGraph, gap: ScratchSpan<Double>, isRightward: Bool) {
        let root = root, shift = shift, remainingIn = remainingIn, outStart = outStart, outFill = outFill, outEdges = outEdges
        let edgeFrom = edgeFrom, edgeTo = edgeTo, edgeWidth = edgeWidth
        let rankStart = graph.rankStart, order = graph.order
        var edgeCount = 0
        for vertex in 0..<vertexCount { remainingIn[unchecked: vertex] = 0 }
        for vertex in 0...vertexCount { outStart[unchecked: vertex] = 0 }
        for rank in 0...graph.maximumRank {
            let end = rankStart[rank + 1]
            for index in (rankStart[rank] + 1)..<max(rankStart[rank] + 1, end) {
                let first = isRightward ? order[index] : order[index - 1]
                let second = isRightward ? order[index - 1] : order[index]
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
            outStart[unchecked: vertex + 1] += outStart[unchecked: vertex]
            outFill[unchecked: vertex] = outStart[unchecked: vertex]
        }
        for edge in 0..<edgeCount {
            outEdges[outFill[edgeFrom[edge]]] = edge
            outFill[edgeFrom[edge]] += 1
        }
    }
}
