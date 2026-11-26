/**
 * File: ClassDiagramPageAssembly.swift
 * ------------------------------------
 * Layer: Core
 * Description: Puts a placed class diagram on the page, in ranks or in its namespaces' boxes, its edges as flat
 *              records over one list of segments and its texts as measured texts.
 *
 * Authors: Félix Chevalier, Bahey Shalash
 * Version: 0.9
 * Date: 26/11/2026
 */

import CoreGraphics

/// Puts a placed class diagram on the page: nodes at their centers, relations from one box's side to the other's
/// through their passing points with their marks and cardinalities, loops beside their classes, then everything
/// moved inside the padding below the title.
struct ClassDiagramPageAssembly {
    /// A cardinality sits 5 points beside a left or right side's end and 7 points above or below its line, or
    /// 9 points beside a top or bottom side's line and 3 points above or below the side: Pele's.
    static let besideVerticalSide = CGVector(dx: 5, dy: 7)
    static let besideHorizontalSide = CGVector(dx: 9, dy: 3)
    /// An end with a cardinality runs straight for its text's room (its width and 10 points on a left or right side,
    /// its row and 6 points on a top or bottom side), at most this share of the way to the next point.
    static let straightEndExtra = CGSize(width: 10, height: 6)
    static let straightEndShare: CGFloat = 0.35
    /// A straight end shorter than this is not worth drawing.
    static let shortestStraightEnd: CGFloat = 4

    let measured: ClassDiagramMeasurement
    let markRowHeight: CGFloat
    let axes: FlowchartFlowAxes
    var nodeCenters: [CGPoint] = []
    /// By the index of the measurement's edge; nil until the edge is placed.
    var edges: [ClassDiagramPlacedEdge?]
    /// The segments of every edge placed.
    var segments: [DiagramPathSegment] = []
    /// An edge's points on the page, kept from one edge to the next.
    private var route: [CGPoint] = []
    /// The namespaces' boxes, for a diagram laid out in them.
    var namespaces: [FlowchartLayoutCluster] = []
    /// For each relation placed through boxes, the points it passes: where it crosses a namespace's top.
    private var edgePoints: [[CGPoint]] = []
    /// The namespace each node sits in and the one each namespace is in, for a diagram laid out in them.
    var nodeNamespaces: [Int?] = []
    var namespaceParents: [Int?] = []

    init(measured: ClassDiagramMeasurement, markRowHeight: CGFloat, axes: FlowchartFlowAxes) {
        self.measured = measured
        self.markRowHeight = markRowHeight
        self.axes = axes
        edges = Array(repeating: nil, count: measured.edges.count)
        segments.reserveCapacity(4 * measured.edges.count)
    }

    /// The nodes of a diagram laid out in ranks, at their flat nodes' centers.
    mutating func placeNodes(flowNodes: ScratchSpan<LayeredFlatNode>) {
        nodeCenters.reserveCapacity(flowNodes.count)
        for node in flowNodes { nodeCenters.append(axes.pagePoint(CGPoint(x: node.x, y: node.y))) }
    }

