/**
 * File: LayeredSpanPlacement.swift
 * --------------------------------
 * Layer: Tests
 * Description: The 0.7.0 adapters' graphs placed on the 0.8.0 span layouts, so that the tests can put the layouts and the
 *              frozen 0.7.0 references side by side on the same graphs.
 *
 * Authors: Félix Chevalier, Bahey Shalash
 * Version: 0.1
 * Date: 25/11/2026
 */

import CoreGraphics
@testable import MermaidDiagrams

/// A graph as 0.7.0 handed it to its flat layered layout, with its gaps and budget.
struct LayeredPlacementInput {
    var graph: LayeredGraph
    var spacing: LayeredSpacing
    var maximumPointCount: Int

    init(graph: LayeredGraph, spacing: LayeredSpacing, maximumPointCount: Int) {
        self.graph = graph
        self.spacing = spacing
        self.maximumPointCount = maximumPointCount
    }

    /// The graph a ranked layout wrote into the flat layout's spans, as 0.7.0 would have handed it to its layout.
    init(_ recorded: LayeredLayoutRecording.Placement) {
        let nodeSizes = recorded.nodes.map { node in LayeredSize(across: CGFloat(node.width), along: CGFloat(node.height)) }
        let edges = recorded.edges.map { edge in
            LayeredEdge(source: edge.tail, target: edge.head, minimumRankSpan: edge.minimumLength,
                        labelSize: edge.labelWidth > 0 || edge.labelHeight > 0 ? LayeredSize(across: CGFloat(edge.labelWidth), along: CGFloat(edge.labelHeight)) : nil,
                        sourceOffset: CGFloat(edge.tailOffset), targetOffset: CGFloat(edge.headOffset))
        }
        self.init(graph: LayeredGraph(nodeSizes: nodeSizes, edges: edges, nodeSideSpans: recorded.nodes.map { node in CGFloat(node.sideSpan) }),
                  spacing: recorded.spacing, maximumPointCount: recorded.maximumPointCount)
    }
}

/// A cluster graph as 0.7.0 handed it to its compound layout, with its gaps and budget.
struct LayeredClusterPlacementInput {
    var graph: LayeredClusterGraph
    var spacing: LayeredSpacing
    var maximumPointCount: Int
}

/// The 0.7.0 adapters' placements made on the 0.8.0 layouts: a flat graph written into `LayeredFlatLayout`'s spans and
/// read back as `LayeredPlacement`, a cluster graph written into `LayeredCompoundLayout`'s and read back as
/// `LayeredClusterPlacement`, each number as 0.7.0's adapters computed it.
enum LayeredSpanPlacement {
    /// `graph` laid out by the flat layout, or nil when it would need more than `maximumPointCount` nodes and passing points.
    static func place(_ graph: LayeredGraph, spacing: LayeredSpacing, maximumPointCount: Int) -> LayeredPlacement? {
        DiagramScratchArena.withCurrentThread { arena in
            let nodes: ScratchSpan<LayeredFlatNode> = arena.uninitializedSpan(count: graph.nodeSizes.count)
            for (node, size) in graph.nodeSizes.enumerated() {
                var flatNode = LayeredFlatNode(width: Double(size.across), height: Double(size.along))
                flatNode.sideSpan = node < graph.nodeSideSpans.count ? Double(graph.nodeSideSpans[node]) : 0
                nodes[node] = flatNode
            }
            let edges: ScratchSpan<LayeredSpanEdge> = arena.uninitializedSpan(count: graph.edges.count)
            for (edgeIndex, edge) in graph.edges.enumerated() {
                edges[edgeIndex] = LayeredSpanEdge(tail: edge.source, head: edge.target, minimumLength: edge.minimumRankSpan,
                                                   labelWidth: Double(edge.labelSize?.across ?? 0), labelHeight: Double(edge.labelSize?.along ?? 0),
                                                   tailOffset: Double(edge.sourceOffset), headOffset: Double(edge.targetOffset))
            }
            var points = arena.list(capacity: 4 * edges.count, of: CGPoint.self)
            guard let size = LayeredFlatLayout.layout(nodes: nodes, edges: edges, points: &points, options: LayeredFlatOptions(spacing),
                                                      maximumVertexCount: maximumPointCount, arena: arena) else {
                return nil
            }
            return placement(nodes: nodes, edges: edges, points: points.elements, size: size)
        }
    }

    static func place(_ input: LayeredPlacementInput) -> LayeredPlacement? {
        place(input.graph, spacing: input.spacing, maximumPointCount: input.maximumPointCount)
    }

    private static func placement(nodes: ScratchSpan<LayeredFlatNode>, edges: ScratchSpan<LayeredSpanEdge>, points: ScratchSpan<CGPoint>,
                                  size: LayeredFlatResult) -> LayeredPlacement {
        let centers = nodes.map { node in CGPoint(x: node.x, y: node.y) }
        var routes: [[CGPoint]] = []
        var paths: [[CGPoint]] = []
        var labelCenters: [CGPoint?] = []
        for edge in edges {
            let path = edge.pointStart >= 0 ? Array(points.part(edge.pointStart..<(edge.pointStart + edge.pointCount))) : []
            routes.append([centers[edge.tail]] + (path.count > 2 ? Array(path[1..<(path.count - 1)]) : []) + [centers[edge.head]])
            paths.append(path)
            labelCenters.append(edge.labelWidth > 0 ? edge.labelCenter : nil)
        }
        return LayeredPlacement(nodeCenters: centers, edgeRoutes: routes, edgeLabelCenters: labelCenters, edgePaths: paths,
                                extent: CGSize(width: size.width, height: size.height))
    }

