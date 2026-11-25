/**
 * File: ClassDiagramRankedLayout.swift
 * ------------------------------------
 * Layer: Core
 * Description: A class diagram without namespaces laid out in ranks in the scratch arena, and one with namespaces read
 *              from the compound layout where it stands: the graph written straight into the layouts' spans and the
 *              placed spans read on the page.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 24/11/2026
 */

import CoreGraphics

/// A class diagram without namespaces, as Pele lays out a diagram with no groups: its classes, notes and interfaces and
/// the edges between two different nodes as one flat layered graph (`LayeredFlatLayout`); then each node at its center
/// on the page and each edge from one box's side to the other's through its passing points (`ClassDiagramPageAssembly`).
/// The working lists are spans of the calling thread's arena.
enum ClassDiagramRankedLayout {
    /// The page, its nodes and edges placed and its loops beside their classes; nil when the flat graph would need more
    /// than `maximumPointCount` nodes and passing points.
    static func page(_ diagram: ClassDiagram, measured: ClassDiagramMeasurement, selfLoops: [[Int]], spacing: LayeredSpacing, markRowHeight: CGFloat,
                     maximumPointCount: Int, arena: DiagramScratchArena) -> ClassDiagramPageAssembly? {
        let flowAxes = FlowchartFlowAxes(direction: diagram.direction, alongExtent: 0)
        let layoutSizes = measured.layoutSizes(selfLoops: selfLoops)
        let nodes: ScratchSpan<LayeredFlatNode> = arena.uninitializedSpan(count: layoutSizes.count)
        for node in 0..<layoutSizes.count {
            let size = flowAxes.flowSize(of: layoutSizes[node])
            nodes[node] = LayeredFlatNode(width: Double(size.across), height: Double(size.along))
        }
        var layered = arena.list(capacity: measured.edges.count, of: Int.self)
        for edgeIndex in measured.edges.indices where !measured.edges[edgeIndex].isSelfLoop { layered.append(edgeIndex) }
        let edges: ScratchSpan<LayeredSpanEdge> = arena.uninitializedSpan(count: layered.count)
        for layeredIndex in 0..<layered.count {
            let edge = measured.edges[layered[layeredIndex]]
            let labelSize = edge.text.map { text in
                flowAxes.flowSize(of: CGSize(width: text.size.width + ClassDiagramLayoutEngine.edgeTextRoom.width,
                                             height: text.size.height + ClassDiagramLayoutEngine.edgeTextRoom.height))
            }
            edges[layeredIndex] = LayeredSpanEdge(tail: edge.source, head: edge.target, minimumLength: 1, labelWidth: Double(labelSize?.across ?? 0),
                                                  labelHeight: Double(labelSize?.along ?? 0), tailOffset: 0, headOffset: 0)
        }
        #if DEBUG
        record(nodes: nodes, edges: edges, spacing: spacing, maximumPointCount: maximumPointCount)
        #endif
        var points = arena.list(capacity: 4 * edges.count, of: CGPoint.self)
        guard let size = LayeredFlatLayout.layout(nodes: nodes, edges: edges, points: &points, options: LayeredLayout.options(spacing),
                                                  maximumVertexCount: maximumPointCount, arena: arena) else {
            return nil
        }
        var page = ClassDiagramPageAssembly(measured: measured, markRowHeight: markRowHeight,
                                            axes: FlowchartFlowAxes(direction: diagram.direction, alongExtent: CGFloat(size.height)))
        page.placeNodes(flowNodes: nodes)
        page.placeEdges(layeredEdgeIndices: layered.elements, nodes: nodes, edges: edges, points: points.elements)
        page.placeSelfLoops(selfLoops)
        return page
    }

    #if DEBUG
    /// The graph as `LayeredLayout.place` would have been handed it, for the tests that check every placement of the corpora.
    private static func record(nodes: ScratchSpan<LayeredFlatNode>, edges: ScratchSpan<LayeredSpanEdge>, spacing: LayeredSpacing, maximumPointCount: Int) {
        guard let recording = LayeredLayoutRecording.current else { return }
        let placed = LayeredGraph(nodeSizes: nodes.map { node in LayeredSize(across: CGFloat(node.width), along: CGFloat(node.height)) },
                                  edges: edges.map { edge in
                                      LayeredEdge(source: edge.tail, target: edge.head, minimumRankSpan: edge.minimumLength,
                                                  labelSize: edge.labelWidth > 0 || edge.labelHeight > 0
                                                      ? LayeredSize(across: CGFloat(edge.labelWidth), along: CGFloat(edge.labelHeight)) : nil)
                                  })
        recording.placements.append(.init(graph: placed, spacing: spacing, maximumPointCount: maximumPointCount))
    }
    #endif

    /// The page of a diagram with namespaces: each a box laid out on its own and placed in the box around it, as Pele's
    /// class renderer does (`ClassDiagramNamespaceTree`, `ClassDiagramClusterGraph`, `LayeredCompoundLayout`), the compound
    /// layout read where it stands; nil when the boxes would need more than `maximumPointCount` nodes and passing points.
    static func boxedPage(clustered: ClassDiagramClusterGraph, measured: ClassDiagramMeasurement, selfLoops: [[Int]], spacing: LayeredSpacing,
                          markRowHeight: CGFloat, direction: FlowchartDirection, maximumPointCount: Int,
                          arena: DiagramScratchArena) -> ClassDiagramPageAssembly? {
        guard let compound = LayeredClusterLayout.laidOutInCompoundLayout(clustered.graph, spacing: spacing, maximumPointCount: maximumPointCount,
                                                                          arena: arena, isRecorded: true) else {
            return nil
        }
        let nodeCount = clustered.graph.nodeSizes.count
        var centers: [CGPoint] = []
        centers.reserveCapacity(nodeCount)
        for node in 0..<nodeCount { centers.append(CGPoint(x: compound.nodes[node].x, y: compound.nodes[node].y)) }
        var frames: [CGRect] = []
        frames.reserveCapacity(clustered.graph.clusters.count)
        for cluster in clustered.graph.clusters.indices {
            let node = compound.nodes[nodeCount + cluster]
            frames.append(CGRect(x: node.x - node.width / 2, y: node.y - node.height / 2, width: node.width, height: node.height))
        }
        var page = ClassDiagramPageAssembly(measured: measured, markRowHeight: markRowHeight, axes: FlowchartFlowAxes(direction: direction, alongExtent: 0))
        page.placeNodes(pageCenters: centers)
        page.placeEdges(clustered: clustered, compound: compound, clusterFrames: frames)
        page.placeSelfLoops(selfLoops)
        page.placeNamespaces(clustered: clustered, clusterFrames: frames)
        return page
    }
}
