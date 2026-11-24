/**
 * File: ReferenceLayeredFlatGraphBuilding.swift
 * ---------------------------------------------
 * Layer: Tests
 * Description: The 0.7.0 layered layout kept as the reference the span layout is checked against: cuts the edges of
 *              Pele's layered layout into segments and gives every rank its first order.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 24/11/2026
 */

@testable import MermaidDiagrams

/// The vertices and segments a layout is ordered on, built as layout/layered.ts builds them.
private struct ReferenceLayeredSegmentList {
    var from: [Int] = []
    var to: [Int] = []
    var fromOffset: [Double] = []
    var toOffset: [Double] = []
    var fromEnd: [LayeredSegmentEnd] = []
    var toEnd: [LayeredSegmentEnd] = []
    var hasOffsets = false

    /// Empty lists from `workspace` with room for `count` segments each.
    init(capacity count: Int, workspace: ReferenceLayeredFlatWorkspace) {
        from = workspace.emptyIntegers(capacity: count)
        to = workspace.emptyIntegers(capacity: count)
        fromOffset = workspace.emptyNumbers(capacity: count)
        toOffset = workspace.emptyNumbers(capacity: count)
        fromEnd = workspace.emptyEnds(capacity: count)
        toEnd = workspace.emptyEnds(capacity: count)
    }

    mutating func append(from upper: Int, to lower: Int, fromOffset: Double, toOffset: Double,
                         fromEnd: LayeredSegmentEnd = .held, toEnd: LayeredSegmentEnd = .held) {
        from.append(upper)
        to.append(lower)
        self.fromOffset.append(fromOffset)
        self.toOffset.append(toOffset)
        self.fromEnd.append(fromEnd)
        self.toEnd.append(toEnd)
    }
}

extension ReferenceLayeredFlatLayout {
    mutating func buildGraph(vertexCount: Int) -> ReferenceLayeredFlatGraph {
        let nodeCount = nodes.count
        var maximumRank = 0
        for node in nodes { maximumRank = max(maximumRank, node.rank) }
        var widths = workspace.numbers(count: vertexCount, repeating: 0)
        vertexHeight = workspace.numbers(count: vertexCount, repeating: 0)
        var kinds = workspace.kinds(count: vertexCount, repeating: .bend)
        var ranks = workspace.integers(count: vertexCount, repeating: 0)
        for node in 0..<nodeCount {
            widths[node] = nodes[node].width
            vertexHeight[node] = nodes[node].height
            kinds[node] = nodes[node].kind
            ranks[node] = nodes[node].rank
        }
        labelHeadings = [UInt8](repeating: 0, count: maximumRank + 1)
        let spreads = nodes.contains { node in node.sideSpan > 0 && node.kind == .node }
        vertexKey = workspace.numbers(count: vertexCount, repeating: .nan)
        for node in 0..<nodeCount { vertexKey[node] = nodes[node].orderKey }
        let segments = cutEdges(widths: &widths, kinds: &kinds, ranks: &ranks, spreads: spreads)
        let groups = vertexGroups(vertexCount: vertexCount)
        let adjacency = ReferenceLayeredFlatGraph.adjacency(vertexCount: vertexCount, segmentFrom: segments.from, segmentTo: segments.to,
                                                   workspace: workspace)
        let rankStart = ReferenceLayeredFlatGraph.rankStarts(vertexRank: ranks, maximumRank: maximumRank, workspace: workspace)
        var graph = ReferenceLayeredFlatGraph(vertexCount: vertexCount, nodeCount: nodeCount, maximumRank: maximumRank, vertexWidth: widths,
                                     vertexKind: kinds, vertexRank: ranks, segmentFrom: segments.from, segmentTo: segments.to,
                                     segmentFromOffset: segments.fromOffset, segmentToOffset: segments.toOffset,
                                     successorStart: adjacency.successorStart, successorSegments: adjacency.successorSegments,
                                     predecessorStart: adjacency.predecessorStart, predecessorSegments: adjacency.predecessorSegments,
                                     rankStart: rankStart, order: workspace.integers(count: vertexCount, repeating: 0),
                                     position: workspace.integers(count: vertexCount, repeating: 0), hasOffsets: segments.hasOffsets,
                                     isRankFixed: workspace.flags(count: maximumRank + 1, repeating: false), vertexGroup: groups,
                                     parentOfGroup: options.parentOfGroup)
        orderInitially(&graph)
        return graph
    }

    /// The rank of an edge's label: halfway along; for an edge that passes ranks of nodes, in one of those beside the
    /// nodes, the one nearer the node it starts from; between two neighbouring ranks, in the rank between them.
    private func labelRank(upperRank: Int, lowerRank: Int, isReversed: Bool) -> Int {
        var rank = upperRank + ((lowerRank - upperRank) >> 1)
        if step == 2 && lowerRank - upperRank >= 4 {
            if rank & 1 == 1 { rank += isReversed ? 1 : -1 }
        } else if step == 2 && rank & 1 == 0 {
            rank += isReversed ? 1 : -1
        }
        return rank
    }