    /// `graph` laid out by the compound layout, its boxes padded as each cluster asks, within `maximumPointCount` nodes
    /// and passing points in all its boxes together: its nodes, then a group node for each cluster after them.
    static func placeClusters(_ graph: LayeredClusterGraph, spacing: LayeredSpacing,
                              maximumPointCount: Int) throws(LayeredClusterLayoutError) -> LayeredClusterPlacement {
        let placement: LayeredClusterPlacement? = DiagramScratchArena.withCurrentThread { arena in
            let compound = compoundGraph(graph, arena: arena)
            return compound.laidOut(spacing: spacing, maximumPointCount: maximumPointCount, arena: arena).map { layout in
                clusterPlacement(of: layout, graph: graph)
            }
        }
        guard let placement else { throw .tooManyPoints }
        return placement
    }

    static func placeClusters(_ input: LayeredClusterPlacementInput) throws(LayeredClusterLayoutError) -> LayeredClusterPlacement {
        try placeClusters(input.graph, spacing: input.spacing, maximumPointCount: input.maximumPointCount)
    }

    /// The graph's nodes in declaration order, then its clusters as boxes, as 0.7.0's cluster layout wrote them.
    private static func compoundGraph(_ graph: LayeredClusterGraph, arena: DiagramScratchArena) -> LayeredCompoundGraph {
        let nodeCount = graph.nodeSizes.count
        let nodes: ScratchSpan<LayeredCompoundNode> = arena.uninitializedSpan(count: nodeCount + graph.clusters.count)
        for (node, size) in graph.nodeSizes.enumerated() {
            nodes[node] = .member(size: size, box: graph.nodeClusters[node], nodeCount: nodeCount, sequence: node,
                                  sideSpan: node < graph.nodeSideSpans.count ? graph.nodeSideSpans[node] : 0)
        }
        for (index, cluster) in graph.clusters.enumerated() {
            nodes[nodeCount + index] = .box(parent: cluster.parent, nodeCount: nodeCount, direction: cluster.direction, padding: cluster.padding,
                                            minimumWidth: cluster.minimumWidth, sequence: cluster.sequence ?? CGFloat(nodeCount + index),
                                            sideSpan: cluster.sideSpan)
        }
        func index(of end: LayeredClusterEnd) -> Int {
            switch end {
            case .node(let node): node
            case .cluster(let cluster): nodeCount + cluster
            }
        }
        let edges: ScratchSpan<LayeredCompoundSpanEdge> = arena.uninitializedSpan(count: graph.edges.count)
        for (edgeIndex, edge) in graph.edges.enumerated() {
            edges[edgeIndex] = LayeredCompoundSpanEdge(source: index(of: edge.source), target: index(of: edge.target), minimumRankSpan: edge.minimumRankSpan,
                                                       labelSize: edge.labelSize)
        }
        return LayeredCompoundGraph(nodes: nodes, edges: edges, nodeCount: nodeCount, direction: graph.direction)
    }

    private static func clusterPlacement(of layout: LayeredCompoundLayout, graph: LayeredClusterGraph) -> LayeredClusterPlacement {
        let nodeCount = graph.nodeSizes.count
        var strays = Set<Int>()
        var routes: [LayeredClusterRoute] = []
        var labelCenters: [CGPoint?] = []
        for edgeIndex in 0..<layout.edges.count {
            if layout.isStray(edgeIndex) { strays.insert(edgeIndex) }
            let points = layout.routePoints[layout.routeRange(of: edgeIndex)]
            routes.append(LayeredClusterRoute(points: points.map(\.point), segmentsRunVertically: points.dropFirst().map { point in !point.runsHorizontally }))
            labelCenters.append(layout.labelCenter(of: edgeIndex))
        }
        return LayeredClusterPlacement(nodeCenters: (0..<nodeCount).map { node in CGPoint(x: layout.nodes[node].x, y: layout.nodes[node].y) },
                                       clusterFrames: graph.clusters.indices.map { cluster in layout.nodes[nodeCount + cluster].frame },
                                       edgeRoutes: routes, edgeLabelCenters: labelCenters, size: CGSize(width: layout.total.width, height: layout.total.height),
                                       strayEdgeIndices: strays)
    }
}

/// Every number of a cluster placement as bit patterns, or the error it threw.
struct LayeredClusterPlacementBits: Equatable {
    var bits: [UInt64] = []
    var error: LayeredClusterLayoutError?

    /// The bits of what `placing` gives.
    init(placing: () throws(LayeredClusterLayoutError) -> LayeredClusterPlacement) {
        let placement: LayeredClusterPlacement
        do {
            placement = try placing()
        } catch {
            self.error = error
            return
        }
        func add(_ point: CGPoint) { bits += [Double(point.x).bitPattern, Double(point.y).bitPattern] }
        placement.nodeCenters.forEach(add)
        for frame in placement.clusterFrames { bits += [frame.minX, frame.minY, frame.width, frame.height].map { value in Double(value).bitPattern } }
        for route in placement.edgeRoutes {
            bits.append(UInt64(route.points.count))
            route.points.forEach(add)
            bits += route.segmentsRunVertically.map { runsVertically in runsVertically ? 1 : 0 }
        }
        for center in placement.edgeLabelCenters {
            if let center { add(center) } else { bits.append(UInt64.max) }
        }
        bits += [Double(placement.size.width).bitPattern, Double(placement.size.height).bitPattern]
        bits += placement.strayEdgeIndices.sorted().map { index in UInt64(index) }
    }
}
