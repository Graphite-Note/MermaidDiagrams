/**
 * File: SwimlanePageAssembly.swift
 * --------------------------------
 * Layer: Core
 * Description: Puts a swimlane diagram's lane layout on the page as Pele's flowchart renderer draws its swimlane variant:
 *              nodes, edges onto their shapes' outlines, loops, the groups inside lanes and the lanes, read from the lane
 *              layout's placement where it lies in the thread's scratch arena, each edge moved onto the page as it is made.
 *
 * Authors: Bahey Shalash
 * Version: 0.9
 * Date: 26/11/2026
 */

import CoreGraphics

/// Puts a placed swimlane diagram on the page, as Pele's `renderFlowchart` draws it with the swimlane variant: each node at
/// its box's center; each edge along its route, its ends moved from its nodes' boxes onto their shapes' outlines (a group's
/// end stays on its border), each segment an S along its own flow, with its marks and text; loops beside their nodes (a
/// group's from the middle of its box); the groups inside lanes as a flowchart's boxes; the lanes with their title bands;
/// then everything moved 8 points inside the page, below the title (`SwimlanePageFrame`).
///
/// An edge is moved onto the page as soon as it is made, with the very additions moving the finished layout would make:
/// its path's points moved where they lie, so that no edge is made twice.
struct SwimlanePageAssembly {
    let diagram: FlowchartDiagram
    let measured: FlowchartMeasurement
    let graph: SwimlaneGraph
    /// Where the lane layout put everything, in the calling thread's arena: the assembly lasts no longer than it.
    let placement: LaneLayoutPlacedView
    let page: SwimlanePageFrame
    /// The edges drawn, on the page, in their order.
    private(set) var placedEdges: [FlowchartLayoutEdge] = []
    /// The points each edge's route passes, its ends on their outlines, before the move onto the page: where it crosses a
    /// group's top. Kept only when a group sits inside a lane, whose title they move.
    private(set) var routePoints: [[CGPoint]] = []

    init(diagram: FlowchartDiagram, measured: FlowchartMeasurement, graph: SwimlaneGraph, placement: LaneLayoutPlacedView, page: SwimlanePageFrame,
         arena: DiagramScratchArena) {
        self.diagram = diagram
        self.measured = measured
        self.graph = graph
        self.placement = placement
        self.page = page
        placeEdges(arena: arena)
    }

    private func center(ofNode node: Int) -> CGPoint {
        let frame = placement.frames[graph.nodeBoxes[node]]
        return CGPoint(x: frame.midX, y: frame.midY)
    }

    /// Every edge in its order: a loop beside its node (an edge from a node to itself, which the lane layout gives no
    /// route), else an edge along its route, else none.
    private mutating func placeEdges(arena: DiagramScratchArena) {
        let reaches = sideReaches(arena: arena)
        let records = diagram.model.edges
        // For each node, how many of its loops drawn so far are visible, as the loops are counted node by node.
        let loopsDrawn = measured.selfLoopEdgeIndices.isEmpty ? .empty : arena.span(count: diagram.nodeCount, repeating: 0)
        placedEdges.reserveCapacity(records.count)
        let routeStart = arena.mark()
        for edgeIndex in 0..<records.count {
            let record = records[edgeIndex]
            if record.sourceIndex == record.targetIndex, !loopsDrawn.isEmpty {
                let node = Int(record.sourceIndex)
                placedEdges.append(loop(edgeIndex, of: node, loopIndex: loopsDrawn[node]))
                if record.stroke != .invisible { loopsDrawn[node] += 1 }
                continue
            }
            let route = placement.route(of: edgeIndex)
            guard route.count >= 2 else { continue }
            placedEdges.append(routedEdge(edgeIndex, record: record, route: route, reaches: reaches, arena: arena))
            arena.release(to: routeStart)
        }
    }

    /// The edge at `edgeIndex` along its route, its ends on its nodes' outlines, on the page.
    private mutating func routedEdge(_ edgeIndex: Int, record: FlowchartEdgeRecord, route: ScratchSpan<LaneRoutePoint>, reaches: ScratchSpan<CGFloat>,
                                     arena: DiagramScratchArena) -> FlowchartLayoutEdge {
        let offset = page.offset
        let source = Int(record.sourceIndex)
        let target = Int(record.targetIndex)
        let last = route.count - 1
        let points: ScratchSpan<CGPoint> = arena.uninitializedSpan(count: route.count)
        for index in 0..<route.count { points[index] = route[index].point }
        let startReach = reach(at: points[0], box: graph.nodeBoxes[source], in: reaches)
        let endReach = reach(at: points[last], box: graph.nodeBoxes[target], in: reaches)
        points[0] = onOutline(points[0], node: source)
        points[last] = onOutline(points[last], node: target)
        if graph.nesting.hasGroupInsideLane { routePoints.append(Array(points)) }
        let startTrim = DiagramEdgeMark.lineTrim(for: record.sourceArrowhead)
        let endTrim = DiagramEdgeMark.lineTrim(for: record.targetArrowhead)
        let drawn = DiagramTurningRouteDrawing.path(through: points, segmentsRunVertically: LaneRouteSegmentAxes(route: route), startTrim: startTrim,
                                                    endTrim: endTrim, startReach: startReach, endReach: endReach)
        let leaving = CGVector(dx: -drawn.startDirection.dx, dy: -drawn.startDirection.dy)
        return FlowchartLayoutEdge(stroke: record.stroke, path: Self.moved(drawn.path, by: offset),
                                   sourceMark: Self.mark(record.sourceArrowhead, tip: points[0], direction: leaving)?.translated(by: offset),
                                   targetMark: Self.mark(record.targetArrowhead, tip: points[last], direction: drawn.endDirection)?.translated(by: offset),
                                   text: Self.centered(measured.edgeTexts[edgeIndex], at: placement.labelCenters[edgeIndex])?.translated(by: offset),
                                   style: diagram.model.edgeStyle(at: edgeIndex))
    }

