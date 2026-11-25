/**
 * File: SwimlanePageAssembly.swift
 * --------------------------------
 * Layer: Core
 * Description: Puts a swimlane diagram's lane layout on the page as Pele's flowchart renderer draws its swimlane variant:
 *              nodes, edges onto their shapes' outlines, loops, the groups inside lanes and the lanes, read from the lane
 *              layout's placement where it lies in the thread's scratch arena.
 *
 * Authors: Bahey Shalash
 * Version: 0.8
 * Date: 25/11/2026
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
    /// Where the lane layout put everything, in the calling thread's arena: the assembly lasts no longer than it.
    let placement: LaneLayoutPlacedView
    private var edges: [FlowchartLayoutEdge?]
    /// The points each edge's route passes, its ends on their outlines: where it crosses a group's top. Kept only when a
    /// group sits inside a lane, whose title they move.
    private var edgePoints: [[CGPoint]] = []

    init(diagram: FlowchartDiagram, measured: FlowchartMeasurement, graph: SwimlaneGraph, placement: LaneLayoutPlacedView, arena: DiagramScratchArena) {
        self.diagram = diagram
        self.measured = measured
        self.graph = graph
        self.placement = placement
        edges = Array(repeating: nil, count: diagram.edgeCount)
        placeEdges(arena: arena)
        placeSelfLoops()
    }

    private func center(ofNode node: Int) -> CGPoint {
        let frame = placement.frames[graph.nodeBoxes[node]]
        return CGPoint(x: frame.midX, y: frame.midY)
    }

    private mutating func placeEdges(arena: DiagramScratchArena) {
        let reaches = sideReaches(arena: arena)
        let keepsEdgePoints = graph.nesting.subgraphParents.contains { parent in parent != nil }
        for (edgeIndex, edge) in diagram.edgeDrawings.enumerated() {
            let route = placement.route(of: edgeIndex)
            guard route.count >= 2 else { continue }
            var points = route.map(\.point)
            let segmentsRunVertically = route.dropFirst().map { point in point.axis == 0 }
            let startReach = reach(at: points[0], box: graph.nodeBoxes[edge.sourceIndex], in: reaches)
            let endReach = reach(at: points[points.count - 1], box: graph.nodeBoxes[edge.targetIndex], in: reaches)
            points[0] = onOutline(points[0], node: edge.sourceIndex)
            points[points.count - 1] = onOutline(points[points.count - 1], node: edge.targetIndex)
            if keepsEdgePoints { edgePoints.append(points) }
            let startTrim = DiagramEdgeMark.lineTrim(for: edge.sourceArrowhead)
            let endTrim = DiagramEdgeMark.lineTrim(for: edge.targetArrowhead)
            let drawn = DiagramTurningRouteDrawing.path(through: points, segmentsRunVertically: segmentsRunVertically, startTrim: startTrim, endTrim: endTrim,
                                                        startReach: startReach, endReach: endReach)
            let leaving = CGVector(dx: -drawn.startDirection.dx, dy: -drawn.startDirection.dy)
            edges[edgeIndex] = FlowchartLayoutEdge(stroke: edge.stroke, path: drawn.path,
                                                   sourceMark: Self.mark(edge.sourceArrowhead, tip: points[0], direction: leaving),
                                                   targetMark: Self.mark(edge.targetArrowhead, tip: points[points.count - 1], direction: drawn.endDirection),
                                                   text: Self.centered(measured.edgeTexts[edgeIndex], at: placement.labelCenters[edgeIndex]), style: edge.style)
        }
    }

    /// How far from each side of each box the edges that meet it start to turn, as Pele's `sideReach` sets it: as far as the
    /// largest mark there needs, with the lead, for every edge on that side, so that none turns sooner than its neighbour and
    /// crosses it. By box and side (`sideKey`), 0 for a side no edge with a mark meets; an edge to itself or one not drawn
    /// counts for none.
    private func sideReaches(arena: DiagramScratchArena) -> ScratchSpan<CGFloat> {
        let reaches = arena.span(count: 4 * placement.frames.count, repeating: CGFloat(0))
        func reach(_ point: CGPoint, box: Int, arrowhead: FlowchartArrowhead) {
            let trim = DiagramEdgeMark.lineTrim(for: arrowhead)
            guard trim > 0, let key = sideKey(at: point, box: box) else { return }
            reaches[key] = max(reaches[key], DiagramTurningRouteDrawing.defaultReach(trim: trim))
        }
        for (edgeIndex, edge) in diagram.edgeDrawings.enumerated() where edge.stroke != .invisible {
            let route = placement.route(of: edgeIndex)
            guard route.count >= 2 else { continue }
            reach(route[0].point, box: graph.nodeBoxes[edge.sourceIndex], arrowhead: edge.sourceArrowhead)
            reach(route[route.count - 1].point, box: graph.nodeBoxes[edge.targetIndex], arrowhead: edge.targetArrowhead)
        }
        return reaches
    }

    /// The reach of the side of `box` that `point` is on, 0 for a point on no side, as Pele's `sideReach` gives it.
    private func reach(at point: CGPoint, box: Int, in reaches: ScratchSpan<CGFloat>) -> CGFloat {
        sideKey(at: point, box: box).map { key in reaches[key] } ?? 0
    }

    private func sideKey(at point: CGPoint, box: Int) -> Int? {
        Self.side(of: point, on: placement.frames[box]).map { side in
            let sideNumber = switch side {
            case .top: 0
            case .right: 1
            case .bottom: 2
            case .left: 3
            }
            return box * 4 + sideNumber
        }
    }

    /// The side of `frame` that `point` lies on, within half a point, as Pele's `endSide` finds it, or nil.
    static func side(of point: CGPoint, on frame: CGRect) -> DiagramSide? {
        let offset = CGPoint(x: point.x - frame.midX, y: point.y - frame.midY)
        if abs(abs(offset.y) - frame.height / 2) < 0.5 { return offset.y < 0 ? .top : .bottom }
        if abs(abs(offset.x) - frame.width / 2) < 0.5 { return offset.x < 0 ? .left : .right }
        return nil
    }

    /// A route's end moved from its node's box onto the outline of the shape drawn in it, as Pele's `insetRoute` moves it;
    /// a group's end, and one on no side of its box, stay.
    private func onOutline(_ point: CGPoint, node: Int) -> CGPoint {
        guard graph.nesting.representedSubgraphs[node] == nil else { return point }
        let frame = placement.frames[graph.nodeBoxes[node]]
        guard let side = Self.side(of: point, on: frame) else { return point }
        let shape = measured.layoutShape(of: node, in: diagram)
        return FlowchartEdgePorts.outlinePoint(center: CGPoint(x: frame.midX, y: frame.midY), shape: shape,
                                               size: measured.shapeSizes[node], side: side,
                                               offset: side.isHorizontal ? point.x - frame.midX : point.y - frame.midY)
    }

    /// The loops of every node that has edges to itself, as Pele's `loopPath` draws them (`FlowchartSelfLoops`); a group's
    /// from the middle of its box, as Pele loops a group whose drawn node has no size. An invisible loop, which is not drawn,
    /// does not count among the loops drawn before the next one.
    private mutating func placeSelfLoops() {
        guard !measured.selfLoopEdgeIndices.isEmpty else { return }
        for node in 0..<diagram.nodeCount {
            let loopEdgeIndices = measured.selfLoopEdgeIndices[node]
            let isGroup = graph.nesting.representedSubgraphs[node] != nil
            var loopIndex = 0
            for edgeIndex in loopEdgeIndices {
                let edge = diagram.edgeDrawing(at: edgeIndex)
                defer { if edge.stroke != .invisible { loopIndex += 1 } }
                let text = measured.edgeTexts[edgeIndex]
                let loop = FlowchartSelfLoops.loop(center: center(ofNode: node), shapeSize: isGroup ? .zero : measured.shapeSizes[node], loopIndex: loopIndex,
                                                  flowRunsAcross: diagram.direction.runsAcross, endTrim: DiagramEdgeMark.lineTrim(for: edge.targetArrowhead),
                                                  textSize: text?.size)
                edges[edgeIndex] = FlowchartLayoutEdge(stroke: edge.stroke, path: loop.path,
                                                       sourceMark: Self.mark(edge.sourceArrowhead, tip: loop.leave, direction: loop.intoNodeAtLeave),
                                                       targetMark: Self.mark(edge.targetArrowhead, tip: loop.back, direction: loop.arriving),
                                                       text: Self.centered(text, at: loop.textCenter), style: edge.style)
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
        let nodes = (0..<diagram.nodeCount).filter { node in graph.nesting.representedSubgraphs[node] == nil }.map { node in placedNode(node).translated(by: offset) }
        let flowchart = FlowchartLayout(size: size, font: font, nodes: nodes, edges: edges.compactMap { edge in edge?.translated(by: offset) },
                                        title: placedTitle, clusters: groupsInsideLanes().map { cluster in cluster.translated(by: offset) })
        return SwimlaneLayout(flowchart: flowchart, lanes: lanes().map { lane in lane.translated(by: offset) })
    }

    private func placedNode(_ node: Int) -> FlowchartLayoutNode {
        let center = center(ofNode: node)
        var text = measured.nodeTexts[node]
        text.center = CGPoint(x: center.x, y: center.y + measured.textOffsets[node])
        let size = measured.shapeSizes[node]
        return FlowchartLayoutNode(shape: diagram.nodeShape(at: node),
                                   frame: CGRect(x: center.x - size.width / 2, y: center.y - size.height / 2, width: size.width, height: size.height),
                                   text: text, style: diagram.nodeStyle(at: node), asset: diagram.nodeAsset(at: node))
    }

    /// The groups inside lanes, each title along its box's top, clear of the edges where it can be, their depths counted from
    /// the lane they are in.
    private func groupsInsideLanes() -> [FlowchartLayoutCluster] {
        let crossings = FlowchartRoutePointIndex(edgePoints)
        return (0..<diagram.subgraphCount).compactMap { subgraph in
            guard graph.nesting.subgraphParents[subgraph] != nil else { return nil }
            let frame = placement.frames[graph.subgraphBoxes[subgraph]]
            let title = graph.titles[subgraph].map { title in FlowchartClusterTitles.placed(title, in: frame, crossings: crossings) }
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
