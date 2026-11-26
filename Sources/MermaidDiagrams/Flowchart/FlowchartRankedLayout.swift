/**
 * File: FlowchartRankedLayout.swift
 * ---------------------------------
 * Layer: Core
 * Description: A flowchart without groups laid out in ranks and put on the page in the scratch arena: its graph written
 *              straight into the flat layout's spans and its nodes and edges written once, as flat records, at their
 *              place on the page.
 *
 * Authors: Bahey Shalash
 * Version: 0.3
 * Date: 26/11/2026
 */

import CoreGraphics

/// A flowchart without subgraphs, as Pele lays out a diagram with no groups: its nodes and the edges between two
/// different nodes as one flat layered graph (`LayeredFlatLayout`), then each node at its center on the page, each edge
/// from the outline of one shape to the other's through its passing points, the loops beside their nodes, and
/// everything moved inside the padding below the title. The working lists are spans of the calling thread's arena;
/// only the layout's records are allocated, each of their lists once.
enum FlowchartRankedLayout {
    /// The layout, or nil when the flat graph would need more than `maximumPointCount` nodes and passing points.
    static func layout(_ diagram: FlowchartDiagram, measured: FlowchartMeasurement, font: DiagramFont, spacing: LayeredSpacing,
                       maximumPointCount: Int, title: DiagramTextBlock?, arena: DiagramScratchArena) -> FlowchartLayout? {
        let flowAxes = FlowchartFlowAxes(direction: diagram.direction, alongExtent: 0)
        let graph = RankedGraph(diagram, measured: measured, axes: flowAxes, arena: arena)
        #if DEBUG
        LayeredLayoutRecording.recordPlacement(nodes: graph.nodes, edges: graph.edges, spacing: spacing, maximumPointCount: maximumPointCount)
        #endif
        var points = arena.list(capacity: 4 * graph.edges.count, of: CGPoint.self)
        guard let size = LayeredFlatLayout.layout(nodes: graph.nodes, edges: graph.edges, points: &points, options: LayeredFlatOptions(spacing),
                                                  maximumVertexCount: maximumPointCount, arena: arena) else {
            return nil
        }
        let extent = CGSize(width: size.width, height: size.height)
        let axes = FlowchartFlowAxes(direction: diagram.direction, alongExtent: extent.height)
        let placed = PlacedGraph(nodes: graph.nodes, edges: graph.edges, points: points.elements, layoutSizes: graph.layoutSizes, axes: axes, arena: arena)
        let frame = FlowchartPageFrame(extent: flowAxes.flowIsVertical ? extent : CGSize(width: extent.height, height: extent.width), title: title)
        var recording = FlowchartLayoutRecording(nodeCapacity: diagram.nodeCount, edgeCapacity: diagram.edgeCount, textStorages: measured.textStorages,
                                                  arena: arena)
        appendPageEdges(diagram, placed: placed, layeredEdgeIndices: graph.layeredEdgeIndices, measured: measured, frame: frame, to: &recording,
                        arena: arena)
        for node in 0..<diagram.nodeCount {
            FlowchartPagePieces.appendNode(node, of: diagram, center: placed.nodeCenters[node], measured: measured, offset: frame.offset, to: &recording)
        }
        return FlowchartLayout(size: frame.size, font: font, records: FlowchartLayoutRecords(recorded: recording), title: frame.title, clusters: [])
    }

    /// The flowchart's nodes and the edges between two different nodes as the flat layout's graph, in flow space.
    private struct RankedGraph {
        /// Every edge but those from a node to itself, which loop beside it, by its index in the diagram.
        let layeredEdgeIndices: ScratchSpan<Int>
        /// Each node's size in its rank on the page, its loops' room included.
        let layoutSizes: ScratchSpan<CGSize>
        let nodes: ScratchSpan<LayeredFlatNode>
        let edges: ScratchSpan<LayeredSpanEdge>

        init(_ diagram: FlowchartDiagram, measured: FlowchartMeasurement, axes: FlowchartFlowAxes, arena: DiagramScratchArena) {
            var layeredEdgeIndices = arena.list(capacity: diagram.edgeCount, of: Int.self)
            for edgeIndex in 0..<diagram.edgeCount {
                let ends = diagram.edgeEnds(at: edgeIndex)
                if ends.source != ends.target { layeredEdgeIndices.append(edgeIndex) }
            }
            self.layeredEdgeIndices = layeredEdgeIndices.elements
            let spanSide: DiagramSide = diagram.direction.layeredDirection.runsVertically ? .top : .left
            layoutSizes = arena.uninitializedSpan(count: diagram.nodeCount)
            nodes = arena.uninitializedSpan(count: diagram.nodeCount)
            for node in 0..<diagram.nodeCount {
                layoutSizes[node] = measured.layoutSize(of: node, loopSide: axes.loopSide)
                let size = axes.flowSize(of: layoutSizes[node])
                var flatNode = LayeredFlatNode(width: Double(size.across), height: Double(size.along))
                flatNode.sideSpan = Double(measured.sideSpan(of: node, shape: diagram.nodeShape(at: node), side: spanSide))
                nodes[node] = flatNode
            }
            edges = arena.uninitializedSpan(count: layeredEdgeIndices.count)
            for layeredIndex in 0..<layeredEdgeIndices.count {
                let edgeIndex = layeredEdgeIndices[layeredIndex]
                let ends = diagram.edgeEnds(at: edgeIndex)
                let labelSize = labelFlowSize(of: edgeIndex, measured: measured, axes: axes)
                edges[layeredIndex] = LayeredSpanEdge(tail: ends.source, head: ends.target, minimumLength: diagram.edgeMinimumRankSpan(at: edgeIndex),
                                                      labelWidth: Double(labelSize?.across ?? 0), labelHeight: Double(labelSize?.along ?? 0),
                                                      tailOffset: 0, headOffset: 0)
            }
        }
    }