    /// The edges between two different nodes, along their routes. `layeredEdgeIndices[i]` is the edge of the flat
    /// layout's `i`-th edge, whose route runs from its source's center to its target's through its path's inner points.
    mutating func placeEdges(layeredEdgeIndices: ScratchSpan<Int>, nodes: ScratchSpan<LayeredFlatNode>, edges laidOut: ScratchSpan<LayeredSpanEdge>,
                             points: ScratchSpan<CGPoint>) {
        func route(of layeredIndex: Int) -> RankedRoute {
            let edge = laidOut[layeredIndex]
            let path = edge.pointStart >= 0 ? points.part(edge.pointStart..<(edge.pointStart + edge.pointCount)) : .empty
            return RankedRoute(source: CGPoint(x: nodes[edge.tail].x, y: nodes[edge.tail].y), target: CGPoint(x: nodes[edge.head].x, y: nodes[edge.head].y),
                               path: path)
        }
        var ends: [ClassDiagramEdgePorts.End] = []
        ends.reserveCapacity(2 * layeredEdgeIndices.count)
        for layeredIndex in 0..<layeredEdgeIndices.count { appendRouteEnds(of: layeredEdgeIndices[layeredIndex], route: route(of: layeredIndex), to: &ends) }
        let ports = ClassDiagramEdgePorts(ends: ends, edgeCount: measured.edges.count, nodeCenters: nodeCenters, sizes: measured.sizes,
                                          markRowHeight: markRowHeight)
        for layeredIndex in 0..<layeredEdgeIndices.count {
            let edgeIndex = layeredEdgeIndices[layeredIndex]
            // The two ends of a laid-out edge are its source's then its target's.
            guard let sourcePort = ports.sourcePoints[edgeIndex], let targetPort = ports.targetPoints[edgeIndex] else { continue }
            let route = route(of: layeredIndex)
            let laidOutEdge = laidOut[layeredIndex]
            let textCenter = laidOutEdge.labelWidth > 0 ? axes.pagePoint(laidOutEdge.labelCenter)
                : CGPoint(x: (sourcePort.x + targetPort.x) / 2, y: (sourcePort.y + targetPort.y) / 2)
            self.route.removeAll(keepingCapacity: true)
            self.route.append(sourcePort)
            for index in 1..<(route.count - 1) { self.route.append(axes.pagePoint(route[index])) }
            self.route.append(targetPort)
            edges[edgeIndex] = edgeAlongRoute(edgeIndex: edgeIndex, ends: (ends[2 * layeredIndex], ends[2 * layeredIndex + 1]), textCenter: textCenter)
        }
    }

    /// A laid-out edge's route in flow space, from its source's center to its target's through its path's inner points.
    private struct RankedRoute {
        let source: CGPoint
        let target: CGPoint
        let path: ScratchSpan<CGPoint>

        var count: Int { path.count > 2 ? path.count : 2 }

        subscript(index: Int) -> CGPoint {
            index == 0 ? source : index == count - 1 ? target : path[index]
        }
    }

    /// The two ends of a route on the sides of their nodes facing it, with what orders and spaces them.
    private func appendRouteEnds(of edgeIndex: Int, route: RankedRoute, to ends: inout [ClassDiagramEdgePorts.End]) {
        let edge = measured.edges[edgeIndex]
        let last = route.count - 1
        // In a flow that runs down, an end's text goes right of its line when the line bends right or runs straight.
        func isTextAfter(bend: CGFloat) -> Bool { axes.flowIsVertical ? bend >= 0 : bend > 0 }
        ends.append(ClassDiagramEdgePorts.End(edgeIndex: edgeIndex, isSourceEnd: true, node: edge.source,
                                              side: route[1].y > route[0].y ? axes.downstreamSide : axes.upstreamSide, neighborAlongSide: route[1].x,
                                              cardinalityWidth: edge.sourceCardinality?.width ?? 0, isTextAfter: isTextAfter(bend: route[1].x - route[0].x)))
        ends.append(ClassDiagramEdgePorts.End(edgeIndex: edgeIndex, isSourceEnd: false, node: edge.target,
                                              side: route[last - 1].y < route[last].y ? axes.upstreamSide : axes.downstreamSide,
                                              neighborAlongSide: route[last - 1].x, cardinalityWidth: edge.targetCardinality?.width ?? 0,
                                              isTextAfter: isTextAfter(bend: route[last - 1].x - route[last].x)))
    }

