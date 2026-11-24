/**
 * File: LayeredFlatGraphBuilding.swift
 * ------------------------------------
 * Layer: Core
 * Description: Cuts the edges of Pele's layered layout into segments and gives every rank its first order.
 *
 * Authors: Bahey Shalash
 * Version: 0.4
 * Date: 24/11/2026
 */

/// The vertices and segments a layout is ordered on, built as layout/layered.ts builds them.
private struct LayeredSegmentList {
    var from: ScratchList<Int>
    var to: ScratchList<Int>
    var fromOffset: ScratchList<Double>
    var toOffset: ScratchList<Double>
    var fromEnd: ScratchList<LayeredSegmentEnd>
    var toEnd: ScratchList<LayeredSegmentEnd>
    var hasOffsets = false

    /// Empty lists from `arena` with room for `count` segments each.
    init(capacity count: Int, arena: DiagramScratchArena) {
        from = arena.list(capacity: count, of: Int.self)
        to = arena.list(capacity: count, of: Int.self)
        fromOffset = arena.list(capacity: count, of: Double.self)
        toOffset = arena.list(capacity: count, of: Double.self)
        fromEnd = arena.list(capacity: count, of: LayeredSegmentEnd.self)
        toEnd = arena.list(capacity: count, of: LayeredSegmentEnd.self)
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

extension LayeredFlatLayout {
    mutating func buildGraph(vertexCount: Int) -> LayeredFlatGraph {
        let nodeCount = nodes.count
        var maximumRank = 0
        for node in nodes { maximumRank = max(maximumRank, node.rank) }
        let widths = arena.span(count: vertexCount, repeating: 0.0)
        vertexHeight = arena.span(count: vertexCount, repeating: 0)
        let kinds = arena.span(count: vertexCount, repeating: LayeredVertexKind.bend)
        let ranks = arena.span(count: vertexCount, repeating: 0)
        for node in 0..<nodeCount {
            widths[node] = nodes[node].width
            vertexHeight[node] = nodes[node].height
            kinds[node] = nodes[node].kind
            ranks[node] = nodes[node].rank
        }
        labelHeadings = arena.span(count: maximumRank + 1, repeating: 0)
        let spreads = nodes.contains { node in node.sideSpan > 0 && node.kind == .node }
        vertexKey = arena.span(count: vertexCount, repeating: .nan)
        for node in 0..<nodeCount { vertexKey[node] = nodes[node].orderKey }
        let segments = cutEdges(widths: widths, kinds: kinds, ranks: ranks, spreads: spreads)
        let groups = vertexGroups(vertexCount: vertexCount)
        let segmentFrom = segments.from.elements
        let segmentTo = segments.to.elements
        let adjacency = LayeredFlatGraph.adjacency(vertexCount: vertexCount, segmentFrom: segmentFrom, segmentTo: segmentTo, arena: arena)
        let rankStart = LayeredFlatGraph.rankStarts(vertexRank: ranks, maximumRank: maximumRank, arena: arena)
        let graph = LayeredFlatGraph(vertexCount: vertexCount, nodeCount: nodeCount, maximumRank: maximumRank, segmentCount: segmentFrom.count,
                                     vertexWidth: widths, vertexKind: kinds, vertexRank: ranks, segmentFrom: segmentFrom, segmentTo: segmentTo,
                                     segmentFromOffset: segments.fromOffset.elements, segmentToOffset: segments.toOffset.elements,
                                     successorStart: adjacency.successorStart, successorSegments: adjacency.successorSegments,
                                     predecessorStart: adjacency.predecessorStart, predecessorSegments: adjacency.predecessorSegments,
                                     rankStart: rankStart, order: arena.span(count: vertexCount, repeating: 0),
                                     position: arena.span(count: vertexCount, repeating: 0), hasOffsets: segments.hasOffsets,
                                     isRankFixed: arena.span(count: maximumRank + 1, repeating: false), vertexGroup: groups,
                                     parentOfGroup: groupParents())
        orderInitially(graph)
        return graph
    }

    /// The parent of each group, in a span.
    private func groupParents() -> ScratchSpan<Int> {
        let parents: ScratchSpan<Int> = arena.uninitializedSpan(count: options.parentOfGroup.count)
        for group in options.parentOfGroup.indices { parents[group] = options.parentOfGroup[group] }
        return parents
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
    private mutating func cutEdges(widths: ScratchSpan<Double>, kinds: ScratchSpan<LayeredVertexKind>, ranks: ScratchSpan<Int>,
                                   spreads: Bool) -> LayeredSegmentList {
        firstBend = arena.span(count: edges.count, repeating: -1)
        labelVertex = arena.span(count: edges.count, repeating: -1)
        firstSegment = arena.span(count: edges.count, repeating: -1)
        lastSegment = arena.span(count: edges.count, repeating: -1)
        // An edge cut into n bends makes n + 1 segments: the bends are the vertices past the nodes.
        var segments = LayeredSegmentList(capacity: max(0, widths.count - nodes.count) + edges.count, arena: arena)
        var nextVertex = nodes.count
        for edgeIndex in edges.indices where !isDirect[edgeIndex] {
            cutEdge(edgeIndex, into: &segments, nextVertex: &nextVertex, widths: widths, kinds: kinds, ranks: ranks)
        }
        segmentFromEnd = spreads ? segments.fromEnd.elements : nil
        segmentToEnd = spreads ? segments.toEnd.elements : nil
        return segments
    }

    /// One edge cut into a segment per rank it passes, with a bend or its label in each rank between its ends.
    private func cutEdge(_ edgeIndex: Int, into segments: inout LayeredSegmentList, nextVertex: inout Int, widths: ScratchSpan<Double>,
                         kinds: ScratchSpan<LayeredVertexKind>, ranks: ScratchSpan<Int>) {
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
    private func vertexGroups(vertexCount: Int) -> ScratchSpan<Int>? {
        guard let groupOfNode = options.groupOfNode else { return nil }
        let parent = options.parentOfGroup
        let groups = arena.span(count: vertexCount, repeating: -1)
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
