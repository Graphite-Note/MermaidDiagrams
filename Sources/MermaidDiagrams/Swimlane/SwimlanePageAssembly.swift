/**
 * File: SwimlanePageAssembly.swift
 * --------------------------------
 * Layer: Core
 * Description: Puts a swimlane diagram's lane layout on the page as Pele's flowchart renderer draws its swimlane variant:
 *              nodes, edges onto their shapes' outlines, loops, the groups inside lanes and the lanes.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 19/11/2026
 */

import CoreGraphics

/// Puts a placed swimlane diagram on the page, as Pele's `renderFlowchart` draws it with the swimlane variant: each node at
/// its box's center; each edge along its route, its ends moved from its nodes' boxes onto their shapes' outlines (a group's
/// end stays on its border), each segment an S along its own flow, with its marks and text; loops beside their nodes (a
/// group's from the middle of its box); the groups inside lanes as a flowchart's boxes; the lanes with their title bands;
/// then everything moved 8 points inside the page, below the title.
struct SwimlanePageAssembly {
    let diagram: FlowchartDiagram
    let measured: FlowchartMeasurement
    let graph: SwimlaneGraph
    let placement: LaneLayoutPlacement
    private var edges: [FlowchartLayoutEdge?]
    /// The points each edge's route passes, its ends on their outlines: where it crosses a group's top.
    private var edgePoints: [[CGPoint]] = []

    init(diagram: FlowchartDiagram, measured: FlowchartMeasurement, graph: SwimlaneGraph, placement: LaneLayoutPlacement) {
        self.diagram = diagram
        self.measured = measured
        self.graph = graph
        self.placement = placement
        edges = Array(repeating: nil, count: diagram.edges.count)
        placeEdges()
        placeSelfLoops()
    }

    private var loopSide: DiagramSide { diagram.direction.runsAcross ? .bottom : .right }

    private func center(ofNode node: Int) -> CGPoint {
        let frame = placement.frames[graph.nodeBoxes[node]]
        return CGPoint(x: frame.midX, y: frame.midY)
    }

    private mutating func placeEdges() {
        for (edgeIndex, edge) in diagram.edges.enumerated() {
            guard let route = placement.routes[edgeIndex] else { continue }
            var points = route.points
            points[0] = onOutline(points[0], node: edge.sourceIndex)
            points[points.count - 1] = onOutline(points[points.count - 1], node: edge.targetIndex)
            edgePoints.append(points)
            let startTrim = DiagramEdgeMark.lineTrim(for: edge.sourceArrowhead)
            let endTrim = DiagramEdgeMark.lineTrim(for: edge.targetArrowhead)
            let drawn = DiagramTurningRouteDrawing.path(through: points, segmentsRunVertically: route.segmentsRunVertically, startTrim: startTrim, endTrim: endTrim)
            let leaving = CGVector(dx: -drawn.startDirection.dx, dy: -drawn.startDirection.dy)
            edges[edgeIndex] = FlowchartLayoutEdge(stroke: edge.stroke, path: drawn.path,
                                                   sourceMark: Self.mark(edge.sourceArrowhead, tip: points[0], direction: leaving),
                                                   targetMark: Self.mark(edge.targetArrowhead, tip: points[points.count - 1], direction: drawn.endDirection),
                                                   text: Self.centered(measured.edgeTexts[edgeIndex], at: placement.labelCenters[edgeIndex]), style: edge.style)
        }
    }

    /// A route's end moved from its node's box onto the outline of the shape drawn in it, as Pele's `insetRoute` moves it;
    /// a group's end, and one on no side of its box, stay.
    private func onOutline(_ point: CGPoint, node: Int) -> CGPoint {
        guard graph.nesting.representedSubgraphs[node] == nil else { return point }
        let frame = placement.frames[graph.nodeBoxes[node]]
        let offset = CGPoint(x: point.x - frame.midX, y: point.y - frame.midY)
        let side: DiagramSide
        if abs(abs(offset.y) - frame.height / 2) < 0.5 {
            side = offset.y < 0 ? .top : .bottom
        } else if abs(abs(offset.x) - frame.width / 2) < 0.5 {
            side = offset.x < 0 ? .left : .right
        } else {
            return point
        }
        return FlowchartEdgePorts.outlinePoint(center: CGPoint(x: frame.midX, y: frame.midY), shape: diagram.nodes[node].shape,
                                               size: measured.shapeSizes[node], side: side, offset: side.isHorizontal ? offset.x : offset.y)
    }

    /// The loops of every node that has edges to itself; a group's from the middle of its box, as Pele loops a group whose
    /// drawn node has no size.
    private mutating func placeSelfLoops() {
        for (node, loopEdgeIndices) in measured.selfLoopEdgeIndices.enumerated() {
            let isGroup = graph.nesting.representedSubgraphs[node] != nil
            for (loopIndex, edgeIndex) in loopEdgeIndices.enumerated() {
                let edge = diagram.edges[edgeIndex]
                let loop = FlowchartSelfLoops.loop(center: center(ofNode: node), shape: diagram.nodes[node].shape, size: isGroup ? .zero : measured.shapeSizes[node],
                                                   loopSide: loopSide, loopIndex: loopIndex, textSize: measured.edgeTexts[edgeIndex]?.size)
                let arriving = Self.unitVector(from: loop.control2, to: loop.back)
                let leaving = Self.unitVector(from: loop.control1, to: loop.leave)
                let startTrim = DiagramEdgeMark.lineTrim(for: edge.sourceArrowhead)
                let endTrim = DiagramEdgeMark.lineTrim(for: edge.targetArrowhead)
                let start = CGPoint(x: loop.leave.x - leaving.dx * startTrim, y: loop.leave.y - leaving.dy * startTrim)
                let end = CGPoint(x: loop.back.x - arriving.dx * endTrim, y: loop.back.y - arriving.dy * endTrim)
                edges[edgeIndex] = FlowchartLayoutEdge(stroke: edge.stroke,
                                                       path: DiagramPath(start: start, segments: [.curve(to: end, control1: loop.control1, control2: loop.control2)]),
                                                       sourceMark: Self.mark(edge.sourceArrowhead, tip: loop.leave, direction: leaving),
                                                       targetMark: Self.mark(edge.targetArrowhead, tip: loop.back, direction: arriving),
                                                       text: loop.textCenter.flatMap { center in Self.centered(measured.edgeTexts[edgeIndex], at: center) },
                                                       style: edge.style)
            }
        }
    }

