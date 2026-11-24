/**
 * File: ReferenceLayeredLayout.swift
 * ----------------------------------
 * Layer: Tests
 * Description: The 0.7.0 layered layout kept as the reference the span layout is checked against: lays a flat graph out
 *              in ranks with the port of Pele's layered layout, in flow space.
 *
 * Authors: Bahey Shalash, felixchvl
 * Version: 0.1
 * Date: 24/11/2026
 */

import CoreGraphics
@testable import MermaidDiagrams

/// A layered layout of a directed graph without groups, as Pele lays out a diagram with no subgraphs: its compound
/// layout's top level is one flat graph given to `layered` (`ReferenceLayeredFlatLayout`). Cycles are broken by turning edges
/// around, nodes ranked and balanced, edges cut at every rank they pass, ranks ordered, positioned, ends spread and
/// settled, bends straightened and the gaps sized to what crosses them. When any edge has text, or two edges join the
/// same nodes, every span is doubled so that the texts get ranks of their own between the ranks of nodes.
enum ReferenceLayeredLayout {
    /// Lays `graph` out, or returns nil when it would need more than `maximumPointCount` nodes and passing points.
    static func place(_ graph: LayeredGraph, spacing: LayeredSpacing, maximumPointCount: Int) -> LayeredPlacement? {
        var nodes = graph.nodeSizes.enumerated().map { node, size in
            var flatNode = LayeredFlatNode(width: Double(size.across), height: Double(size.along))
            flatNode.sideSpan = node < graph.nodeSideSpans.count ? Double(graph.nodeSideSpans[node]) : 0
            return flatNode
        }
        var edges = graph.edges.map { edge in
            var flatEdge = LayeredFlatEdge(tail: edge.source, head: edge.target, minimumLength: edge.minimumRankSpan,
                                           labelWidth: Double(edge.labelSize?.across ?? 0), labelHeight: Double(edge.labelSize?.along ?? 0))
            flatEdge.tailOffset = Double(edge.sourceOffset)
            flatEdge.headOffset = Double(edge.targetOffset)
            return flatEdge
        }
        guard let size = ReferenceLayeredFlatLayout.layout(nodes: &nodes, edges: &edges, options: options(spacing), maximumVertexCount: maximumPointCount) else {
            return nil
        }
        let centers = nodes.map { node in CGPoint(x: node.x, y: node.y) }
        return LayeredPlacement(nodeCenters: centers,
                                edgeRoutes: edges.map { edge in centeredRoute(edge, centers: centers) },
                                edgeLabelCenters: edges.map { edge in edge.labelWidth > 0 ? edge.labelCenter : nil },
                                edgePaths: edges.map(\.points), extent: CGSize(width: size.width, height: size.height))
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

    /// The edge's route from its source's center to its target's through the points Pele's route passes between the
    /// sides of its nodes.
    private static func centeredRoute(_ edge: LayeredFlatEdge, centers: [CGPoint]) -> [CGPoint] {
        [centers[edge.tail]] + edge.points.dropFirst().dropLast() + [centers[edge.head]]
    }
}
