/**
 * File: LayeredClusterLayout.swift
 * --------------------------------
 * Layer: Core
 * Description: Lays out a graph whose nodes sit in nested boxes with the port of Pele's compound layout.
 *
 * Authors: Félix Chevalier, Bahey Shalash
 * Version: 0.5
 * Date: 24/11/2026
 */

import CoreGraphics

/// A cluster graph laid out as Pele lays out a graph in groups (`LayeredCompoundLayout`): the nodes first, then each
/// cluster as a group node after them, each box laid out on its own in its direction and placed in the box around it.
/// Boxes inside each other through their parents are lifted to the top level, as Pele does.
enum LayeredClusterLayout {
    /// Lays `graph` out, its boxes padded as each cluster asks, within `maximumPointCount` nodes and passing points in
    /// all its boxes together.
    static func place(_ graph: LayeredClusterGraph, spacing: LayeredSpacing,
                      maximumPointCount: Int) throws(LayeredClusterLayoutError) -> LayeredClusterPlacement {
        #if DEBUG
        LayeredLayoutRecording.current?.clusterPlacements.append(.init(graph: graph, spacing: spacing, maximumPointCount: maximumPointCount))
        #endif
        if let placed = placeWithoutClusters(graph, spacing: spacing, maximumPointCount: maximumPointCount) { return try placed.get() }
        return try placeInCompoundLayout(graph, spacing: spacing, maximumPointCount: maximumPointCount)
    }

    /// `place` through the compound layout, whatever the graph: the compound graph written into the calling thread's
    /// arena, laid out there, and the placement read from it.
    static func placeInCompoundLayout(_ graph: LayeredClusterGraph, spacing: LayeredSpacing,
                                      maximumPointCount: Int) throws(LayeredClusterLayoutError) -> LayeredClusterPlacement {
        let placement: LayeredClusterPlacement? = DiagramScratchArena.withCurrentThread { arena in
            laidOutInCompoundLayout(graph, spacing: spacing, maximumPointCount: maximumPointCount, arena: arena).map { layout in
                placement(of: layout, graph: graph, size: layout.total)
            }
        }
        guard let placement else { throw .tooManyPoints }
        return placement
    }

    /// A graph with clusters laid out by the compound layout in `arena`, its nodes the graph's then a group node for each
    /// cluster, as `place` lays it out; nil when it would need more than `maximumPointCount` points. Recorded as `place`
    /// records it, for the tests that place every cluster graph of the corpora again.
    static func laidOutInCompoundLayout(_ graph: LayeredClusterGraph, spacing: LayeredSpacing, maximumPointCount: Int,
                                        arena: DiagramScratchArena, isRecorded: Bool = false) -> LayeredCompoundLayout? {
        #if DEBUG
        if isRecorded { LayeredLayoutRecording.current?.clusterPlacements.append(.init(graph: graph, spacing: spacing, maximumPointCount: maximumPointCount)) }
        #endif
        let nodeCount = graph.nodeSizes.count
        let nodes = compoundNodes(graph, arena: arena)
        func index(of end: LayeredClusterEnd) -> Int {
            switch end {
            case .node(let node): node
            case .cluster(let cluster): nodeCount + cluster
            }
        }
        let edges: ScratchSpan<LayeredCompoundSpanEdge> = arena.uninitializedSpan(count: graph.edges.count)
        for (edgeIndex, edge) in graph.edges.enumerated() {
            edges[edgeIndex] = LayeredCompoundSpanEdge(source: index(of: edge.source), target: index(of: edge.target), minimumLength: edge.minimumRankSpan,
                                                       labelWidth: Double(edge.labelSize?.width ?? 0), labelHeight: Double(edge.labelSize?.height ?? 0))
        }
        var layout = LayeredCompoundLayout(nodes: nodes, edges: edges, rootDirection: graph.direction, options: LayeredLayout.options(spacing),
                                           maximumVertexCount: maximumPointCount, arena: arena)
        return LayeredCompoundLayout.layout(&layout) == nil ? nil : layout
    }

