/**
 * File: FlowchartPageAssembly.swift
 * ---------------------------------
 * Layer: Core
 * Description: Puts a placed flowchart on the page.
 *
 * Authors: Félix Chevalier, Bahey Shalash
 * Version: 0.11
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

    mutating func placeNodes(flowCenters: [CGPoint]) {
        nodeCenters = flowCenters.map(axes.pagePoint)
    }

    /// The edges between two different nodes, along their routes. `layeredEdgeIndices[i]` is the edge of the
    /// placement's `i`-th route.
    mutating func placeEdges(layeredEdgeIndices: [Int], placement: LayeredPlacement) {
        var ends: [FlowchartEdgePorts.End] = []
        ends.reserveCapacity(2 * layeredEdgeIndices.count)
        for (layeredIndex, edgeIndex) in layeredEdgeIndices.enumerated() {
            let route = placement.edgeRoutes[layeredIndex]
            let (source, target) = diagram.edgeEnds(at: edgeIndex)
            let leavesDownstream = route[1].y > route[0].y
            let arrivesFromUpstream = route[route.count - 2].y < route[route.count - 1].y
            ends.append(FlowchartEdgePorts.End(edgeIndex: edgeIndex, isSourceEnd: true, node: source,
                                               side: leavesDownstream ? axes.downstreamSide : axes.upstreamSide, neighborAcross: route[1].x))
            ends.append(FlowchartEdgePorts.End(edgeIndex: edgeIndex, isSourceEnd: false, node: target,
                                               side: arrivesFromUpstream ? axes.upstreamSide : axes.downstreamSide,
                                               neighborAcross: route[route.count - 2].x))
        }
        let ports = FlowchartEdgePorts(ends: ends, edgeCount: diagram.edgeCount, nodeCenters: nodeCenters, shapes: measured.layoutShapes(of: diagram),
                                       shapeSizes: measured.shapeSizes, spreadsEnds: measured.spreadsEdgeEnds, endsAtMiddle: measured.assetNodes)
        for (layeredIndex, edgeIndex) in layeredEdgeIndices.enumerated() {
            let route = placement.edgeRoutes[layeredIndex]
            // Each end where Pele's layout settled it, moved onto its shape's outline; the spread ends where it left none.
            // Only the path's two ends are read, each put on the page alone.
            let path = placement.edgePaths[layeredIndex]
            let (source, target) = diagram.edgeEnds(at: edgeIndex)
            guard let sourcePoint = path.first.map(axes.pagePoint).flatMap({ end in outlineEnd(end, node: source, loopSide: axes.loopSide) })
                      ?? ports.sourcePoints[edgeIndex],
                  let targetPoint = path.last.map(axes.pagePoint).flatMap({ end in outlineEnd(end, node: target, loopSide: axes.loopSide) })
                      ?? ports.targetPoints[edgeIndex]
            else { continue }
            let points = Self.joined(sourcePoint, route.dropFirst().dropLast(), targetPoint, through: axes.pagePoint)
            let textCenter = placement.edgeLabelCenters[layeredIndex].map(axes.pagePoint)
                ?? CGPoint(x: (sourcePoint.x + targetPoint.x) / 2, y: (sourcePoint.y + targetPoint.y) / 2)
            edges[edgeIndex] = edgeAlong(points, edgeIndex: edgeIndex, textCenter: textCenter)
        }
    }

    private func edgeAlong(_ points: [CGPoint], edgeIndex: Int, textCenter: CGPoint, segmentsRunVertically: [Bool]? = nil) -> FlowchartLayoutEdge {
        let edge = diagram.edgeDrawing(at: edgeIndex)
        let startTrim = DiagramEdgeMark.lineTrim(for: edge.sourceArrowhead)
        let endTrim = DiagramEdgeMark.lineTrim(for: edge.targetArrowhead)
        let drawn = segmentsRunVertically.map { axes in
            DiagramRouteDrawing.path(through: points, segmentsRunVertically: axes, startTrim: startTrim, endTrim: endTrim)
        } ?? DiagramRouteDrawing.path(through: points, flowIsVertical: axes.flowIsVertical, startTrim: startTrim, endTrim: endTrim)
        let leaving = CGVector(dx: -drawn.startDirection.dx, dy: -drawn.startDirection.dy)
        return FlowchartLayoutEdge(stroke: edge.stroke, path: drawn.path,
                                   sourceMark: mark(edge.sourceArrowhead, tip: points[0], direction: leaving),
                                   targetMark: mark(edge.targetArrowhead, tip: points[points.count - 1], direction: drawn.endDirection),
                                   text: centered(measured.edgeTexts[edgeIndex], at: textCenter), style: edge.style)
    }

    /// The loops of every node that has edges to itself, as Pele's `loopPath` draws them (`FlowchartSelfLoops`); a group's
    /// from the middle of its box, as Pele loops a group whose drawn node has no size. An invisible loop, which is not drawn,
    /// does not count among the loops drawn before the next one.
    mutating func placeSelfLoops() {
        for (node, loopEdgeIndices) in measured.selfLoopEdgeIndices.enumerated() {
            let isGroup = clustered?.representedSubgraphs[node] != nil
            let flowRunsAcross = (clustered?.loopSides[node] ?? axes.loopSide) == .bottom
            var loopIndex = 0
            for edgeIndex in loopEdgeIndices {
                let edge = diagram.edgeDrawing(at: edgeIndex)
                defer { if edge.stroke != .invisible { loopIndex += 1 } }
                let text = measured.edgeTexts[edgeIndex]
                let loop = FlowchartSelfLoops.loop(center: nodeCenters[node], shapeSize: isGroup ? .zero : measured.shapeSizes[node], loopIndex: loopIndex,
                                                   flowRunsAcross: flowRunsAcross, endTrim: DiagramEdgeMark.lineTrim(for: edge.targetArrowhead),
                                                   textSize: text?.size)
                edges[edgeIndex] = FlowchartLayoutEdge(stroke: edge.stroke, path: loop.path,
                                                       sourceMark: mark(edge.sourceArrowhead, tip: loop.leave, direction: loop.intoNodeAtLeave),
                                                       targetMark: mark(edge.targetArrowhead, tip: loop.back, direction: loop.arriving),
                                                       text: centered(text, at: loop.textCenter), style: edge.style)
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
        let boxCenters = placement.clusterFrames.map { frame in CGPoint(x: frame.midX, y: frame.midY) }
        let ports = FlowchartEdgePorts(ends: ends, edgeCount: diagram.edgeCount, nodeCenters: nodeCenters + boxCenters,
                                       shapes: measured.layoutShapes(of: diagram) + Array(repeating: .rectangle, count: boxCenters.count),
                                       shapeSizes: measured.shapeSizes + placement.clusterFrames.map { frame in frame.size },
                                       keptClear: FlowchartBorderCrossings.crossings(routes: placement.edgeRoutes, frames: placement.clusterFrames,
                                                                                 firstBoxNode: nodeCount),
                                       spreadsEnds: measured.spreadsEdgeEnds, endsAtMiddle: measured.assetNodes)
        for (layoutIndex, edgeIndex) in clustered.layoutEdgeIndices.enumerated() {
            let route = placement.edgeRoutes[layoutIndex]
            if placement.strayEdgeIndices.contains(layoutIndex) {
                // Between a group and something inside it: from one center to the other, its mark under the node, as Pele draws it.
                edges[edgeIndex] = edgeAlong(route.points, edgeIndex: edgeIndex, textCenter: placement.edgeLabelCenters[layoutIndex] ?? route.points[0],
                                             segmentsRunVertically: route.segmentsRunVertically)
                continue
            }
            let (source, target) = diagram.edgeEnds(at: edgeIndex)
            guard let sourcePoint = route.points.first.flatMap({ end in clusteredEnd(end, node: source, placement: placement) }) ?? ports.sourcePoints[edgeIndex],
                  let targetPoint = route.points.last.flatMap({ end in clusteredEnd(end, node: target, placement: placement) }) ?? ports.targetPoints[edgeIndex]
            else { continue }
            let points = Self.joined(sourcePoint, route.points.dropFirst().dropLast(), targetPoint) { point in point }
            edgePoints.append(points)
            let textCenter = placement.edgeLabelCenters[layoutIndex]
                ?? CGPoint(x: (sourcePoint.x + targetPoint.x) / 2, y: (sourcePoint.y + targetPoint.y) / 2)
            edges[edgeIndex] = edgeAlong(points, edgeIndex: edgeIndex, textCenter: textCenter, segmentsRunVertically: route.segmentsRunVertically)
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
                                        shape: measured.assetNodes.contains(node) ? .rectangle : diagram.nodeShape(at: node),
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

    private func mark(_ arrowhead: FlowchartArrowhead, tip: CGPoint, direction: CGVector) -> DiagramEdgeMark? {
        arrowhead == .none ? nil : DiagramEdgeMark(arrowhead: arrowhead, tip: tip, direction: direction)
    }

    private func centered(_ text: DiagramTextBlock?, at center: CGPoint) -> DiagramTextBlock? {
        guard var text else { return nil }
        text.center = center
        return text
    }

    /// The finished layout: everything moved so that the drawing starts `padding` from the top left, below the
    /// title, and centered under the title when the title is wider. The drawing is the layout's box, `extent` on the
    /// page from the origin, as Pele sizes its page from the layout's width and height.
    func finished(font: DiagramFont, title: DiagramTextBlock?, padding: CGFloat, titleGap: CGFloat, extent: CGSize) -> FlowchartLayout {
        func placedNode(_ node: Int) -> FlowchartLayoutNode {
            var text = measured.nodeTexts[node]
            text.center = CGPoint(x: nodeCenters[node].x, y: nodeCenters[node].y + measured.textOffsets[node])
            let size = measured.shapeSizes[node]
            return FlowchartLayoutNode(shape: diagram.nodeShape(at: node),
                                       frame: CGRect(x: nodeCenters[node].x - size.width / 2, y: nodeCenters[node].y - size.height / 2,
                                                     width: size.width, height: size.height),
                                       text: text, style: diagram.nodeStyle(at: node), asset: diagram.nodeAsset(at: node))
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
