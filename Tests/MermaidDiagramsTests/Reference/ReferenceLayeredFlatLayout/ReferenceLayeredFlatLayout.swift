/**
 * File: ReferenceLayeredFlatLayout.swift
 * --------------------------------------
 * Layer: Tests
 * Description: The 0.7.0 layered layout kept as the reference the span layout is checked against: pele's layered
 *              (Sugiyama) layout of one flat graph, ported step for step from layout/layered.ts.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 24/11/2026
 */

import CoreGraphics
@testable import MermaidDiagrams

/// Pele's `layered` (layout/layered.ts): ranks run down the y axis, callers turn the result for other directions. The
/// edges that close cycles are turned around, the nodes ranked and balanced, every edge cut at each rank it passes,
/// the ranks ordered by sweeps and swaps, positioned by Brandes and Köpf's four alignments, the ends spread along their
/// sides and settled, the bends straightened, and the gaps sized to the levels and tracks of the edges that cross them.
/// Values only: the vertices are numbered, and each pass reads and writes arrays indexed by vertex or segment.
struct ReferenceLayeredFlatLayout {
    var nodes: [LayeredFlatNode]
    var edges: [LayeredFlatEdge]
    let options: LayeredFlatOptions
    /// The working lists, shared with the other flat layouts of one compound layout.
    let workspace: ReferenceLayeredFlatWorkspace
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
    /// `maximumVertexCount` (the nodes then ranked and the edges oriented, but neither placed). The working lists come
    /// from `workspace`, which a compound layout hands to each of its flat layouts, and go back to it; without one, the
    /// layout makes its own.
    static func layout(nodes: inout [LayeredFlatNode], edges: inout [LayeredFlatEdge], options: LayeredFlatOptions,
                       maximumVertexCount: Int = .max, workspace givenWorkspace: ReferenceLayeredFlatWorkspace? = nil) -> LayeredFlatResult? {
        if nodes.isEmpty { return LayeredFlatResult(width: 0, height: 0) }
        if nodes.count == 1 && edges.isEmpty && nodes[0].kind == .node {
            nodes[0].rank = 0
            nodes[0].x = nodes[0].width / 2
            nodes[0].y = nodes[0].height / 2
            return LayeredFlatResult(width: nodes[0].width, height: nodes[0].height)
        }
        let workspace = givenWorkspace ?? ReferenceLayeredFlatWorkspace()
        var layout = ReferenceLayeredFlatLayout(nodes: [], edges: [], options: options, workspace: workspace,
                                       step: stepOf(nodeCount: nodes.count, edges: edges, workspace: workspace))
        // The lists move into the layout and back, so that ranking and routing change them in place, never copied.
        swap(&layout.nodes, &nodes)
        swap(&layout.edges, &edges)
        ReferenceLayeredFlatRanking.orient(nodes: layout.nodes, edges: &layout.edges, workspace: workspace)
        ReferenceLayeredFlatRanking.rank(nodes: &layout.nodes, edges: layout.edges, step: layout.step, workspace: workspace)
        let result = layout.run(maximumVertexCount: maximumVertexCount)
        swap(&layout.nodes, &nodes)
        swap(&layout.edges, &edges)
        layout.recycleLists()
        return result
    }

    /// Gives the layout's own lists back to its workspace.
    private consuming func recycleLists() {
        workspace.recycle(edgeRankSpan)
        workspace.recycle(isDirect)
        workspace.recycle(firstBend)
        workspace.recycle(labelVertex)
        workspace.recycle(firstSegment)
        workspace.recycle(lastSegment)
        workspace.recycle(vertexHeight)
        workspace.recycle(vertexKey)
        if let segmentFromEnd { workspace.recycle(consume segmentFromEnd) }
        if let segmentToEnd { workspace.recycle(consume segmentToEnd) }
    }

    /// Every edge gets a middle rank of its own when an edge has a label or two edges join the same two nodes.
    private static func stepOf(nodeCount: Int, edges: [LayeredFlatEdge], workspace: ReferenceLayeredFlatWorkspace) -> Int {
        if edges.contains(where: { edge in edge.labelWidth > 0 }) { return 2 }
        // Two edges join the same two nodes when their pairs, sorted, have two alike side by side.
        var pairs = workspace.emptyIntegers(capacity: edges.count)
        for edge in edges { pairs.append(min(edge.tail, edge.head) * nodeCount + max(edge.tail, edge.head)) }
        pairs.sort()
        var step = 1
        for index in pairs.indices.dropFirst() where pairs[index] == pairs[index - 1] {
            step = 2
            break
        }
        workspace.recycle(consume pairs)
        return step
    }

    private mutating func run(maximumVertexCount: Int) -> LayeredFlatResult? {
        let bendCount = chooseDirectEdges()
        let vertexCount = nodes.count + bendCount
        guard vertexCount <= maximumVertexCount else { return nil }
        var graph = buildGraph(vertexCount: vertexCount)
        var result = LayeredFlatResult(width: 0, height: 0)
        // A graph with no rank of two vertices has one order: its reduction would find no crossing and change nothing.
        if graph.segmentCount > 0 && graph.maximumRank > 0 && ReferenceLayeredFlatCrossingReduction.widestRank(of: graph) >= 2 {
            // The graph moves into the reduction and back, so that its order is changed in place and never copied.
            var reduction = ReferenceLayeredFlatCrossingReduction(graph: consume graph, nodes: nodes, workspace: workspace)
            (result.crossings, result.declaredCrossings) = reduction.reduce()
            graph = (consume reduction).finished()
            graph.settlePositions()
        }
        if options.ordersOnly {
            writeOrderPositions(graph: &graph)
            graph.recycle(into: workspace)
            return result
        }
        let placed = route(graph: &graph)
        result.width = placed.width
        result.height = placed.height
        graph.recycle(into: workspace)
        return result
    }

    /// Spans and bend counts; past `maximumBends` bends, the longest edges are drawn direct. Returns the bends left. An
    /// edge whose ends share a rank (only an edge from a node to itself, which callers lay out beside the node and Pele
    /// never hands its layout) is drawn direct too, so that every segment runs from one rank to the next.
    private mutating func chooseDirectEdges() -> Int {
        edgeRankSpan = workspace.emptyIntegers(capacity: edges.count)
        isDirect = workspace.flags(count: edges.count, repeating: false)
        var bendCount = 0
        for edgeIndex in edges.indices {
            let span = abs(nodes[edges[edgeIndex].head].rank - nodes[edges[edgeIndex].tail].rank)
            edgeRankSpan.append(span)
            bendCount += max(0, span - 1)
            isDirect[edgeIndex] = span == 0
        }
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
    private mutating func writeOrderPositions(graph: inout ReferenceLayeredFlatGraph) {
        let across = ReferenceLayeredFlatPositioning.positions(&graph, options: options, workspace: workspace)
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
        workspace.recycle(consume across)
    }
}
