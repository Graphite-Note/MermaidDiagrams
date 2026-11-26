/**
 * File: ReferenceLayeredClusterLayout.swift
 * -----------------------------------------
 * Layer: Tests
 * Description: The 0.7.0 compound layout kept as the reference the layout is checked against: lays out a graph whose
 *              nodes sit in nested boxes with the port of Pele's compound layout.
 *
 * Authors: Félix Chevalier, Bahey Shalash
 * Version: 0.2
 * Date: 25/11/2026
 */

import CoreGraphics
@testable import MermaidDiagrams

/// A cluster graph laid out as Pele lays out a graph in groups (`ReferenceLayeredCompoundLayout`): the nodes first, then each
/// cluster as a group node after them, each box laid out on its own in its direction and placed in the box around it.
/// Boxes inside each other through their parents are lifted to the top level, as Pele does.
enum ReferenceLayeredClusterLayout {
    /// Lays `graph` out, its boxes padded as each cluster asks, within `maximumPointCount` nodes and passing points in
    /// all its boxes together.
    static func place(_ graph: LayeredClusterGraph, spacing: LayeredSpacing,
                      maximumPointCount: Int) throws(LayeredClusterLayoutError) -> LayeredClusterPlacement {
        let nodeCount = graph.nodeSizes.count
        var nodes = compoundNodes(graph)
        func index(of end: LayeredClusterEnd) -> Int {
            switch end {
            case .node(let node): node
            case .cluster(let cluster): nodeCount + cluster
            }
        }
        var edges = graph.edges.map { edge in
            LayeredCompoundEdge(source: index(of: edge.source), target: index(of: edge.target), minimumLength: edge.minimumRankSpan,
                                labelWidth: Double(edge.labelSize?.width ?? 0), labelHeight: Double(edge.labelSize?.height ?? 0))
        }
        guard let size = ReferenceLayeredCompoundLayout.layout(nodes: &nodes, edges: &edges, rootDirection: graph.direction,
                                                      options: LayeredFlatOptions(spacing), maximumVertexCount: maximumPointCount) else {
            throw .tooManyPoints
        }
        let frames = graph.clusters.indices.map { cluster in
            let node = nodes[nodeCount + cluster]
            return CGRect(x: node.x - node.width / 2, y: node.y - node.height / 2, width: node.width, height: node.height)
        }
        let strays = Set(edges.indices.filter { edgeIndex in edges[edgeIndex].source != edges[edgeIndex].target && isStray(edges[edgeIndex], nodes: nodes) })
        return LayeredClusterPlacement(nodeCenters: (0..<nodeCount).map { node in CGPoint(x: nodes[node].x, y: nodes[node].y) },
                                       clusterFrames: frames, edgeRoutes: edges.map(route(of:)),
                                       edgeLabelCenters: edges.indices.map { edgeIndex in
                                           edges[edgeIndex].labelWidth > 0 || strays.contains(edgeIndex) ? edges[edgeIndex].labelCenter : nil
                                       },
                                       size: CGSize(width: size.width, height: size.height), strayEdgeIndices: strays)
    }

    /// The graph's nodes, then its clusters as groups: a node's place in the declaration order its index, a cluster's
    /// after every node, in cluster order (a cluster with members takes its first member's).
    private static func compoundNodes(_ graph: LayeredClusterGraph) -> [LayeredCompoundNode] {
        let nodeCount = graph.nodeSizes.count
        var nodes = graph.nodeSizes.enumerated().map { node, size in
            var compound = LayeredCompoundNode(width: Double(size.width), height: Double(size.height),
                                               parent: graph.nodeClusters[node].map { cluster in nodeCount + cluster } ?? -1)
            compound.sequence = Double(node)
            compound.sideSpan = node < graph.nodeSideSpans.count ? Double(graph.nodeSideSpans[node]) : 0
            return compound
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
            nodes.append(group)
        }
        return nodes
    }

    /// Whether an edge runs between a group and something inside it, which Pele draws from one center to the other.
    private static func isStray(_ edge: LayeredCompoundEdge, nodes: [LayeredCompoundNode]) -> Bool {
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

    private static func route(of edge: LayeredCompoundEdge) -> LayeredClusterRoute {
        LayeredClusterRoute(points: edge.route.map(\.point), segmentsRunVertically: edge.route.dropFirst().map { point in !point.runsHorizontally })
    }
}
