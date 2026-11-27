/**
 * File: FlowchartBoxedEdges.swift
 * -------------------------------
 * Layer: Core
 * Description: The edges of a flowchart laid out in boxes on the page: each end on the outline of its node or box, the
 *              ends of one side spread along it clear of the edges crossing a box's border, each segment an S along its
 *              own flow, and the loops beside their nodes, written into the layout's records where they lie on the page.
 *
 * Authors: Bahey Shalash
 * Version: 0.2
 * Date: 26/11/2026
 */

import CoreGraphics

extension FlowchartPlacedBoxes {
    /// Every edge on the page in its written order, written into `recording` moved by `offset`: a loop beside its node (a
    /// group's from the middle of its box), an edge between a box and what it holds from one center to the other, any
    /// other along its route; an edge with an end placed nowhere is left out. The points each edge but the last kind
    /// passes go to `edgePoints`.
    func appendPageEdges(_ diagram: FlowchartDiagram, measured: FlowchartMeasurement, offset: CGVector, edgePoints: inout ScratchList<CGPoint>,
                         to recording: inout FlowchartLayoutRecording, arena: DiagramScratchArena) {
        let ports = endPoints(diagram, measured: measured, arena: arena)
        let loopsDrawn = measured.selfLoopEdgeIndices.isEmpty ? ScratchSpan<Int32>.empty : arena.span(count: diagram.nodeCount, repeating: 0)
        var layoutIndex = 0
        for edgeIndex in 0..<diagram.edgeCount {
            let (source, target) = diagram.edgeEnds(at: edgeIndex)
            if source == target {
                let isGroup = clustered.representedSubgraphs[source] != nil
                let stroke = FlowchartPagePieces.appendSelfLoop(edgeIndex, of: diagram, node: source, center: nodeCenters[source],
                                                                shapeSize: isGroup ? .zero : measured.shapeSize(of: source), loopIndex: Int(loopsDrawn[source]),
                                                                flowRunsAcross: clustered.loopSides[source] == .bottom, measured: measured, offset: offset,
                                                                to: &recording)
                if stroke != .invisible { loopsDrawn[source] += 1 }
                continue
            }
            defer { layoutIndex += 1 }
            appendEdge(edgeIndex, layoutIndex: layoutIndex, of: diagram, source: source, target: target, ports: ports, measured: measured, offset: offset,
                       edgePoints: &edgePoints, to: &recording, arena: arena)
        }
    }

    /// Laid-out edge `layoutIndex`, edge `edgeIndex` of the diagram, along its route, its points put on the page in a span
    /// of `arena`.
    private func appendEdge(_ edgeIndex: Int, layoutIndex: Int, of diagram: FlowchartDiagram, source: Int, target: Int, ports: FlowchartEdgePorts.Points,
                            measured: FlowchartMeasurement, offset: CGVector, edgePoints: inout ScratchList<CGPoint>,
                            to recording: inout FlowchartLayoutRecording, arena: DiagramScratchArena) {
        let route = route(of: layoutIndex)
        let segments = segmentsRunVertically(of: layoutIndex, arena: arena)
        if isStray[layoutIndex] {
            // Between a group and something inside it: from one center to the other, its mark under the node, as Pele draws it.
            let points: ScratchSpan<CGPoint> = arena.uninitializedSpan(count: route.count)
            for (index, point) in route.enumerated() { points[index] = point.point }
            let textCenter = labelCenter(of: layoutIndex) ?? points[0]
            return FlowchartPagePieces.appendEdge(edgeIndex, of: diagram, along: points, segmentsRunVertically: segments, textCenter: textCenter,
                                                  measured: measured, offset: offset, to: &recording)
        }
        guard let sourcePoint = route.first.flatMap({ end in outlineEnd(end.point, node: source, measured: measured, diagram: diagram) })
                  ?? ports.sourcePoint(of: edgeIndex),
              let targetPoint = route.last.flatMap({ end in outlineEnd(end.point, node: target, measured: measured, diagram: diagram) })
                  ?? ports.targetPoint(of: edgeIndex)
        else { return }
        let points: ScratchSpan<CGPoint> = arena.uninitializedSpan(count: max(route.count, 2))
        points[0] = sourcePoint
        var index = 1
        for point in route.dropFirst().dropLast() {
            points[index] = point.point
            index += 1
        }
        points[index] = targetPoint
        for point in points { edgePoints.append(point) }
        let textCenter = labelCenter(of: layoutIndex) ?? CGPoint(x: (sourcePoint.x + targetPoint.x) / 2, y: (sourcePoint.y + targetPoint.y) / 2)
        FlowchartPagePieces.appendEdge(edgeIndex, of: diagram, along: points, segmentsRunVertically: segments, textCenter: textCenter, measured: measured,
                                       offset: offset, to: &recording)
    }

