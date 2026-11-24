/**
 * File: ReferenceLayeredFlatCompaction.swift
 * ------------------------------------------
 * Layer: Tests
 * Description: The 0.7.0 layered layout kept as the reference the span layout is checked against: aligns and compacts
 *              the blocks of Brandes and Köpf's four alignments (layered.ts position), with one set of working lists
 *              that the four reuse, held in two buffers.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 24/11/2026
 */

@testable import MermaidDiagrams

/// The working lists of one alignment and its compaction, made once and refilled for each of the four: every list of
/// integers is a part of one buffer and every list of positions a part of another, so that the four alignments cost two
/// allocations and their loops write without checks of uniqueness. Every index is a vertex, a block edge (at most one
/// per vertex) or a place in a list of vertices, all below the vertex count the buffers were made for.
final class ReferenceLayeredPositioningWork {
    private let integers: UnsafeMutableBufferPointer<Int>
    private let positions: UnsafeMutableBufferPointer<Double>
    let vertexCount: Int
    /// Each vertex's block root and the vertex it is aligned to.
    let root: UnsafeMutableBufferPointer<Int>
    let align: UnsafeMutableBufferPointer<Int>
    /// Offset of each vertex from its block's root, so that aligned edges meet at their attachment points.
    let shift: UnsafeMutableBufferPointer<Double>
    /// The blocks as a graph: an edge from each block to the next in every rank, as wide as the room the two vertices
    /// need, and each block's edges out. A rank of n vertices gives n - 1 edges: at most one edge per vertex.
    private var edgeCount = 0
    private let edgeFrom: UnsafeMutableBufferPointer<Int>
    private let edgeTo: UnsafeMutableBufferPointer<Int>
    private let edgeWidth: UnsafeMutableBufferPointer<Double>
    private let remainingIn: UnsafeMutableBufferPointer<Int>
    /// Where each block's edges out start in `outEdges`, with the end of the last after them.
    private let outStart: UnsafeMutableBufferPointer<Int>
    private let outFill: UnsafeMutableBufferPointer<Int>
    private let outEdges: UnsafeMutableBufferPointer<Int>
    private let across: UnsafeMutableBufferPointer<Double>
    /// The blocks in topological order, each once.
    private let topological: UnsafeMutableBufferPointer<Int>

    init(vertexCount: Int) {
        self.vertexCount = vertexCount
        let integers = UnsafeMutableBufferPointer<Int>.allocate(capacity: 9 * vertexCount + 1)
        integers.initialize(repeating: 0)
        let positions = UnsafeMutableBufferPointer<Double>.allocate(capacity: 3 * vertexCount)
        positions.initialize(repeating: 0)
        func integerList(_ index: Int, extra: Int = 0) -> UnsafeMutableBufferPointer<Int> {
            UnsafeMutableBufferPointer(rebasing: integers[(index * vertexCount)..<((index + 1) * vertexCount + extra)])
        }
        func positionList(_ index: Int) -> UnsafeMutableBufferPointer<Double> {
            UnsafeMutableBufferPointer(rebasing: positions[(index * vertexCount)..<((index + 1) * vertexCount)])
        }
        self.integers = integers
        self.positions = positions
        root = integerList(0)
        align = integerList(1)
        edgeFrom = integerList(2)
        edgeTo = integerList(3)
        remainingIn = integerList(4)
        outFill = integerList(5)
        outEdges = integerList(6)
        topological = integerList(7)
        outStart = integerList(8, extra: 1)
        shift = positionList(0)
        edgeWidth = positionList(1)
        across = positionList(2)
    }

    deinit {
        integers.deallocate()
        positions.deallocate()
    }

    /// Aligns each vertex with its median neighbour above (upward) or below, sweeping each rank left to right or right
    /// to left.
    func align(_ graph: ReferenceLayeredFlatGraph, conflict: [Bool], isUpward: Bool, isRightward: Bool) {
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
    func compact(_ graph: ReferenceLayeredFlatGraph, gap: [Double], isRightward: Bool, into results: inout [Double], at base: Int) {
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
        for block in topological[0..<topologicalCount].reversed() {
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
    private func buildBlockGraph(_ graph: ReferenceLayeredFlatGraph, gap: [Double], isRightward: Bool) {
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
