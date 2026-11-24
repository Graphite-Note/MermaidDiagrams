/**
 * File: FlowchartPageAssembly.swift
 * ---------------------------------
 * Layer: Core
 * Description: Puts a placed flowchart on the page.
 *
 * Authors: Félix Chevalier, Bahey Shalash
 * Version: 0.12
 * Date: 24/11/2026
 */

import CoreGraphics

/// Puts a placed flowchart on the page: nodes at their centers, edges from the outline of one shape to the other's
/// through their passing points, loops beside their nodes, the boxes of its groups with their titles, then everything
/// moved inside the padding below the title.
struct FlowchartPageAssembly {
    let diagram: FlowchartDiagram
    let measured: FlowchartMeasurement
    let axes: FlowchartFlowAxes
    private(set) var nodeCenters: [CGPoint] = []
    /// By edge index; nil until the edge is placed.
    private var edges: [FlowchartLayoutEdge?]
    /// A flowchart with groups: its nodes in boxes, which nodes stand for boxes, and each node's loop side.
    private var clustered: FlowchartClusterGraph?
    private var clusters: [FlowchartLayoutCluster] = []
    /// For each edge placed through boxes, the points it passes, its ends on their outlines: where it crosses a box's top.
    private var edgePoints: [[CGPoint]] = []

    init(diagram: FlowchartDiagram, measured: FlowchartMeasurement, axes: FlowchartFlowAxes) {
        self.diagram = diagram
        self.measured = measured
        self.axes = axes
        edges = Array(repeating: nil, count: diagram.edgeCount)
    }

    private func edgeAlong(_ points: [CGPoint], edgeIndex: Int, textCenter: CGPoint, segmentsRunVertically: [Bool]) -> FlowchartLayoutEdge {
        FlowchartPagePieces.edge(edgeIndex, of: diagram, along: points, segmentsRunVertically: segmentsRunVertically, textCenter: textCenter, measured: measured)
    }

    /// The loops of every node that has edges to itself; a group's from the middle of its box. An invisible loop, which
    /// is not drawn, does not count among the loops drawn before the next one.
    mutating func placeSelfLoops() {
        guard !measured.selfLoopEdgeIndices.isEmpty else { return }
        for node in 0..<diagram.nodeCount {
            let isGroup = clustered?.representedSubgraphs[node] != nil
            let flowRunsAcross = (clustered?.loopSides[node] ?? axes.loopSide) == .bottom
            var loopIndex = 0
            for edgeIndex in measured.selfLoopEdgeIndices[node] {
                let edge = FlowchartPagePieces.selfLoop(edgeIndex, of: diagram, node: node, center: nodeCenters[node],
                                                        shapeSize: isGroup ? .zero : measured.shapeSizes[node], loopIndex: loopIndex,
                                                        flowRunsAcross: flowRunsAcross, measured: measured)
                if edge.stroke != .invisible { loopIndex += 1 }
                edges[edgeIndex] = edge
            }
        }
    }

    /// The nodes of a flowchart laid out in boxes, at their centers on the page; a node that stands for a group at the
    /// center of its box, where it is not drawn.
    mutating func placeNodes(clustered: FlowchartClusterGraph, placement: LayeredClusterPlacement) {
        self.clustered = clustered
        nodeCenters = (0..<diagram.nodeCount).map { node in
            if let subgraph = clustered.representedSubgraphs[node] {
                return CGPoint(x: placement.clusterFrames[subgraph].midX, y: placement.clusterFrames[subgraph].midY)
            }
            return placement.nodeCenters[clustered.layoutNodeIndices[node] ?? 0]
        }
    }

