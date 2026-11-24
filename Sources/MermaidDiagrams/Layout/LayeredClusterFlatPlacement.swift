/**
 * File: LayeredClusterFlatPlacement.swift
 * ---------------------------------------
 * Layer: Core
 * Description: A cluster graph without clusters laid out as the compound layout lays out its one level, straight on
 *              the scratch arena, with none of the compound layout's levels, ports and routes to build.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 24/11/2026
 */

import CoreGraphics

extension LayeredClusterLayout {
    /// The placement `LayeredCompoundLayout` gives a graph with no cluster, no node in one and every edge between nodes,
    /// to the bit, or nil for any other graph. Such a graph is one level: no port, no group, nothing keyed or ordered,
    /// so the compound layout runs one flat layout of its nodes in declaration order and its edges that are not loops,
    /// turns it onto the page in an unpadded box at the origin, joins each route without its repeated points, and puts a
    /// loop's label beside its node; this does the same arithmetic in the same order. Nil also stands for a layout that
    /// would need more than `maximumPointCount` points, reported by `tooManyPoints`.
    static func placeWithoutClusters(_ graph: LayeredClusterGraph, spacing: LayeredSpacing,
                                     maximumPointCount: Int) -> Result<LayeredClusterPlacement, LayeredClusterLayoutError>? {
        guard graph.clusters.isEmpty, !graph.nodeClusters.contains(where: { cluster in cluster != nil }) else { return nil }
        for edge in graph.edges {
            guard case .node = edge.source, case .node = edge.target else { return nil }
        }
        return DiagramScratchArena.withCurrentThread { arena in
            let isVertical = graph.direction.runsVertically
            let nodes: ScratchSpan<LayeredFlatNode> = arena.uninitializedSpan(count: graph.nodeSizes.count)
            for (node, size) in graph.nodeSizes.enumerated() {
                let width = Double(size.width)
                let height = Double(size.height)
                var flatNode = LayeredFlatNode(width: isVertical ? width : height, height: isVertical ? height : width)
                flatNode.sideSpan = node < graph.nodeSideSpans.count ? Double(graph.nodeSideSpans[node]) : 0
                nodes[node] = flatNode
            }
            let edges = flatEdges(of: graph, isVertical: isVertical, arena: arena)
            var points = arena.list(capacity: 4 * edges.count, of: CGPoint.self)
            guard let size = LayeredFlatLayout.layout(nodes: nodes, edges: edges, points: &points, options: LayeredLayout.options(spacing),
                                                      maximumVertexCount: maximumPointCount, arena: arena) else {
                return .failure(.tooManyPoints)
            }
            return .success(placement(of: graph, nodes: nodes, edges: edges, points: points.elements,
                                      box: LayeredCompoundBox(direction: graph.direction, size: size, group: nil)))
        }
    }

    /// The graph's edges that are not loops, in order, in flow space.
    private static func flatEdges(of graph: LayeredClusterGraph, isVertical: Bool, arena: DiagramScratchArena) -> ScratchSpan<LayeredSpanEdge> {
        var edges = arena.list(capacity: graph.edges.count, of: LayeredSpanEdge.self)
        for edge in graph.edges {
            guard case .node(let source) = edge.source, case .node(let target) = edge.target, source != target else { continue }
            let labelWidth = Double(edge.labelSize?.width ?? 0)
            let labelHeight = Double(edge.labelSize?.height ?? 0)
            edges.append(LayeredSpanEdge(tail: source, head: target, minimumLength: edge.minimumRankSpan,
                                         labelWidth: isVertical ? labelWidth : labelHeight, labelHeight: isVertical ? labelHeight : labelWidth,
                                         tailOffset: 0, headOffset: 0))
        }
        return edges.elements
    }

    /// The flat layout turned onto the page: centers, routes and label centers as the compound layout writes them.
    private static func placement(of graph: LayeredClusterGraph, nodes: ScratchSpan<LayeredFlatNode>, edges: ScratchSpan<LayeredSpanEdge>,
                                  points: ScratchSpan<CGPoint>, box: LayeredCompoundBox) -> LayeredClusterPlacement {
        let origin = CGPoint.zero
        var centers: [CGPoint] = []
        centers.reserveCapacity(nodes.count)
        for node in nodes {
            let point = box.pagePoint(CGPoint(x: node.x, y: node.y))
            centers.append(CGPoint(x: point.x + origin.x, y: point.y + origin.y))
        }
        var routes: [LayeredClusterRoute] = []
        var labelCenters: [CGPoint?] = []
        routes.reserveCapacity(graph.edges.count)
        labelCenters.reserveCapacity(graph.edges.count)
        var flatEdge = 0
        for edge in graph.edges {
            guard case .node(let source) = edge.source, case .node(let target) = edge.target else { continue }
            let labelWidth = Double(edge.labelSize?.width ?? 0)
            if source == target {
                routes.append(LayeredClusterRoute(points: [], segmentsRunVertically: []))
                let node = centers[source]
                let width = Double(graph.nodeSizes[source].width)
                let center = CGPoint(x: node.x + width / 2 + LayeredCompoundConstants.loopLabelGap + labelWidth / 2, y: node.y)
                labelCenters.append(labelWidth > 0 ? center : nil)
                continue
            }
            let laidOut = edges[flatEdge]
            flatEdge += 1
            routes.append(route(points.part(laidOut.pointStart..<(laidOut.pointStart + laidOut.pointCount)), box: box, origin: origin))
            let center = box.pagePoint(laidOut.labelCenter)
            labelCenters.append(labelWidth > 0 ? CGPoint(x: center.x + origin.x, y: center.y + origin.y) : nil)
        }
        return LayeredClusterPlacement(nodeCenters: centers, clusterFrames: [], edgeRoutes: routes, edgeLabelCenters: labelCenters,
                                       size: CGSize(width: box.width, height: box.height), strayEdgeIndices: [])
    }

    /// A flat route on the page, each point moved by `origin` and a point within 0.01 of the one before left out, every
    /// segment running across the box's direction as `LayeredCompoundBox.route` marks it.
    private static func route(_ flowPoints: ScratchSpan<CGPoint>, box: LayeredCompoundBox, origin: CGPoint) -> LayeredClusterRoute {
        var points: [CGPoint] = []
        points.reserveCapacity(flowPoints.count)
        for flowPoint in flowPoints {
            let pagePoint = box.pagePoint(flowPoint)
            let point = CGPoint(x: pagePoint.x + origin.x, y: pagePoint.y + origin.y)
            if let last = points.last, abs(last.x - point.x) < 0.01, abs(last.y - point.y) < 0.01 { continue }
            points.append(point)
        }
        let runsVertically = box.direction.runsVertically
        return LayeredClusterRoute(points: points, segmentsRunVertically: [Bool](repeating: runsVertically, count: max(points.count - 1, 0)))
    }
}