    /// The placement a compound layout of `graph` gave, its lists made once from the arena's.
    private static func placement(of layout: LayeredCompoundLayout, graph: LayeredClusterGraph, size: (width: Double, height: Double)) -> LayeredClusterPlacement {
        let nodeCount = graph.nodeSizes.count
        let nodes = layout.nodes
        let edges = layout.edges
        var frames: [CGRect] = []
        frames.reserveCapacity(graph.clusters.count)
        for cluster in graph.clusters.indices {
            let node = nodes[nodeCount + cluster]
            frames.append(CGRect(x: node.x - node.width / 2, y: node.y - node.height / 2, width: node.width, height: node.height))
        }
        var strays = Set<Int>()
        var routes: [LayeredClusterRoute] = []
        var labelCenters: [CGPoint?] = []
        routes.reserveCapacity(edges.count)
        labelCenters.reserveCapacity(edges.count)
        for edgeIndex in 0..<edges.count {
            if layout.isStray(edgeIndex) { strays.insert(edgeIndex) }
            routes.append(route(layout.routePoints[layout.routeRange(of: edgeIndex)]))
            labelCenters.append(edges[edgeIndex].labelWidth > 0 || strays.contains(edgeIndex) ? edges[edgeIndex].labelCenter : nil)
        }
        var centers: [CGPoint] = []
        centers.reserveCapacity(nodeCount)
        for node in 0..<nodeCount { centers.append(CGPoint(x: nodes[node].x, y: nodes[node].y)) }
        return LayeredClusterPlacement(nodeCenters: centers, clusterFrames: frames, edgeRoutes: routes, edgeLabelCenters: labelCenters,
                                       size: CGSize(width: size.width, height: size.height), strayEdgeIndices: strays)
    }

    /// The graph's nodes, then its clusters as groups: a node's place in the declaration order its index, a cluster's
    /// after every node, in cluster order (a cluster with members takes its first member's).
    private static func compoundNodes(_ graph: LayeredClusterGraph, arena: DiagramScratchArena) -> ScratchSpan<LayeredCompoundNode> {
        let nodeCount = graph.nodeSizes.count
        let nodes: ScratchSpan<LayeredCompoundNode> = arena.uninitializedSpan(count: nodeCount + graph.clusters.count)
        for (node, size) in graph.nodeSizes.enumerated() {
            var compound = LayeredCompoundNode(width: Double(size.width), height: Double(size.height),
                                               parent: graph.nodeClusters[node].map { cluster in nodeCount + cluster } ?? -1)
            compound.sequence = Double(node)
            compound.sideSpan = node < graph.nodeSideSpans.count ? Double(graph.nodeSideSpans[node]) : 0
            nodes[node] = compound
        }
        for (clusterIndex, cluster) in graph.clusters.enumerated() {
            var group = LayeredCompoundNode(width: 0, height: 0, parent: cluster.parent.map { parent in nodeCount + parent } ?? -1)
            group.isGroup = true
            group.direction = cluster.direction
            group.paddingSide = Double(cluster.padding.side)
            group.paddingTop = Double(cluster.padding.top)
            group.paddingBottom = Double(cluster.padding.bottom)
            group.minimumWidth = Double(cluster.minimumWidth)
            group.sequence = Double(cluster.sequence ?? CGFloat(nodeCount + clusterIndex))
            group.sideSpan = Double(cluster.sideSpan)
            nodes[nodeCount + clusterIndex] = group
        }
        return nodes
    }

    private static func route(_ points: ArraySlice<LayeredRoutePoint>) -> LayeredClusterRoute {
        var placed: [CGPoint] = []
        var segmentsRunVertically: [Bool] = []
        placed.reserveCapacity(points.count)
        segmentsRunVertically.reserveCapacity(max(points.count - 1, 0))
        for (index, point) in points.enumerated() {
            placed.append(point.point)
            if index > 0 { segmentsRunVertically.append(!point.runsHorizontally) }
        }
        return LayeredClusterRoute(points: placed, segmentsRunVertically: segmentsRunVertically)
    }
}

extension LayeredCompoundLayout {
    /// Whether edge `edgeIndex` runs between a group and something inside it, which Pele draws from one center to the
    /// other.
    func isStray(_ edgeIndex: Int) -> Bool {
        let edge = edges[edgeIndex]
        guard edge.source != edge.target else { return false }
        func contains(_ group: Int, _ node: Int) -> Bool {
            var parent = nodes[node].parent
            var hops = 0
            while parent >= 0 && hops < nodes.count {
                if parent == group { return true }
                parent = nodes[parent].parent
                hops += 1
            }
            return false
        }
        return contains(edge.source, edge.target) || contains(edge.target, edge.source)
    }
}
