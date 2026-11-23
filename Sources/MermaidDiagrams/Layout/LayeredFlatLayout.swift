/**
 * File: LayeredFlatLayout.swift
 * -----------------------------
 * Layer: Core
 * Description: Pele's layered (Sugiyama) layout of one flat graph, ported step for step from layout/layered.ts.
 *
 * Authors: Bahey Shalash
 * Version: 0.2
 * Date: 23/11/2026
 */

import CoreGraphics

/// Pele's `layered` (layout/layered.ts): ranks run down the y axis, callers turn the result for other directions. The
/// edges that close cycles are turned around, the nodes ranked and balanced, every edge cut at each rank it passes,
/// the ranks ordered by sweeps and swaps, positioned by Brandes and Köpf's four alignments, the ends spread along their
/// sides and settled, the bends straightened, and the gaps sized to the levels and tracks of the edges that cross them.
/// Values only: the vertices are numbered, and each pass reads and writes arrays indexed by vertex or segment.
struct LayeredFlatLayout {
    var nodes: [LayeredFlatNode]
    var edges: [LayeredFlatEdge]
    let options: LayeredFlatOptions
    /// 2 when every edge gets a middle rank of its own, for labels or parallel edges; else 1.
    let step: Int
    /// The ranks each edge passes, and whether it is drawn as one direct curve instead of through bends.
    var edgeRankSpan: [Int] = []
    var isDirect: [Bool] = []
    /// The first bend of each edge, the vertex of its label, and its first and last segments; -1 for none.
    var firstBend: [Int] = []
    var labelVertex: [Int] = []
    var firstSegment: [Int] = []
    var lastSegment: [Int] = []
    var vertexHeight: [Double] = []
    var vertexKey: [Double] = []
    /// Which way the labelled edges of each rank head: 1 down, 2 up, 3 both.
    var labelHeadings: [UInt8] = []
    /// What each segment's ends are to the nodes they meet, where nodes spread their ends; nil when none does.
    var segmentFromEnd: [LayeredSegmentEnd]?
    var segmentToEnd: [LayeredSegmentEnd]?

    /// Lays `nodes` and `edges` out in place, or returns nil when the nodes and bends would be more than
    /// `maximumVertexCount`.
    static func layout(nodes: inout [LayeredFlatNode], edges: inout [LayeredFlatEdge], options: LayeredFlatOptions,
                       maximumVertexCount: Int = .max) -> LayeredFlatResult? {
        if nodes.isEmpty { return LayeredFlatResult(width: 0, height: 0) }
        if nodes.count == 1 && edges.isEmpty && nodes[0].kind == .node {
            nodes[0].rank = 0
            nodes[0].x = nodes[0].width / 2
            nodes[0].y = nodes[0].height / 2
            return LayeredFlatResult(width: nodes[0].width, height: nodes[0].height)
        }
        var layout = LayeredFlatLayout(nodes: nodes, edges: edges, options: options, step: stepOf(nodeCount: nodes.count, edges: edges))
        LayeredFlatRanking.orient(nodes: layout.nodes, edges: &layout.edges)
        LayeredFlatRanking.rank(nodes: &layout.nodes, edges: layout.edges, step: layout.step)
        guard let result = layout.run(maximumVertexCount: maximumVertexCount) else { return nil }
        nodes = layout.nodes
        edges = layout.edges
        return result
    }

    /// Every edge gets a middle rank of its own when an edge has a label or two edges join the same two nodes.
    private static func stepOf(nodeCount: Int, edges: [LayeredFlatEdge]) -> Int {
        var seen = Set<Int>()
        for edge in edges {
            let key = min(edge.tail, edge.head) * nodeCount + max(edge.tail, edge.head)
            if edge.labelWidth > 0 || seen.contains(key) { return 2 }
            seen.insert(key)
        }
        return 1
    }

    private mutating func run(maximumVertexCount: Int) -> LayeredFlatResult? {
        let bendCount = chooseDirectEdges()
        let vertexCount = nodes.count + bendCount
        guard vertexCount <= maximumVertexCount else { return nil }
        var graph = buildGraph(vertexCount: vertexCount)
        var result = LayeredFlatResult(width: 0, height: 0)
        if graph.segmentCount > 0 && graph.maximumRank > 0 {
            // The graph moves into the reduction and back, so that its order is changed in place and never copied.
            var reduction = LayeredFlatCrossingReduction(graph: consume graph, nodes: nodes)
            (result.crossings, result.declaredCrossings) = reduction.reduce()
            graph = (consume reduction).graph
            graph.settlePositions()
        }
        if options.ordersOnly {
            writeOrderPositions(graph: &graph)
            return result
        }
        let placed = route(graph: &graph)
        result.width = placed.width
        result.height = placed.height
        return result
    }

    /// Spans and bend counts; past `maximumBends` bends, the longest edges are drawn direct. Returns the bends left. An
    /// edge whose ends share a rank (only an edge from a node to itself, which callers lay out beside the node and Pele
    /// never hands its layout) is drawn direct too, so that every segment runs from one rank to the next.
    private mutating func chooseDirectEdges() -> Int {
        edgeRankSpan = edges.map { edge in abs(nodes[edge.head].rank - nodes[edge.tail].rank) }
        var bendCount = edgeRankSpan.reduce(0) { total, span in total + max(0, span - 1) }
        isDirect = edgeRankSpan.map { span in span == 0 }
        guard bendCount > LayeredFlatConstants.maximumBends else { return bendCount }
        var longest = edges.indices.filter { edgeIndex in edgeRankSpan[edgeIndex] > 1 }
        longest.sortStably { first, second in Double(edgeRankSpan[second] - edgeRankSpan[first]) }
        for edgeIndex in longest {
            if bendCount <= LayeredFlatConstants.maximumBends { break }
            isDirect[edgeIndex] = true
            bendCount -= edgeRankSpan[edgeIndex] - 1
        }
        return bendCount
    }

    /// With `ordersOnly`: each node's position across, and each edge's (rank, position) points.
    private mutating func writeOrderPositions(graph: inout LayeredFlatGraph) {
        let across = LayeredFlatPositioning.positions(&graph, options: options)
        for node in nodes.indices { nodes[node].x = across[node] }
        for edgeIndex in edges.indices {
            let edge = edges[edgeIndex]
            let upper = edge.isReversed ? edge.head : edge.tail
            let lower = edge.isReversed ? edge.tail : edge.head
            var points = [CGPoint(x: Double(graph.vertexRank[upper]), y: across[upper])]
            if !isDirect[edgeIndex] && firstBend[edgeIndex] >= 0 {
                for bend in firstBend[edgeIndex]..<(firstBend[edgeIndex] + edgeRankSpan[edgeIndex] - 1) {
                    points.append(CGPoint(x: Double(graph.vertexRank[bend]), y: across[bend]))
                }
            }
            points.append(CGPoint(x: Double(graph.vertexRank[lower]), y: across[lower]))
            edges[edgeIndex].points = points
        }
    }
}