    /// The edge through `ports`; `segmentsRunVertically` gives each segment's flow for a route through boxes, else every
    /// segment follows the diagram's.
    /// The route is taken, so that a straight end is put in its own list rather than in a copy.
    private mutating func edgeAlongRoute(edgeIndex: Int, ends: (source: ClassDiagramEdgePorts.End, target: ClassDiagramEdgePorts.End),
                                         textCenter: CGPoint, segmentsRunVertically: [Bool]? = nil) -> ClassDiagramPlacedEdge {
        let edge = measured.edges[edgeIndex]
        var points = route
        route = []
        defer { route = points }
        var segmentAxes = segmentsRunVertically
        if let straight = straightEnd(from: points[0], toward: points[1], end: ends.source) {
            points.insert(straight, at: 1)
            if let first = segmentAxes?.first { segmentAxes?.insert(first, at: 0) }
        }
        if let straight = straightEnd(from: points[points.count - 1], toward: points[points.count - 2], end: ends.target) {
            points.insert(straight, at: points.count - 1)
            if let last = segmentAxes?.last { segmentAxes?.append(last) }
        }
        let startTrim = ClassDiagramMarkGeometry.lineTrim(for: edge.sourceEnd)
        let endTrim = ClassDiagramMarkGeometry.lineTrim(for: edge.targetEnd)
        let drawn = segmentAxes.map { segmentAxes in
            DiagramRouteSegments.append(through: points, segmentsRunVertically: segmentAxes, startTrim: startTrim, endTrim: endTrim, into: &segments)
        } ?? DiagramRouteSegments.append(through: points, flowIsVertical: axes.flowIsVertical, startTrim: startTrim, endTrim: endTrim, into: &segments)
        let leaving = CGVector(dx: -drawn.startDirection.dx, dy: -drawn.startDirection.dy)
        return ClassDiagramPlacedEdge(line: edge.line, path: drawn.run,
                                      sourceMark: mark(edge.sourceEnd, tip: points[0], direction: leaving),
                                      targetMark: mark(edge.targetEnd, tip: points[points.count - 1], direction: drawn.endDirection),
                                      text: centeredIfPresent(edge.text, at: textCenter),
                                      sourceCardinality: cardinality(edge.sourceCardinality, at: points[0], side: ends.source.side,
                                                                     isTextAfter: ends.source.isTextAfter),
                                      targetCardinality: cardinality(edge.targetCardinality, at: points[points.count - 1], side: ends.target.side,
                                                                     isTextAfter: ends.target.isTextAfter))
    }

    /// The point an end with a cardinality runs straight out to from its side before it bends, or nil.
    private func straightEnd(from port: CGPoint, toward neighbor: CGPoint, end: ClassDiagramEdgePorts.End) -> CGPoint? {
        guard end.cardinalityWidth > 0 else { return nil }
        let reach = end.side.isHorizontal ? abs(neighbor.y - port.y) : abs(neighbor.x - port.x)
        let room = end.side.isHorizontal ? markRowHeight + Self.straightEndExtra.height : end.cardinalityWidth + Self.straightEndExtra.width
        let length = min(room, reach * Self.straightEndShare)
        guard length >= Self.shortestStraightEnd else { return nil }
        switch end.side {
        case .top: return CGPoint(x: port.x, y: port.y - length)
        case .bottom: return CGPoint(x: port.x, y: port.y + length)
        case .left: return CGPoint(x: port.x - length, y: port.y)
        case .right: return CGPoint(x: port.x + length, y: port.y)
        }
    }

    /// The nodes of a diagram laid out in namespaces' boxes, at their centers on the page.
    mutating func placeNodes(pageCenters: [CGPoint]) {
        nodeCenters = pageCenters
    }