    /// Every edge not drawn direct cut into segments, one per rank it passes, with a bend or its label in each rank
    /// between its ends.
    private mutating func cutEdges(widths: inout [Double], kinds: inout [LayeredVertexKind], ranks: inout [Int], spreads: Bool) -> ReferenceLayeredSegmentList {
        firstBend = workspace.integers(count: edges.count, repeating: -1)
        labelVertex = workspace.integers(count: edges.count, repeating: -1)
        firstSegment = workspace.integers(count: edges.count, repeating: -1)
        lastSegment = workspace.integers(count: edges.count, repeating: -1)
        // An edge cut into n bends makes n + 1 segments: the bends are the vertices past the nodes.
        var segments = ReferenceLayeredSegmentList(capacity: max(0, widths.count - nodes.count) + edges.count, workspace: workspace)
        var nextVertex = nodes.count
        for edgeIndex in edges.indices where !isDirect[edgeIndex] {
            cutEdge(edgeIndex, into: &segments, nextVertex: &nextVertex, widths: &widths, kinds: &kinds, ranks: &ranks)
        }
        if spreads {
            segmentFromEnd = segments.fromEnd
            segmentToEnd = segments.toEnd
        } else {
            workspace.recycle(segments.fromEnd)
            workspace.recycle(segments.toEnd)
            segmentFromEnd = nil
            segmentToEnd = nil
        }
        segments.fromEnd = []
        segments.toEnd = []
        return segments
    }

    /// One edge cut into a segment per rank it passes, with a bend or its label in each rank between its ends.
    private mutating func cutEdge(_ edgeIndex: Int, into segments: inout ReferenceLayeredSegmentList, nextVertex: inout Int, widths: inout [Double],
                                  kinds: inout [LayeredVertexKind], ranks: inout [Int]) {
        let edge = edges[edgeIndex]
        let upper = edge.isReversed ? edge.head : edge.tail
        let lower = edge.isReversed ? edge.tail : edge.head
        let upperOffset = edge.isReversed ? edge.headOffset : edge.tailOffset
        let lowerOffset = edge.isReversed ? edge.tailOffset : edge.headOffset
        if upperOffset != 0 || lowerOffset != 0 { segments.hasOffsets = true }
        let upperRank = ranks[upper]
        let lowerRank = ranks[lower]
        let rankOfLabel = edge.labelWidth > 0 ? labelRank(upperRank: upperRank, lowerRank: lowerRank, isReversed: edge.isReversed) : -1
        if lowerRank - upperRank > 1 { firstBend[edgeIndex] = nextVertex }
        firstSegment[edgeIndex] = segments.from.count
        let firstEnd: LayeredSegmentEnd = edge.isReversed ? (edge.isHeadHeld ? .held : .arrives) : (edge.isTailHeld ? .held : .leaves)
        let lastEnd: LayeredSegmentEnd = edge.isReversed ? (edge.isTailHeld ? .held : .leaves) : (edge.isHeadHeld ? .held : .arrives)
        var previous = upper
        for rank in (upperRank + 1)..<max(upperRank + 1, lowerRank) {
            let bend = nextVertex
            nextVertex += 1
            ranks[bend] = rank
            vertexKey[bend] = vertexKey[upper] + (vertexKey[lower] - vertexKey[upper]) * Double(rank - upperRank) / Double(lowerRank - upperRank)
            if rank == rankOfLabel {
                widths[bend] = edge.labelWidth
                vertexHeight[bend] = edge.labelHeight
                kinds[bend] = .label
                labelVertex[edgeIndex] = bend
                labelHeadings[rank] |= edge.isReversed ? 2 : 1
            }
            segments.append(from: previous, to: bend, fromOffset: previous == upper ? upperOffset : 0, toOffset: 0,
                            fromEnd: previous == upper ? firstEnd : .held)
            previous = bend
        }
        lastSegment[edgeIndex] = segments.from.count
        segments.append(from: previous, to: lower, fromOffset: previous == upper ? upperOffset : 0, toOffset: lowerOffset,
                        fromEnd: previous == upper ? firstEnd : .held, toEnd: lastEnd)
    }

    /// The innermost group of every vertex: a node's own, and a bend's the innermost holding both its edge's ends.
    private func vertexGroups(vertexCount: Int) -> [Int]? {
        guard let groupOfNode = options.groupOfNode else { return nil }
        let parent = options.parentOfGroup
        var groups = workspace.integers(count: vertexCount, repeating: -1)
        for node in nodes.indices { groups[node] = groupOfNode[node] }
        func depth(_ group: Int) -> Int {
            var depth = 0
            var group = group
            while group >= 0 { depth += 1; group = parent[group] }
            return depth
        }
        func commonGroup(_ first: Int, _ second: Int) -> Int {
            var first = first, second = second
            var firstDepth = depth(first), secondDepth = depth(second)
            while firstDepth > secondDepth { first = parent[first]; firstDepth -= 1 }
            while secondDepth > firstDepth { second = parent[second]; secondDepth -= 1 }
            while first != second { first = parent[first]; second = parent[second] }
            return first
        }
        for edgeIndex in edges.indices where firstBend[edgeIndex] >= 0 {
            let group = commonGroup(groupOfNode[edges[edgeIndex].tail], groupOfNode[edges[edgeIndex].head])
            for bend in firstBend[edgeIndex]..<(firstBend[edgeIndex] + edgeRankSpan[edgeIndex] - 1) { groups[bend] = group }
        }
        return groups
    }
}