    /// Every edge on the page in its written order, written into `recording`: a loop beside its node, any other along its
    /// route; an edge with an end placed nowhere is left out.
    private static func appendPageEdges(_ diagram: FlowchartDiagram, placed: PlacedGraph, layeredEdgeIndices: ScratchSpan<Int>,
                                        measured: FlowchartMeasurement, frame: FlowchartPageFrame, to recording: inout FlowchartLayoutRecording,
                                        arena: DiagramScratchArena) {
        let ends = placed.endPoints(diagram, layeredEdgeIndices: layeredEdgeIndices, measured: measured, arena: arena)
        let loopsDrawn = selfLoopCounts(nodeCount: diagram.nodeCount, measured: measured, arena: arena)
        var layeredIndex = 0
        for edgeIndex in 0..<diagram.edgeCount {
            let (source, target) = diagram.edgeEnds(at: edgeIndex)
            if source == target {
                let stroke = FlowchartPagePieces.appendSelfLoop(edgeIndex, of: diagram, node: source, center: placed.nodeCenters[source],
                                                                shapeSize: measured.shapeSize(of: source), loopIndex: Int(loopsDrawn[source]),
                                                                flowRunsAcross: placed.axes.loopSide == .bottom, measured: measured, offset: frame.offset,
                                                                to: &recording)
                if stroke != .invisible { loopsDrawn[source] += 1 }
                continue
            }
            defer { layeredIndex += 1 }
            placed.appendEdge(edgeIndex, layeredIndex: layeredIndex, of: diagram, source: source, target: target, ends: ends, measured: measured,
                              offset: frame.offset, to: &recording, arena: arena)
        }
    }

    /// The flow-space size of an edge's text's place, or nil for an edge without text.
    private static func labelFlowSize(of edgeIndex: Int, measured: FlowchartMeasurement, axes: FlowchartFlowAxes) -> LayeredSize? {
        measured.edgeText(of: edgeIndex).map { text in
            let room = FlowchartLayoutEngine.edgeTextRoom
            return axes.flowSize(of: CGSize(width: text.size.width + room.width, height: text.size.height + room.height))
        }
    }

    /// For each node, how many of its loops have been drawn so far (an invisible loop is not), or an empty span when no
    /// edge loops.
    private static func selfLoopCounts(nodeCount: Int, measured: FlowchartMeasurement, arena: DiagramScratchArena) -> ScratchSpan<Int32> {
        measured.selfLoopEdgeIndices.isEmpty ? .empty : arena.span(count: nodeCount, repeating: 0)
    }

    /// The laid-out flat graph read on the page.
    private struct PlacedGraph {
        let nodes: ScratchSpan<LayeredFlatNode>
        let edges: ScratchSpan<LayeredSpanEdge>
        let points: ScratchSpan<CGPoint>
        let layoutSizes: ScratchSpan<CGSize>
        let axes: FlowchartFlowAxes
        /// Each node's center on the page.
        let nodeCenters: ScratchSpan<CGPoint>

        init(nodes: ScratchSpan<LayeredFlatNode>, edges: ScratchSpan<LayeredSpanEdge>, points: ScratchSpan<CGPoint>, layoutSizes: ScratchSpan<CGSize>,
             axes: FlowchartFlowAxes, arena: DiagramScratchArena) {
            self.nodes = nodes
            self.edges = edges
            self.points = points
            self.layoutSizes = layoutSizes
            self.axes = axes
            nodeCenters = arena.uninitializedSpan(count: nodes.count)
            for node in 0..<nodes.count { nodeCenters[node] = axes.pagePoint(flowCenter(of: node)) }
        }

        @inline(__always)
        func flowCenter(of node: Int) -> CGPoint { CGPoint(x: nodes[node].x, y: nodes[node].y) }

        /// The points of the route Pele's layout drew for layered edge `layeredIndex`, from the side of its source to the
        /// side of its target; empty for an edge it gave none.
        @inline(__always)
        func path(of layeredIndex: Int) -> ScratchSpan<CGPoint> {
            let edge = edges[layeredIndex]
            return edge.pointStart >= 0 ? points.part(edge.pointStart..<(edge.pointStart + edge.pointCount)) : .empty
        }