    /// The edges of a flowchart laid out in boxes, along their routes: each end on the outline of its node or box, on
    /// the side its route leaves or arrives by, spread along it with the other ends there; each segment an S along its
    /// own flow.
    mutating func placeEdges(clustered: FlowchartClusterGraph, placement: LayeredClusterPlacement) {
        var ends: [FlowchartEdgePorts.End] = []
        let nodeCount = diagram.nodeCount
        func endItem(of node: Int) -> Int { clustered.representedSubgraphs[node].map { subgraph in nodeCount + subgraph } ?? node }
        for (layoutIndex, edgeIndex) in clustered.layoutEdgeIndices.enumerated() where !placement.strayEdgeIndices.contains(layoutIndex) {
            let route = placement.edgeRoutes[layoutIndex]
            let (source, target) = diagram.edgeEnds(at: edgeIndex)
            ends.append(Self.routeEnd(of: route, edgeIndex: edgeIndex, isSourceEnd: true, item: endItem(of: source)))
            ends.append(Self.routeEnd(of: route, edgeIndex: edgeIndex, isSourceEnd: false, item: endItem(of: target)))
        }
        let ports = boxedPorts(ends, placement: placement)
        for (layoutIndex, edgeIndex) in clustered.layoutEdgeIndices.enumerated() {
            let route = placement.edgeRoutes[layoutIndex]
            if placement.strayEdgeIndices.contains(layoutIndex) {
                // Between a group and something inside it: from one center to the other, its mark under the node, as Pele draws it.
                edges[edgeIndex] = edgeAlong(route.points, edgeIndex: edgeIndex, textCenter: placement.edgeLabelCenters[layoutIndex] ?? route.points[0],
                                             segmentsRunVertically: route.segmentsRunVertically)
                continue
            }
            let (source, target) = diagram.edgeEnds(at: edgeIndex)
            guard let sourcePoint = route.points.first.flatMap({ end in clusteredEnd(end, node: source, placement: placement) }) ?? ports.sources[edgeIndex],
                  let targetPoint = route.points.last.flatMap({ end in clusteredEnd(end, node: target, placement: placement) }) ?? ports.targets[edgeIndex]
            else { continue }
            let points = Self.joined(sourcePoint, route.points.dropFirst().dropLast(), targetPoint) { point in point }
            edgePoints.append(points)
            let textCenter = placement.edgeLabelCenters[layoutIndex]
                ?? CGPoint(x: (sourcePoint.x + targetPoint.x) / 2, y: (sourcePoint.y + targetPoint.y) / 2)
            edges[edgeIndex] = edgeAlong(points, edgeIndex: edgeIndex, textCenter: textCenter, segmentsRunVertically: route.segmentsRunVertically)
        }
    }

    /// Where the ends of the edges through boxes meet their nodes and boxes where the layout left none: spread along each
    /// side, clear of where other edges cross a box's border.
    private func boxedPorts(_ ends: [FlowchartEdgePorts.End], placement: LayeredClusterPlacement) -> (sources: [CGPoint?], targets: [CGPoint?]) {
        let nodeCount = diagram.nodeCount
        return DiagramScratchArena.withCurrentThread { arena in
            let endSpan: ScratchSpan<FlowchartEdgePorts.End> = arena.uninitializedSpan(count: ends.count)
            for (index, end) in ends.enumerated() { endSpan[index] = end }
            let itemCount = nodeCount + placement.clusterFrames.count
            let items = FlowchartEdgePorts.Items(count: itemCount, arena: arena)
            for node in 0..<nodeCount {
                items.centers[node] = nodeCenters[node]
                items.sizes[node] = measured.shapeSizes[node]
                items.spreadsEnds[node] = measured.spreadsEdgeEnds(of: node)
            }
            for (box, frame) in placement.clusterFrames.enumerated() {
                items.centers[nodeCount + box] = CGPoint(x: frame.midX, y: frame.midY)
                items.sizes[nodeCount + box] = frame.size
                items.spreadsEnds[nodeCount + box] = measured.spreadsEdgeEnds
            }
            let kept = FlowchartBorderCrossings.crossings(routes: placement.edgeRoutes, frames: placement.clusterFrames, firstBoxNode: nodeCount,
                                                          arena: arena)
            let points = FlowchartEdgePorts.Points(edgeCount: diagram.edgeCount, arena: arena)
            FlowchartEdgePorts.place(endSpan, items: items, of: diagram, measured: measured, keptClear: kept, into: points, arena: arena)
            return ((0..<diagram.edgeCount).map(points.sourcePoint(of:)), (0..<diagram.edgeCount).map(points.targetPoint(of:)))
        }
    }

    /// `first`, the points between, each put through `place`, and `last`, in one list made once.
    private static func joined(_ first: CGPoint, _ between: ArraySlice<CGPoint>, _ last: CGPoint, through place: (CGPoint) -> CGPoint) -> [CGPoint] {
        var points: [CGPoint] = []
        points.reserveCapacity(between.count + 2)
        points.append(first)
        for point in between { points.append(place(point)) }
        points.append(last)
        return points
    }

    /// A route's end on the outline of `node`'s shape, from the side of its layout box the layout left it on.
    private func outlineEnd(_ end: CGPoint, node: Int, loopSide: DiagramSide) -> CGPoint? {
        FlowchartRouteEnds.outlinePoint(of: end, center: nodeCenters[node], boxSize: measured.layoutSize(of: node, loopSide: loopSide),
                                        shape: measured.layoutShape(of: node, in: diagram),
                                        shapeSize: measured.shapeSizes[node])
    }