    static func mark(_ arrowhead: FlowchartArrowhead, tip: CGPoint, direction: CGVector) -> DiagramEdgeMark? {
        arrowhead == .none ? nil : DiagramEdgeMark(arrowhead: arrowhead, tip: tip, direction: direction)
    }

    static func centered(_ text: DiagramTextBlock?, at center: CGPoint) -> DiagramTextBlock? {
        guard var text else { return nil }
        text.center = center
        return text
    }

    private static func unitVector(from start: CGPoint, to end: CGPoint) -> CGVector {
        let length = max(((end.x - start.x) * (end.x - start.x) + (end.y - start.y) * (end.y - start.y)).squareRoot(), 0.0001)
        return CGVector(dx: (end.x - start.x) / length, dy: (end.y - start.y) / length)
    }
}

extension SwimlanePageAssembly {
    /// The finished layout: the lane layout's extent moved `padding` inside the page, below the title and centered under it
    /// when the title is wider, as Pele frames a flowchart.
    func finished(font: DiagramFont, title: DiagramTextBlock?, padding: CGFloat, titleGap: CGFloat) -> SwimlaneLayout {
        let titleSize = title?.size ?? .zero
        let titleHeight = title == nil ? 0 : titleSize.height + titleGap
        let innerWidth = max(placement.size.width, titleSize.width)
        let offset = CGVector(dx: padding + (innerWidth - placement.size.width) / 2, dy: padding + titleHeight)
        let size = CGSize(width: (innerWidth + 2 * padding).rounded(.up), height: (placement.size.height + titleHeight + 2 * padding).rounded(.up))
        var placedTitle = title
        placedTitle?.center = CGPoint(x: size.width / 2, y: padding + titleSize.height / 2)
        let nodes = diagram.nodes.indices.filter { node in graph.nesting.representedSubgraphs[node] == nil }.map { node in placedNode(node).translated(by: offset) }
        let flowchart = FlowchartLayout(size: size, font: font, nodes: nodes, edges: edges.compactMap { edge in edge?.translated(by: offset) },
                                        title: placedTitle, clusters: groupsInsideLanes().map { cluster in cluster.translated(by: offset) })
        return SwimlaneLayout(flowchart: flowchart, lanes: lanes().map { lane in lane.translated(by: offset) })
    }

    private func placedNode(_ node: Int) -> FlowchartLayoutNode {
        let center = center(ofNode: node)
        var text = measured.nodeTexts[node]
        text.center = CGPoint(x: center.x, y: center.y + measured.textOffsets[node])
        let size = measured.shapeSizes[node]
        return FlowchartLayoutNode(shape: diagram.nodes[node].shape,
                                   frame: CGRect(x: center.x - size.width / 2, y: center.y - size.height / 2, width: size.width, height: size.height),
                                   text: text, style: diagram.nodes[node].style)
    }

    /// The groups inside lanes, each title along its box's top, clear of the edges where it can be, their depths counted from
    /// the lane they are in.
    private func groupsInsideLanes() -> [FlowchartLayoutCluster] {
        return diagram.subgraphs.indices.compactMap { subgraph in
            guard graph.nesting.subgraphParents[subgraph] != nil else { return nil }
            let frame = placement.frames[graph.subgraphBoxes[subgraph]]
            let title = graph.titles[subgraph].map { title in FlowchartClusterTitles.placed(title, in: frame, edgePoints: edgePoints) }
            return FlowchartLayoutCluster(frame: frame, title: title?.title, depth: graph.nesting.subgraphDepths[subgraph] - 1,
                                          isTitleCrossed: title?.isCrossed ?? false)
        }
    }

    /// The lanes in the order they are placed, each title centered in the band at its start, turned where the flow runs across.
    private func lanes() -> [SwimlaneLayoutLane] {
        let isTurned = diagram.direction.runsAcross
        let depth = placement.laneTitleDepth
        return placement.lanes.map { box in
            let frame = placement.frames[box]
            let band = isTurned ? CGRect(x: frame.minX, y: frame.minY, width: depth, height: frame.height)
                                : CGRect(x: frame.minX, y: frame.minY, width: frame.width, height: depth)
            let subgraph = graph.subgraphBoxes.firstIndex(of: box)
            let title = subgraph.flatMap { subgraph in Self.centered(graph.titles[subgraph], at: CGPoint(x: band.midX, y: band.midY)) }
            return SwimlaneLayoutLane(frame: frame, titleBand: band, title: title, isTitleTurned: isTurned)
        }
    }
}
