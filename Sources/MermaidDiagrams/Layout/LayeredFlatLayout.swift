/**
 * File: LayeredFlatLayout.swift
 * -----------------------------
 * Layer: Core
 * Description: Pele's layered (Sugiyama) layout of one flat graph, ported step for step from layout/layered.ts.
 *
 * Authors: Bahey Shalash
 * Version: 0.5
 * Date: 25/11/2026
 */

import CoreGraphics

/// Pele's `layered` (layout/layered.ts): ranks run down the y axis, callers turn the result for other directions. The
/// edges that close cycles are turned around, the nodes ranked and balanced, every edge cut at each rank it passes,
/// the ranks ordered by sweeps and swaps, positioned by Brandes and Köpf's four alignments, the ends spread along their
/// sides and settled, the bends straightened, and the gaps sized to the levels and tracks of the edges that cross them.
/// Values only: the vertices are numbered, and each pass reads and writes spans of the calling thread's scratch arena
/// indexed by vertex or segment, so that a layout allocates nothing once the arena has room.
struct LayeredFlatLayout {
    let nodes: ScratchSpan<LayeredFlatNode>
    let edges: ScratchSpan<LayeredSpanEdge>
    /// Every edge's route, one after another (`LayeredSpanEdge.pointStart`).
    var points: ScratchList<CGPoint>
    let options: LayeredFlatOptions
    let arena: DiagramScratchArena
    /// 2 when every edge gets a middle rank of its own, for labels or parallel edges; else 1.
    let step: Int
    /// The ranks each edge passes, and whether it is drawn as one direct curve instead of through bends.
    var edgeRankSpan = ScratchSpan<Int>.empty
    var isDirect = ScratchSpan<Bool>.empty
    /// The first bend of each edge, the vertex of its label, and its first and last segments; -1 for none.
    var firstBend = ScratchSpan<Int>.empty
    var labelVertex = ScratchSpan<Int>.empty
    var firstSegment = ScratchSpan<Int>.empty
    var lastSegment = ScratchSpan<Int>.empty
    var vertexHeight = ScratchSpan<Double>.empty
    var vertexKey = ScratchSpan<Double>.empty
    /// Which way the labelled edges of each rank head: 1 down, 2 up, 3 both.
    var labelHeadings = ScratchSpan<UInt8>.empty
    /// What each segment's ends are to the nodes they meet, where nodes spread their ends; nil when none does.
    var segmentFromEnd: ScratchSpan<LayeredSegmentEnd>?
    var segmentToEnd: ScratchSpan<LayeredSegmentEnd>?

    /// Lays `nodes` and `edges` out in place, each edge's route appended to `points`, or returns nil when the nodes and
    /// bends would be more than `maximumVertexCount` (the nodes then ranked and the edges oriented, but neither placed).
    /// Every span the layout works in comes from `arena`, after `points`' room.
    static func layout(nodes: ScratchSpan<LayeredFlatNode>, edges: ScratchSpan<LayeredSpanEdge>, points: inout ScratchList<CGPoint>,
                       options: LayeredFlatOptions, maximumVertexCount: Int, arena: DiagramScratchArena) -> LayeredFlatResult? {
        #if DEBUG
        LayeredLayoutRecording.current?.flatLayouts.append(.init(nodes: Array(nodes), edges: edges.map(LayeredFlatEdge.init), options: options,
                                                                 maximumVertexCount: maximumVertexCount))
        #endif
        if nodes.isEmpty { return LayeredFlatResult(width: 0, height: 0) }
        if nodes.count == 1 && edges.isEmpty && nodes[0].kind == .node {
            nodes[0].rank = 0
            nodes[0].x = nodes[0].width / 2
            nodes[0].y = nodes[0].height / 2
            return LayeredFlatResult(width: nodes[0].width, height: nodes[0].height)
        }
        var layout = LayeredFlatLayout(nodes: nodes, edges: edges, points: points, options: options, arena: arena,
                                       step: stepOf(nodeCount: nodes.count, edges: edges, arena: arena))
        LayeredFlatRanking.orient(nodes: nodes, edges: edges, arena: arena)
        LayeredFlatRanking.rank(nodes: nodes, edges: edges, step: layout.step, arena: arena)
        let result = layout.run(maximumVertexCount: maximumVertexCount)
        points = layout.points
        return result
    }

    /// Lays `nodes` and `edges` out in place as `layout(nodes:edges:points:...)` does, with the calling thread's arena:
    /// each edge laid out gets its route as a list of its own. For compound layouts and tests.
    static func layout(nodes: inout [LayeredFlatNode], edges: inout [LayeredFlatEdge], options: LayeredFlatOptions,
                       maximumVertexCount: Int = .max) -> LayeredFlatResult? {
        DiagramScratchArena.withCurrentThread { arena in
            let nodeSpan: ScratchSpan<LayeredFlatNode> = arena.uninitializedSpan(count: nodes.count)
            for node in nodes.indices { nodeSpan[node] = nodes[node] }
            let edgeSpan: ScratchSpan<LayeredSpanEdge> = arena.uninitializedSpan(count: edges.count)
            for edgeIndex in edges.indices { edgeSpan[edgeIndex] = LayeredSpanEdge(edges[edgeIndex]) }
            var points = arena.list(capacity: 0, of: CGPoint.self)
            let result = layout(nodes: nodeSpan, edges: edgeSpan, points: &points, options: options, maximumVertexCount: maximumVertexCount,
                                arena: arena)
            for node in nodes.indices { nodes[node] = nodeSpan[node] }
            for edgeIndex in edges.indices {
                let laidOut = edgeSpan[edgeIndex]
                edges[edgeIndex].tailOffset = laidOut.tailOffset
                edges[edgeIndex].headOffset = laidOut.headOffset
                edges[edgeIndex].isReversed = laidOut.isReversed
                edges[edgeIndex].labelCenter = laidOut.labelCenter
                if laidOut.pointStart >= 0 {
                    edges[edgeIndex].points = Array(points.elements.part(laidOut.pointStart..<(laidOut.pointStart + laidOut.pointCount)))
                }
            }
            return result
        }
    }