    /// A route's end through boxes on its node's outline, or on the box of the group the node stands for.
    private func clusteredEnd(_ end: CGPoint, node: Int, placement: LayeredClusterPlacement) -> CGPoint? {
        guard let clustered else { return nil }
        if let subgraph = clustered.representedSubgraphs[node] {
            let frame = placement.clusterFrames[subgraph]
            return FlowchartRouteEnds.outlinePoint(of: end, center: CGPoint(x: frame.midX, y: frame.midY), boxSize: frame.size, shape: .rectangle,
                                                   shapeSize: frame.size)
        }
        return outlineEnd(end, node: node, loopSide: clustered.loopSides[node])
    }

    /// An end of a route through boxes: the side of its node or box that its first or last segment leaves or arrives
    /// by, along that segment's flow, and where along the side the route goes next.
    private static func routeEnd(of route: LayeredClusterRoute, edgeIndex: Int, isSourceEnd: Bool, item: Int) -> FlowchartEdgePorts.End {
        let points = route.points
        let end = isSourceEnd ? points[0] : points[points.count - 1]
        let next = isSourceEnd ? points[1] : points[points.count - 2]
        let runsVertically = isSourceEnd ? route.segmentsRunVertically[0] : route.segmentsRunVertically[route.segmentsRunVertically.count - 1]
        let side: DiagramSide = runsVertically ? (next.y > end.y ? .bottom : .top) : (next.x > end.x ? .right : .left)
        return FlowchartEdgePorts.End(edgeIndex: edgeIndex, isSourceEnd: isSourceEnd, node: item, side: side,
                                      neighborAcross: side.isHorizontal ? next.x : next.y)
    }

    /// The groups' boxes, each title along its box's top, clear of the edges where it can be.
    mutating func placeClusters(clustered: FlowchartClusterGraph, placement: LayeredClusterPlacement) {
        let crossings = FlowchartRoutePointIndex(edgePoints)
        clusters = placement.clusterFrames.enumerated().map { subgraph, frame in
            let title = clustered.titles[subgraph].map { title in FlowchartClusterTitles.placed(title, in: frame, crossings: crossings) }
            return FlowchartLayoutCluster(frame: frame, title: title?.title, depth: clustered.depths[subgraph], isTitleCrossed: title?.isCrossed ?? false)
        }
    }

    /// The finished layout: everything moved so that the drawing starts `padding` from the top left, below the
    /// title, and centered under the title when the title is wider. The drawing is the layout's box, `extent` on the
    /// page from the origin, as Pele sizes its page from the layout's width and height.
    func finished(font: DiagramFont, title: DiagramTextBlock?, padding: CGFloat, titleGap: CGFloat, extent: CGSize) -> FlowchartLayout {
        func placedNode(_ node: Int) -> FlowchartLayoutNode {
            FlowchartPagePieces.node(node, of: diagram, center: nodeCenters[node], measured: measured)
        }
        let bounds = CGRect(origin: .zero, size: extent)
        let titleSize = title?.size ?? .zero
        let innerWidth = max(bounds.width, titleSize.width)
        let titleHeight = title == nil ? 0 : titleSize.height + titleGap
        let offset = CGVector(dx: padding + (innerWidth - bounds.width) / 2 - bounds.minX, dy: padding + titleHeight - bounds.minY)
        let size = CGSize(width: (innerWidth + 2 * padding).rounded(.up), height: (bounds.height + titleHeight + 2 * padding).rounded(.up))
        var placedTitle = title
        placedTitle?.center = CGPoint(x: size.width / 2, y: padding + titleSize.height / 2)
        // A node that stands for a group is its box, not a node. Each list is made once, as long as what it holds.
        let isDrawn = { (node: Int) in clustered?.representedSubgraphs[node] == nil }
        var nodes: [FlowchartLayoutNode] = []
        nodes.reserveCapacity((0..<diagram.nodeCount).reduce(0) { count, node in isDrawn(node) ? count + 1 : count })
        for node in 0..<diagram.nodeCount where isDrawn(node) { nodes.append(placedNode(node).translated(by: offset)) }
        var placedEdges: [FlowchartLayoutEdge] = []
        placedEdges.reserveCapacity(edges.reduce(0) { count, edge in edge == nil ? count : count + 1 })
        for case let edge? in edges { placedEdges.append(edge.translated(by: offset)) }
        return FlowchartLayout(size: size, font: font, nodes: nodes, edges: placedEdges, title: placedTitle,
                               clusters: clusters.map { cluster in cluster.translated(by: offset) })
    }
}