        /// The second point of the route from the source's center to the target's through the path's inner points, and
        /// the one before its last, in flow space.
        @inline(__always)
        func routeNeighbors(of layeredIndex: Int) -> (afterSource: CGPoint, beforeTarget: CGPoint) {
            let edge = edges[layeredIndex]
            let path = path(of: layeredIndex)
            guard path.count > 2 else { return (flowCenter(of: edge.head), flowCenter(of: edge.tail)) }
            return (path[1], path[path.count - 2])
        }

        /// Where each edge meets its nodes where the layout left no end of its own: the ends on one side spread along it.
        func endPoints(_ diagram: FlowchartDiagram, layeredEdgeIndices: ScratchSpan<Int>, measured: FlowchartMeasurement,
                       arena: DiagramScratchArena) -> FlowchartEdgePorts.Points {
            let ends: ScratchSpan<FlowchartEdgePorts.End> = arena.uninitializedSpan(count: 2 * layeredEdgeIndices.count)
            for layeredIndex in 0..<layeredEdgeIndices.count {
                let edgeIndex = layeredEdgeIndices[layeredIndex]
                let edge = edges[layeredIndex]
                let source = flowCenter(of: edge.tail)
                let target = flowCenter(of: edge.head)
                let (afterSource, beforeTarget) = routeNeighbors(of: layeredIndex)
                let leavesDownstream = afterSource.y > source.y
                let arrivesFromUpstream = beforeTarget.y < target.y
                ends[2 * layeredIndex] = FlowchartEdgePorts.End(edgeIndex: edgeIndex, isSourceEnd: true, node: edge.tail,
                                                                side: leavesDownstream ? axes.downstreamSide : axes.upstreamSide,
                                                                neighborAcross: afterSource.x)
                ends[2 * layeredIndex + 1] = FlowchartEdgePorts.End(edgeIndex: edgeIndex, isSourceEnd: false, node: edge.head,
                                                                    side: arrivesFromUpstream ? axes.upstreamSide : axes.downstreamSide,
                                                                    neighborAcross: beforeTarget.x)
            }
            let nodeCount = nodes.count
            let items = FlowchartEdgePorts.Items(count: nodeCount, arena: arena)
            for node in 0..<nodeCount {
                items.centers[node] = nodeCenters[node]
                items.sizes[node] = measured.shapeSize(of: node)
                items.spreadsEnds[node] = measured.spreadsEdgeEnds(of: node)
            }
            let points = FlowchartEdgePorts.Points(edgeCount: diagram.edgeCount, arena: arena)
            FlowchartEdgePorts.place(ends, items: items, of: diagram, measured: measured, keptClear: .empty, into: points, arena: arena)
            return points
        }

        /// Edge `edgeIndex`, the `layeredIndex`-th of the graph, along its route, written into `recording` moved by
        /// `offset`: each end where Pele's layout settled it, moved onto its shape's outline, or the spread end where it left
        /// none; left out when an end has neither. The route is put on the page in a span of `arena`.
        func appendEdge(_ edgeIndex: Int, layeredIndex: Int, of diagram: FlowchartDiagram, source: Int, target: Int, ends: FlowchartEdgePorts.Points,
                        measured: FlowchartMeasurement, offset: CGVector, to recording: inout FlowchartLayoutRecording, arena: DiagramScratchArena) {
            let path = path(of: layeredIndex)
            // Only the path's two ends are read, each put on the page alone.
            guard let sourcePoint = path.first.map(axes.pagePoint).flatMap({ end in outlineEnd(end, node: source, of: diagram, measured: measured) })
                      ?? ends.sourcePoint(of: edgeIndex),
                  let targetPoint = path.last.map(axes.pagePoint).flatMap({ end in outlineEnd(end, node: target, of: diagram, measured: measured) })
                      ?? ends.targetPoint(of: edgeIndex)
            else { return }
            let routePoints: ScratchSpan<CGPoint> = arena.uninitializedSpan(count: max(path.count, 2))
            routePoints[0] = sourcePoint
            if path.count > 2 { for index in 1..<(path.count - 1) { routePoints[index] = axes.pagePoint(path[index]) } }
            routePoints[routePoints.count - 1] = targetPoint
            let laidOut = edges[layeredIndex]
            let textCenter = laidOut.labelWidth > 0 ? axes.pagePoint(laidOut.labelCenter)
                : CGPoint(x: (sourcePoint.x + targetPoint.x) / 2, y: (sourcePoint.y + targetPoint.y) / 2)
            FlowchartPagePieces.appendEdge(edgeIndex, of: diagram, along: routePoints,
                                           segmentsRunVertically: repeatElement(axes.flowIsVertical, count: routePoints.count - 1), textCenter: textCenter,
                                           measured: measured, offset: offset, to: &recording)
        }

        /// A route's end on the outline of `node`'s shape, from the side of its layout box the layout left it on.
        private func outlineEnd(_ end: CGPoint, node: Int, of diagram: FlowchartDiagram, measured: FlowchartMeasurement) -> CGPoint? {
            FlowchartRouteEnds.outlinePoint(of: end, center: nodeCenters[node], boxSize: layoutSizes[node], shape: measured.layoutShape(of: node, in: diagram),
                                            shapeSize: measured.shapeSize(of: node))
        }
    }
}