    /// Every edge gets a middle rank of its own when an edge has a label or two edges join the same two nodes.
    private static func stepOf(nodeCount: Int, edges: ScratchSpan<LayeredSpanEdge>, arena: DiagramScratchArena) -> Int {
        if edges.contains(where: { edge in edge.labelWidth > 0 }) { return 2 }
        // Two edges join the same two nodes when their pairs, sorted, have two alike side by side.
        let mark = arena.mark()
        defer { arena.release(to: mark) }
        let pairs: ScratchSpan<Int> = arena.uninitializedSpan(count: edges.count)
        for edgeIndex in edges.indices {
            let edge = edges[edgeIndex]
            pairs[edgeIndex] = min(edge.tail, edge.head) * nodeCount + max(edge.tail, edge.head)
        }
        pairs.sortAscending()
        for index in pairs.indices.dropFirst() where pairs[index] == pairs[index - 1] { return 2 }
        return 1
    }

    private mutating func run(maximumVertexCount: Int) -> LayeredFlatResult? {
        let bendCount = chooseDirectEdges()
        let vertexCount = nodes.count + bendCount
        guard vertexCount <= maximumVertexCount else { return nil }
        let graph = buildGraph(vertexCount: vertexCount)
        var result = LayeredFlatResult(width: 0, height: 0)
        // A graph with no rank of two vertices has one order: its reduction would find no crossing and change nothing.
        if graph.segmentCount > 0 && graph.maximumRank > 0 && LayeredFlatCrossingReduction.widestRank(of: graph) >= 2 {
            // The reduction changes the graph's order in place; its own lists are given back when it is done.
            let mark = arena.mark()
            let reduction = LayeredFlatCrossingReduction(graph: graph, nodes: nodes, arena: arena)
            (result.crossings, result.declaredCrossings) = reduction.reduce()
            arena.release(to: mark)
            graph.settlePositions()
        }
        if options.ordersOnly {
            writeOrderPositions(graph: graph)
            return result
        }
        let placed = route(graph: graph)
        result.width = placed.width
        result.height = placed.height
        return result
    }

    /// Spans and bend counts; past `maximumBends` bends, the longest edges are drawn direct. Returns the bends left. An
    /// edge whose ends share a rank (only an edge from a node to itself, which callers lay out beside the node and Pele
    /// never hands its layout) is drawn direct too, so that every segment runs from one rank to the next.
    private mutating func chooseDirectEdges() -> Int {
        edgeRankSpan = arena.uninitializedSpan(count: edges.count)
        isDirect = arena.span(count: edges.count, repeating: false)
        var bendCount = 0
        for edgeIndex in edges.indices {
            let span = abs(nodes[edges[edgeIndex].head].rank - nodes[edges[edgeIndex].tail].rank)
            edgeRankSpan[edgeIndex] = span
            bendCount += max(0, span - 1)
            isDirect[edgeIndex] = span == 0
        }
        guard bendCount > LayeredFlatConstants.maximumBends else { return bendCount }
        var longest = arena.list(capacity: edges.count, of: Int.self)
        for edgeIndex in edges.indices where edgeRankSpan[edgeIndex] > 1 { longest.append(edgeIndex) }
        let edgeRankSpan = edgeRankSpan
        longest.sortStably(in: arena) { first, second in Double(edgeRankSpan[second] - edgeRankSpan[first]) < 0 }
        for edgeIndex in longest {
            if bendCount <= LayeredFlatConstants.maximumBends { break }
            isDirect[edgeIndex] = true
            bendCount -= edgeRankSpan[edgeIndex] - 1
        }
        return bendCount
    }

    /// With `ordersOnly`: each node's position across, and each edge's (rank, position) points.
    private mutating func writeOrderPositions(graph: LayeredFlatGraph) {
        let across = LayeredFlatPositioning.positions(graph, options: options, arena: arena)
        for node in nodes.indices { nodes[node].x = across[node] }
        for edgeIndex in edges.indices {
            let edge = edges[edgeIndex]
            let upper = edge.isReversed ? edge.head : edge.tail
            let lower = edge.isReversed ? edge.tail : edge.head
            edges[edgeIndex].pointStart = points.count
            points.append(CGPoint(x: Double(graph.vertexRank[upper]), y: across[upper]))
            if !isDirect[edgeIndex] && firstBend[edgeIndex] >= 0 {
                for bend in firstBend[edgeIndex]..<(firstBend[edgeIndex] + edgeRankSpan[edgeIndex] - 1) {
                    points.append(CGPoint(x: Double(graph.vertexRank[bend]), y: across[bend]))
                }
            }
            points.append(CGPoint(x: Double(graph.vertexRank[lower]), y: across[lower]))
            edges[edgeIndex].pointCount = points.count - edges[edgeIndex].pointStart
        }
    }
}