    /// `path` with each of its points moved by `offset`, as `DiagramPath.translated(by:)` moves them, where they lie.
    static func moved(_ path: consuming DiagramPath, by offset: CGVector) -> DiagramPath {
        var moved = path
        moved.start = moved.start.translated(by: offset)
        for index in moved.segments.indices {
            switch moved.segments[index] {
            case .line(let end): moved.segments[index] = .line(to: end.translated(by: offset))
            case .curve(let end, let firstControl, let secondControl):
                moved.segments[index] = .curve(to: end.translated(by: offset), control1: firstControl.translated(by: offset),
                                               control2: secondControl.translated(by: offset))
            }
        }
        return moved
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
        for (edgeIndex, record) in diagram.model.edges.enumerated() where record.stroke != .invisible {
            let route = placement.route(of: edgeIndex)
            guard route.count >= 2 else { continue }
            reach(route[0].point, box: graph.nodeBoxes[Int(record.sourceIndex)], arrowhead: record.sourceArrowhead)
            reach(route[route.count - 1].point, box: graph.nodeBoxes[Int(record.targetIndex)], arrowhead: record.targetArrowhead)
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
        guard graph.nesting.representedSubgraphs[node] < 0 else { return point }
        let frame = placement.frames[graph.nodeBoxes[node]]
        guard let side = Self.side(of: point, on: frame) else { return point }
        let shape = measured.layoutShape(of: node, in: diagram)
        return FlowchartEdgePorts.outlinePoint(center: CGPoint(x: frame.midX, y: frame.midY), shape: shape,
                                               size: measured.shapeSizes[node], side: side,
                                               offset: side.isHorizontal ? point.x - frame.midX : point.y - frame.midY)
    }

    /// The loop `edgeIndex` of `node`, the `loopIndex`th visible one, as Pele's `loopPath` draws it (`FlowchartSelfLoops`);
    /// a group's from the middle of its box, as Pele loops a group whose drawn node has no size. An invisible loop, which is
    /// not drawn, does not count among the loops drawn before the next one.
    private func loop(_ edgeIndex: Int, of node: Int, loopIndex: Int) -> FlowchartLayoutEdge {
        let offset = page.offset
        let isGroup = graph.nesting.representedSubgraphs[node] >= 0
        let edge = diagram.edgeDrawing(at: edgeIndex)
        let text = measured.edgeTexts[edgeIndex]
        let loop = FlowchartSelfLoops.loop(center: center(ofNode: node), shapeSize: isGroup ? .zero : measured.shapeSizes[node], loopIndex: loopIndex,
                                          flowRunsAcross: diagram.direction.runsAcross, endTrim: DiagramEdgeMark.lineTrim(for: edge.targetArrowhead),
                                          textSize: text?.size)
        return FlowchartLayoutEdge(stroke: edge.stroke, path: Self.moved(loop.path, by: offset),
                                   sourceMark: Self.mark(edge.sourceArrowhead, tip: loop.leave, direction: loop.intoNodeAtLeave)?.translated(by: offset),
                                   targetMark: Self.mark(edge.targetArrowhead, tip: loop.back, direction: loop.arriving)?.translated(by: offset),
                                   text: Self.centered(text, at: loop.textCenter)?.translated(by: offset), style: edge.style)
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

/// The axes of a lane route's segments, read from its points as `LaneLayoutPlacedView.placement` lists them: segment
/// `index` runs along a vertical flow when the point it arrives at has axis 0.
struct LaneRouteSegmentAxes: RandomAccessCollection {
    let route: ScratchSpan<LaneRoutePoint>

    var startIndex: Int { 0 }
    var endIndex: Int { route.count - 1 }

    subscript(index: Int) -> Bool {
        precondition(index >= 0 && index < route.count - 1, "Index out of range of a route's segments")
        return route[index + 1].axis == 0
    }
}