    /// The relations of a diagram laid out in namespaces' boxes, along their routes on the page: each end on the side its
    /// route leaves or arrives by, spread along it with the others there, running straight to its namespace's border
    /// where that is close (`ClassDiagramBorderRuns`); each segment an S along its own flow.
    mutating func placeEdges(clustered: ClassDiagramClusterGraph, compound: LayeredCompoundLayout, clusterFrames: [CGRect]) {
        var routes: [Route] = []
        routes.reserveCapacity(clustered.layoutEdgeIndices.count)
        var ends: [ClassDiagramEdgePorts.End] = []
        ends.reserveCapacity(2 * clustered.layoutEdgeIndices.count)
        for (layoutIndex, edgeIndex) in clustered.layoutEdgeIndices.enumerated() {
            let route = Self.route(of: layoutIndex, in: compound)
            routes.append(route)
            ends += pageRouteEnds(of: edgeIndex, route: route)
        }
        let ports = ClassDiagramEdgePorts(ends: ends, edgeCount: measured.edges.count, nodeCenters: nodeCenters, sizes: measured.sizes,
                                          markRowHeight: markRowHeight)
        let borderRuns = ClassDiagramBorderRuns(nodeNamespaces: clustered.nodeNamespaces, namespaceParents: clustered.namespaceParents,
                                                clusterFrames: clusterFrames, ends: ends)
        for (layoutIndex, edgeIndex) in clustered.layoutEdgeIndices.enumerated() {
            let route = routes[layoutIndex]
            guard let sourcePort = ports.sourcePoints[edgeIndex], let targetPort = ports.targetPoints[edgeIndex] else { continue }
            let points = borderRuns.straightened([sourcePort] + route.points.dropFirst().dropLast() + [targetPort],
                                                 source: ends[2 * layoutIndex], target: ends[2 * layoutIndex + 1])
            edgePoints.append(points)
            let textCenter = compound.labelCenter(of: layoutIndex) ?? CGPoint(x: (sourcePort.x + targetPort.x) / 2, y: (sourcePort.y + targetPort.y) / 2)
            self.route = points
            edges[edgeIndex] = edgeAlongRoute(edgeIndex: edgeIndex, ends: (ends[2 * layoutIndex], ends[2 * layoutIndex + 1]), textCenter: textCenter,
                                              segmentsRunVertically: route.segmentsRunVertically)
        }
    }

    /// Laid-out edge `edge`'s route: its points, and for each segment whether the flow it follows runs vertically.
    private static func route(of edge: Int, in compound: LayeredCompoundLayout) -> Route {
        let range = compound.routeRange(of: edge)
        var points: [CGPoint] = []
        var segmentsRunVertically: [Bool] = []
        points.reserveCapacity(range.count)
        segmentsRunVertically.reserveCapacity(max(range.count - 1, 0))
        for index in range {
            let point = compound.routePoints[index]
            points.append(point.point)
            if index > range.lowerBound { segmentsRunVertically.append(!point.runsHorizontally) }
        }
        return Route(points: points, segmentsRunVertically: segmentsRunVertically)
    }

    /// A route through namespaces' boxes on the page, from the side of its source to the side of its target, and for
    /// each segment whether the flow it follows runs vertically.
    private struct Route {
        let points: [CGPoint]
        let segmentsRunVertically: [Bool]
    }

    /// The two ends of a route on the page, each on the side its first or last segment leaves or arrives by.
    private func pageRouteEnds(of edgeIndex: Int, route: Route) -> [ClassDiagramEdgePorts.End] {
        let edge = measured.edges[edgeIndex]
        func end(isSourceEnd: Bool) -> ClassDiagramEdgePorts.End {
            let points = route.points
            let point = isSourceEnd ? points[0] : points[points.count - 1]
            let next = isSourceEnd ? points[1] : points[points.count - 2]
            let runsVertically = isSourceEnd ? route.segmentsRunVertically[0] : route.segmentsRunVertically[route.segmentsRunVertically.count - 1]
            let side: DiagramSide = runsVertically ? (next.y > point.y ? .bottom : .top) : (next.x > point.x ? .right : .left)
            let bend = runsVertically ? next.x - point.x : next.y - point.y
            let cardinality = isSourceEnd ? edge.sourceCardinality : edge.targetCardinality
            return ClassDiagramEdgePorts.End(edgeIndex: edgeIndex, isSourceEnd: isSourceEnd, node: isSourceEnd ? edge.source : edge.target, side: side,
                                             neighborAlongSide: runsVertically ? next.x : next.y, cardinalityWidth: cardinality?.width ?? 0,
                                             isTextAfter: axes.flowIsVertical ? bend >= 0 : bend > 0)
        }
        return [end(isSourceEnd: true), end(isSourceEnd: false)]
    }

