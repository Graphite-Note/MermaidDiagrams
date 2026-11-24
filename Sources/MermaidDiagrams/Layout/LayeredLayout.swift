/**
 * File: LayeredLayout.swift
 * -------------------------
 * Layer: Core
 * Description: Lays a flat graph out in ranks with the port of Pele's layered layout, in flow space.
 *
 * Authors: Félix Chevalier, Bahey Shalash
 * Version: 0.3
 * Date: 24/11/2026
 */

import CoreGraphics

/// A layered layout of a directed graph without groups, as Pele lays out a diagram with no subgraphs: its compound
/// layout's top level is one flat graph given to `layered` (`LayeredFlatLayout`). Cycles are broken by turning edges
/// around, nodes ranked and balanced, edges cut at every rank they pass, ranks ordered, positioned, ends spread and
/// settled, bends straightened and the gaps sized to what crosses them. When any edge has text, or two edges join the
/// same nodes, every span is doubled so that the texts get ranks of their own between the ranks of nodes.
enum LayeredLayout {
    /// Lays `graph` out, or returns nil when it would need more than `maximumPointCount` nodes and passing points. The
    /// layout works in the calling thread's scratch arena; only the placement it returns is allocated.
    static func place(_ graph: LayeredGraph, spacing: LayeredSpacing, maximumPointCount: Int) -> LayeredPlacement? {
        #if DEBUG
        LayeredLayoutRecording.current?.placements.append(.init(graph: graph, spacing: spacing, maximumPointCount: maximumPointCount))
        #endif
        return DiagramScratchArena.withCurrentThread { arena in
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
            guard let size = LayeredFlatLayout.layout(nodes: nodes, edges: edges, points: &points, options: options(spacing),
                                                      maximumVertexCount: maximumPointCount, arena: arena) else {
                return nil
            }
            return placement(nodes: nodes, edges: edges, points: points.elements, size: size)
        }
    }

    /// The placement of laid-out `nodes` and `edges`, every list made once with the room it needs.
    private static func placement(nodes: ScratchSpan<LayeredFlatNode>, edges: ScratchSpan<LayeredSpanEdge>, points: ScratchSpan<CGPoint>,
                                  size: LayeredFlatResult) -> LayeredPlacement {
        var centers: [CGPoint] = []
        centers.reserveCapacity(nodes.count)
        for node in nodes { centers.append(CGPoint(x: node.x, y: node.y)) }
        var routes: [[CGPoint]] = []
        var paths: [[CGPoint]] = []
        var labelCenters: [CGPoint?] = []
        routes.reserveCapacity(edges.count)
        paths.reserveCapacity(edges.count)
        labelCenters.reserveCapacity(edges.count)
        for edge in edges {
            let path = edge.pointStart >= 0 ? points.part(edge.pointStart..<(edge.pointStart + edge.pointCount)) : points.part(0..<0)
            // The route from its source's center to its target's through the points Pele's route passes between the
            // sides of its nodes.
            var route: [CGPoint] = []
            route.reserveCapacity(max(path.count, 2))
            route.append(centers[edge.tail])
            if path.count > 2 { route.append(contentsOf: path.part(1..<(path.count - 1))) }
            route.append(centers[edge.head])
            routes.append(route)
            paths.append(Array(path))
            labelCenters.append(edge.labelWidth > 0 ? edge.labelCenter : nil)
        }
        return LayeredPlacement(nodeCenters: centers, edgeRoutes: routes, edgeLabelCenters: labelCenters, edgePaths: paths,
                                extent: CGSize(width: size.width, height: size.height))
    }

    /// Pele's options for `spacing`.
    static func options(_ spacing: LayeredSpacing) -> LayeredFlatOptions {
        var options = LayeredFlatOptions(nodeSeparation: Double(spacing.nodeSeparation), edgeSeparation: Double(spacing.edgeSeparation),
                                         rankSeparation: Double(spacing.rankSeparation),
                                         portSeparation: Double(spacing.borderSeparation ?? spacing.rankSeparation))
        options.runsOnTracks = spacing.routing.runsOnTracks
        options.isStraight = spacing.routing.isStraight
        options.keepsTwinsApart = spacing.routing.keepsTwinsApart
        options.headRoom = Double(spacing.routing.headRoom)
        return options
    }
}