    /// A route's end on the outline of its node's shape, or on the box of the group the node stands for.
    private func outlineEnd(_ end: CGPoint, node: Int, measured: FlowchartMeasurement, diagram: FlowchartDiagram) -> CGPoint? {
        if let subgraph = clustered.representedSubgraphs[node] {
            let frame = frames[subgraph]
            return FlowchartRouteEnds.outlinePoint(of: end, center: CGPoint(x: frame.midX, y: frame.midY), boxSize: frame.size, shape: .rectangle,
                                                   shapeSize: frame.size)
        }
        return FlowchartRouteEnds.outlinePoint(of: end, center: nodeCenters[node], boxSize: measured.layoutSize(of: node, loopSide: clustered.loopSides[node]),
                                               shape: measured.layoutShape(of: node, in: diagram), shapeSize: measured.shapeSize(of: node))
    }

    /// Where the ends of the edges through boxes meet their nodes and boxes where the layout left none: spread along each
    /// side, clear of where other edges cross a box's border.
    private func endPoints(_ diagram: FlowchartDiagram, measured: FlowchartMeasurement, arena: DiagramScratchArena) -> FlowchartEdgePorts.Points {
        let nodeCount = diagram.nodeCount
        var ends = arena.list(capacity: 2 * compound.edges.count, of: FlowchartEdgePorts.End.self)
        for (layoutIndex, edgeIndex) in clustered.layoutEdgeIndices.enumerated() where !isStray[layoutIndex] {
            let (source, target) = diagram.edgeEnds(at: edgeIndex)
            ends.append(routeEnd(of: layoutIndex, edgeIndex: edgeIndex, isSourceEnd: true, item: endItem(of: source, nodeCount: nodeCount)))
            ends.append(routeEnd(of: layoutIndex, edgeIndex: edgeIndex, isSourceEnd: false, item: endItem(of: target, nodeCount: nodeCount)))
        }
        let items = FlowchartEdgePorts.Items(count: nodeCount + frames.count, arena: arena)
        for node in 0..<nodeCount {
            items.centers[node] = nodeCenters[node]
            items.sizes[node] = measured.shapeSize(of: node)
            items.spreadsEnds[node] = measured.spreadsEdgeEnds(of: node)
        }
        for box in 0..<frames.count {
            items.centers[nodeCount + box] = CGPoint(x: frames[box].midX, y: frames[box].midY)
            items.sizes[nodeCount + box] = frames[box].size
            items.spreadsEnds[nodeCount + box] = measured.spreadsEdgeEnds
        }
        var innerPoints = arena.list(capacity: compound.routePoints.count, of: CGPoint.self)
        for layoutIndex in 0..<compound.edges.count {
            for point in route(of: layoutIndex).dropFirst().dropLast() { innerPoints.append(point.point) }
        }
        let kept = FlowchartBorderCrossings.crossings(innerPoints: innerPoints.elements, frames: frames, firstBoxNode: nodeCount, arena: arena)
        let points = FlowchartEdgePorts.Points(edgeCount: diagram.edgeCount, arena: arena)
        FlowchartEdgePorts.place(ends.elements, items: items, of: diagram, measured: measured, keptClear: kept, into: points, arena: arena)
        return points
    }

    /// A node's item among the ends: itself, or the box of the group it stands for, numbered after the nodes.
    private func endItem(of node: Int, nodeCount: Int) -> Int {
        clustered.representedSubgraphs[node].map { subgraph in nodeCount + subgraph } ?? node
    }

    /// An end of a route through boxes: the side of its node or box that its first or last segment leaves or arrives
    /// by, along that segment's flow, and where along the side the route goes next.
    private func routeEnd(of layoutIndex: Int, edgeIndex: Int, isSourceEnd: Bool, item: Int) -> FlowchartEdgePorts.End {
        let route = route(of: layoutIndex)
        let first = route.startIndex
        let last = route.endIndex - 1
        let end = isSourceEnd ? route[first].point : route[last].point
        let next = isSourceEnd ? route[first + 1].point : route[last - 1].point
        let runsVertically = isSourceEnd ? !route[first + 1].runsHorizontally : !route[last].runsHorizontally
        let side: DiagramSide = runsVertically ? (next.y > end.y ? .bottom : .top) : (next.x > end.x ? .right : .left)
        return FlowchartEdgePorts.End(edgeIndex: edgeIndex, isSourceEnd: isSourceEnd, node: item, side: side,
                                      neighborAcross: side.isHorizontal ? next.x : next.y)
    }
}