    /// The namespaces' boxes, each title along its box's top, clear of the relations where it can be.
    mutating func placeNamespaces(clustered: ClassDiagramClusterGraph, clusterFrames: [CGRect]) {
        nodeNamespaces = clustered.nodeNamespaces
        namespaceParents = clustered.namespaceParents
        let crossings = FlowchartRoutePointIndex(edgePoints)
        namespaces = clusterFrames.enumerated().map { index, frame in
            let title = clustered.titles[index].map { title in FlowchartClusterTitles.placed(title, in: frame, crossings: crossings) }
            return FlowchartLayoutCluster(frame: frame, title: title?.title, depth: clustered.depths[index], isTitleCrossed: title?.isCrossed ?? false)
        }
    }

    /// The loops of every class that has relations to itself.
    mutating func placeSelfLoops(_ selfLoops: [[Int]]) {
        for (node, loopEdgeIndices) in selfLoops.enumerated() {
            for (loopIndex, edgeIndex) in loopEdgeIndices.enumerated() {
                let edge = measured.edges[edgeIndex]
                let loop = ClassDiagramSelfLoops.loop(center: nodeCenters[node], boxSize: measured.sizes[node], loopIndex: loopIndex,
                                                      startTrim: ClassDiagramMarkGeometry.lineTrim(for: edge.sourceEnd),
                                                      endTrim: ClassDiagramMarkGeometry.lineTrim(for: edge.targetEnd),
                                                      textWidth: edge.text?.width ?? 0)
                let intoBox = CGVector(dx: -1, dy: 0)
                segments.append(loop.segment)
                let path = DiagramSegmentRun(start: loop.start, firstSegment: Int32(segments.count - 1), segmentCount: 1)
                edges[edgeIndex] = ClassDiagramPlacedEdge(
                    line: edge.line, path: path, sourceMark: mark(edge.sourceEnd, tip: loop.leave, direction: intoBox),
                    targetMark: mark(edge.targetEnd, tip: loop.back, direction: intoBox), text: centeredIfPresent(edge.text, at: loop.textCenter),
                    sourceCardinality: cardinality(edge.sourceCardinality, at: loop.leave, side: .right, isTextAfter: false),
                    targetCardinality: cardinality(edge.targetCardinality, at: loop.back, side: .right, isTextAfter: true))
            }
        }
    }

    private func mark(_ end: ClassDiagramRelationEnd, tip: CGPoint, direction: CGVector) -> ClassDiagramRelationMark? {
        end == .none ? nil : ClassDiagramRelationMark(end: end, tip: tip, direction: direction)
    }

    /// A cardinality beside the end at `point`, on the side of its line `isTextAfter` names.
    private func cardinality(_ text: DiagramMeasuredText?, at point: CGPoint, side: DiagramSide, isTextAfter: Bool) -> DiagramMeasuredText? {
        guard let text else { return nil }
        let width = text.width
        let after: CGFloat = isTextAfter ? 1 : -1
        let center: CGPoint
        switch side {
        case .left, .right:
            let outward: CGFloat = side == .left ? -1 : 1
            center = CGPoint(x: point.x + outward * (Self.besideVerticalSide.dx + width / 2),
                             y: point.y + after * (Self.besideVerticalSide.dy + markRowHeight / 2))
        case .top, .bottom:
            let outward: CGFloat = side == .top ? -1 : 1
            center = CGPoint(x: point.x + after * (Self.besideHorizontalSide.dx + width / 2),
                             y: point.y + outward * (Self.besideHorizontalSide.dy + markRowHeight / 2))
        }
        return text.centered(at: center)
    }

    /// `text` centered at `center`, or nil when there is no text.
    private func centeredIfPresent(_ text: DiagramMeasuredText?, at center: CGPoint) -> DiagramMeasuredText? {
        text.map { text in text.centered(at: center) }
    }

}
