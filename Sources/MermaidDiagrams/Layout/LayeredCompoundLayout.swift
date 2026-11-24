/**
 * File: LayeredCompoundLayout.swift
 * ---------------------------------
 * Layer: Core
 * Description: Pele's compound layout of a graph in nested groups, ported step for step from layout/compound.ts, its
 *              levels, ports, routes and keys in the calling thread's scratch arena.
 *
 * Authors: Bahey Shalash
 * Version: 0.4
 * Date: 24/11/2026
 */

import CoreGraphics

/// Pele's `compoundLayout` (layout/compound.ts): each group is laid out on its own, in its own direction, by the flat
/// layered layout, then placed in its parent as one box; an edge that crosses a group's border passes through a port on
/// the side facing its other end. A flat layout of every node first keys the orders of all groups alike, and the port
/// order is refined from the routes outside each group, each kept only when its routes cross less. Every list is a span
/// or a growing list of the arena: the levels' items, edges and ports are ranges of one list each, an edge end's ports
/// are chained level to level, and every route is a range of one list of route points that only grows, so that a
/// snapshot is a copy of the nodes', edges' and ports' plain values.
struct LayeredCompoundLayout {
    let nodes: ScratchSpan<LayeredCompoundNode>
    let edges: ScratchSpan<LayeredCompoundSpanEdge>
    let options: LayeredFlatOptions
    let rootDirection: LayeredDirection
    let maximumVertexCount: Int
    /// The levels in breadth-first order, the top level first, and what they hold: items, edges and ports, each level's
    /// a range of these.
    var levels: ScratchList<LayeredCompoundLevel>
    var levelItems: ScratchSpan<Int> = .empty
    var levelEdges: ScratchSpan<LayeredCompoundLevelEdge> = .empty
    var ports: ScratchSpan<LayeredCompoundPort> = .empty
    /// The first port of each edge end (`edge * 2` leaving, `edge * 2 + 1` arriving), -1 for none.
    var firstPortOfEdgeEnd: ScratchSpan<Int> = .empty
    /// The level of each group by node (-1 for none).
    let levelOfGroup: ScratchSpan<Int>
    let depth: ScratchSpan<Int>
    /// Each item's index in the level being built.
    let local: ScratchSpan<Int>
    let key: ScratchSpan<Double>
    var isKeyed = false
    var isOrdered = false
    var flatCrossings = 0
    /// From the flat layout: each edge's flat edge (-1 for none), the flat edges' (rank, position) points as ranges of
    /// one list, and the last flat rank each group occupies.
    var flatEdgeOf: ScratchSpan<Int> = .empty
    var flatEdgePointRanges: ScratchSpan<LayeredIndexRange> = .empty
    var flatEdgePoints: ScratchSpan<CGPoint> = .empty
    var lastFlatRank: ScratchSpan<Int> = .empty
    var hasFarHint = false
    var total = (width: 0.0, height: 0.0)
    var loops: ScratchList<Int>
    var strays: ScratchList<Int>
    /// Every route written, edges', level edges' and ports', each a range of this list. It is the one list outside the
    /// arena: it grows while each level is laid out, within the arena memory that level gives back.
    var routePoints: [LayeredRoutePoint] = []
    /// The calling thread's arena, for every list and the levels' flat graphs and layouts.
    let arena: DiagramScratchArena

    init(nodes: ScratchSpan<LayeredCompoundNode>, edges: ScratchSpan<LayeredCompoundSpanEdge>, rootDirection: LayeredDirection,
         options: LayeredFlatOptions, maximumVertexCount: Int, arena: DiagramScratchArena) {
        self.arena = arena
        self.nodes = nodes
        self.edges = edges
        self.options = options
        self.rootDirection = rootDirection
        self.maximumVertexCount = maximumVertexCount
        levels = arena.list(capacity: 4, of: LayeredCompoundLevel.self)
        levelOfGroup = arena.span(count: nodes.count, repeating: -1)
        depth = arena.span(count: nodes.count, repeating: 0)
        local = arena.span(count: nodes.count, repeating: 0)
        key = arena.span(count: nodes.count, repeating: .nan)
        loops = arena.list(capacity: 0, of: Int.self)
        strays = arena.list(capacity: 0, of: Int.self)
        routePoints.reserveCapacity(8 * edges.count)
    }

    /// Lays the graph out in place in the arena and returns its width and height, or nil when a level would need more
    /// vertices than the limit. Each edge's route is then a range of `routePoints`.
    static func layout(_ layout: inout LayeredCompoundLayout) -> (width: Double, height: Double)? {
        layout.buildLevels()
        let ports = layout.budgetPorts()
        layout.assignEdges()
        layout.isOrdered = ports > 1 && ports <= LayeredCompoundConstants.maximumOrderedPorts
            && layout.edges.count <= LayeredCompoundConstants.maximumOrderedEdges
        return layout.arrange() ? layout.total : nil
    }

    /// Lays the graph out in place and returns its width and height, or nil when a level would need more vertices
    /// than the limit: the lists copied into the calling thread's arena, laid out there, and copied back.
    static func layout(nodes: inout [LayeredCompoundNode], edges: inout [LayeredCompoundEdge], rootDirection: LayeredDirection,
                       options: LayeredFlatOptions, maximumVertexCount: Int = .max) -> (width: Double, height: Double)? {
        DiagramScratchArena.withCurrentThread { arena in
            let nodeSpan: ScratchSpan<LayeredCompoundNode> = arena.uninitializedSpan(count: nodes.count)
            for index in nodes.indices { nodeSpan[index] = nodes[index] }
            let edgeSpan: ScratchSpan<LayeredCompoundSpanEdge> = arena.uninitializedSpan(count: edges.count)
            for index in edges.indices { edgeSpan[index] = LayeredCompoundSpanEdge(edges[index]) }
            var laidOut = LayeredCompoundLayout(nodes: nodeSpan, edges: edgeSpan, rootDirection: rootDirection, options: options,
                                                maximumVertexCount: maximumVertexCount, arena: arena)
            guard let size = layout(&laidOut) else { return nil }
            for index in nodes.indices { nodes[index] = nodeSpan[index] }
            for index in edges.indices {
                let edge = edgeSpan[index]
                edges[index].source = edge.source
                edges[index].target = edge.target
                edges[index].labelCenter = edge.labelCenter
                edges[index].route = Array(laidOut.routePoints[laidOut.routeRange(of: index)])
            }
            return size
        }
    }

    /// Where the route of `edge` is in `routePoints`.
    @inline(__always)
    func routeRange(of edge: Int) -> Range<Int> { edges[edge].routeStart..<(edges[edge].routeStart + edges[edge].routeCount) }

    /// The level that holds what sits directly in `group` (-1 for the top level).
    @inline(__always)
    func levelIndex(of group: Int) -> Int { group < 0 ? 0 : levelOfGroup[group] }

    /// Whether the end of `edge` at `item` lies inside it rather than at it.
    @inline(__always)
    func endsBelow(_ item: Int, edge: Int, isOutgoing: Bool) -> Bool {
        (isOutgoing ? edges[edge].source : edges[edge].target) != item
    }

    /// The port of the end of `edge` in the level `levelIndex`, or -1.
    @inline(__always)
    func port(in levelIndex: Int, edge: Int, isOutgoing: Bool) -> Int {
        var port = firstPortOfEdgeEnd[edge * 2 + (isOutgoing ? 0 : 1)]
        while port >= 0 && ports[port].level != levelIndex { port = ports[port].nextOfSameEnd }
        return port
    }
}
