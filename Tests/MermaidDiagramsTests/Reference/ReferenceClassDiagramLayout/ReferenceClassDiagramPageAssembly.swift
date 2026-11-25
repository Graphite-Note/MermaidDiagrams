/**
 * File: ReferenceClassDiagramPageAssembly.swift
 * ---------------------------------------------
 * Layer: Tests
 * Description: The 0.7.0 ClassDiagramPageAssembly kept as the reference the 0.8.0 layout is checked against:
 *              puts a placed class diagram on the page, in ranks or in its namespaces' boxes.
 *
 * Authors: Félix Chevalier, Bahey Shalash
 * Version: 0.1
 * Date: 24/11/2026
 */

import CoreGraphics
@testable import MermaidDiagrams

/// Puts a placed class diagram on the page: nodes at their centers, relations from one box's side to the other's
/// through their passing points with their marks and cardinalities, loops beside their classes, then everything
/// moved inside the padding below the title.
struct ReferenceClassDiagramPageAssembly {
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

    let measured: ReferenceClassDiagramMeasurement
    let markRowHeight: CGFloat
    let axes: FlowchartFlowAxes
    private(set) var nodeCenters: [CGPoint] = []
    /// By the index of the measurement's edge; nil until the edge is placed.
    private var edges: [ClassDiagramLayoutEdge?]
    /// The namespaces' boxes, for a diagram laid out in them.
    private var namespaces: [FlowchartLayoutCluster] = []
    /// For each relation placed through boxes, the points it passes: where it crosses a namespace's top.
    private var edgePoints: [[CGPoint]] = []
    /// The namespace each node sits in and the one each namespace is in, for a diagram laid out in them.
    private var nodeNamespaces: [Int?] = []
    private var namespaceParents: [Int?] = []

    init(measured: ReferenceClassDiagramMeasurement, markRowHeight: CGFloat, axes: FlowchartFlowAxes) {
        self.measured = measured
        self.markRowHeight = markRowHeight
        self.axes = axes
        edges = Array(repeating: nil, count: measured.edges.count)
    }

    mutating func placeNodes(flowCenters: [CGPoint]) {
        nodeCenters = flowCenters.map(axes.pagePoint)
    }

    /// The edges between two different nodes, along their routes. `layeredEdgeIndices[i]` is the edge of the
    /// placement's `i`-th route.
    mutating func placeEdges(layeredEdgeIndices: [Int], placement: LayeredPlacement) {
        let ends = layeredEdgeIndices.enumerated().flatMap { layeredIndex, edgeIndex in
            routeEnds(of: edgeIndex, route: placement.edgeRoutes[layeredIndex])
        }
        let ports = ReferenceClassDiagramEdgePorts(ends: ends, edgeCount: measured.edges.count, nodeCenters: nodeCenters, sizes: measured.sizes,
                                          markRowHeight: markRowHeight)
        var endsByEdge = [(source: ReferenceClassDiagramEdgePorts.End?, target: ReferenceClassDiagramEdgePorts.End?)](repeating: (nil, nil), count: measured.edges.count)
        for end in ends {
            if end.isSourceEnd { endsByEdge[end.edgeIndex].source = end } else { endsByEdge[end.edgeIndex].target = end }
        }
        for (layeredIndex, edgeIndex) in layeredEdgeIndices.enumerated() {
            guard let sourcePort = ports.sourcePoints[edgeIndex], let targetPort = ports.targetPoints[edgeIndex],
                  let sourceEnd = endsByEdge[edgeIndex].source, let targetEnd = endsByEdge[edgeIndex].target else { continue }
            let route = placement.edgeRoutes[layeredIndex]
            let textCenter = placement.edgeLabelCenters[layeredIndex].map(axes.pagePoint)
                ?? CGPoint(x: (sourcePort.x + targetPort.x) / 2, y: (sourcePort.y + targetPort.y) / 2)
            edges[edgeIndex] = edgeAlong([sourcePort] + route.dropFirst().dropLast().map(axes.pagePoint) + [targetPort], edgeIndex: edgeIndex,
                                         ends: (sourceEnd, targetEnd), textCenter: textCenter)
        }
    }

    /// The two ends of a route on the sides of their nodes facing it, with what orders and spaces them.
    private func routeEnds(of edgeIndex: Int, route: [CGPoint]) -> [ReferenceClassDiagramEdgePorts.End] {
        let edge = measured.edges[edgeIndex]
        let last = route.count - 1
        // In a flow that runs down, an end's text goes right of its line when the line bends right or runs straight.
        func isTextAfter(bend: CGFloat) -> Bool { axes.flowIsVertical ? bend >= 0 : bend > 0 }
        return [
            ReferenceClassDiagramEdgePorts.End(edgeIndex: edgeIndex, isSourceEnd: true, node: edge.source,
                                      side: route[1].y > route[0].y ? axes.downstreamSide : axes.upstreamSide, neighborAlongSide: route[1].x,
                                      cardinalityWidth: edge.sourceCardinality?.size.width ?? 0, isTextAfter: isTextAfter(bend: route[1].x - route[0].x)),
            ReferenceClassDiagramEdgePorts.End(edgeIndex: edgeIndex, isSourceEnd: false, node: edge.target,
                                      side: route[last - 1].y < route[last].y ? axes.upstreamSide : axes.downstreamSide,
                                      neighborAlongSide: route[last - 1].x, cardinalityWidth: edge.targetCardinality?.size.width ?? 0,
                                      isTextAfter: isTextAfter(bend: route[last - 1].x - route[last].x)),
        ]
    }

    /// The edge through `ports`; `segmentsRunVertically` gives each segment's flow for a route through boxes, else every
    /// segment follows the diagram's.
    private func edgeAlong(_ ports: [CGPoint], edgeIndex: Int, ends: (source: ReferenceClassDiagramEdgePorts.End, target: ReferenceClassDiagramEdgePorts.End),
                           textCenter: CGPoint, segmentsRunVertically: [Bool]? = nil) -> ClassDiagramLayoutEdge {
        let edge = measured.edges[edgeIndex]
        var points = ports
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
            DiagramRouteDrawing.path(through: points, segmentsRunVertically: segmentAxes, startTrim: startTrim, endTrim: endTrim)
        } ?? DiagramRouteDrawing.path(through: points, flowIsVertical: axes.flowIsVertical, startTrim: startTrim, endTrim: endTrim)
        let leaving = CGVector(dx: -drawn.startDirection.dx, dy: -drawn.startDirection.dy)
        return ClassDiagramLayoutEdge(line: edge.line, path: drawn.path,
                                      sourceMark: mark(edge.sourceEnd, tip: points[0], direction: leaving),
                                      targetMark: mark(edge.targetEnd, tip: points[points.count - 1], direction: drawn.endDirection),
                                      text: centeredIfPresent(edge.text, at: textCenter),
                                      sourceCardinality: cardinality(edge.sourceCardinality, at: points[0], side: ends.source.side,
                                                                     isTextAfter: ends.source.isTextAfter),
                                      targetCardinality: cardinality(edge.targetCardinality, at: points[points.count - 1], side: ends.target.side,
                                                                     isTextAfter: ends.target.isTextAfter))
    }

    /// The point an end with a cardinality runs straight out to from its side before it bends, or nil.
    private func straightEnd(from port: CGPoint, toward neighbor: CGPoint, end: ReferenceClassDiagramEdgePorts.End) -> CGPoint? {
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
    /// where that is close (`ReferenceClassDiagramBorderRuns`); each segment an S along its own flow.
    mutating func placeEdges(clustered: ReferenceClassDiagramClusterGraph, placement: LayeredClusterPlacement) {
        let ends = clustered.layoutEdgeIndices.enumerated().flatMap { layoutIndex, edgeIndex in
            pageRouteEnds(of: edgeIndex, route: placement.edgeRoutes[layoutIndex])
        }
        let ports = ReferenceClassDiagramEdgePorts(ends: ends, edgeCount: measured.edges.count, nodeCenters: nodeCenters, sizes: measured.sizes,
                                          markRowHeight: markRowHeight)
        let borderRuns = ReferenceClassDiagramBorderRuns(graph: clustered.graph, clusterFrames: placement.clusterFrames, ends: ends)
        for (layoutIndex, edgeIndex) in clustered.layoutEdgeIndices.enumerated() {
            let route = placement.edgeRoutes[layoutIndex]
            guard let sourcePort = ports.sourcePoints[edgeIndex], let targetPort = ports.targetPoints[edgeIndex] else { continue }
            let points = borderRuns.straightened([sourcePort] + route.points.dropFirst().dropLast() + [targetPort],
                                                 source: ends[2 * layoutIndex], target: ends[2 * layoutIndex + 1])
            edgePoints.append(points)
            let textCenter = placement.edgeLabelCenters[layoutIndex] ?? CGPoint(x: (sourcePort.x + targetPort.x) / 2, y: (sourcePort.y + targetPort.y) / 2)
            edges[edgeIndex] = edgeAlong(points, edgeIndex: edgeIndex, ends: (ends[2 * layoutIndex], ends[2 * layoutIndex + 1]), textCenter: textCenter,
                                         segmentsRunVertically: route.segmentsRunVertically)
        }
    }

    /// The two ends of a route on the page, each on the side its first or last segment leaves or arrives by.
    private func pageRouteEnds(of edgeIndex: Int, route: LayeredClusterRoute) -> [ReferenceClassDiagramEdgePorts.End] {
        let edge = measured.edges[edgeIndex]
        func end(isSourceEnd: Bool) -> ReferenceClassDiagramEdgePorts.End {
            let points = route.points
            let point = isSourceEnd ? points[0] : points[points.count - 1]
            let next = isSourceEnd ? points[1] : points[points.count - 2]
            let runsVertically = isSourceEnd ? route.segmentsRunVertically[0] : route.segmentsRunVertically[route.segmentsRunVertically.count - 1]
            let side: DiagramSide = runsVertically ? (next.y > point.y ? .bottom : .top) : (next.x > point.x ? .right : .left)
            let bend = runsVertically ? next.x - point.x : next.y - point.y
            let cardinality = isSourceEnd ? edge.sourceCardinality : edge.targetCardinality
            return ReferenceClassDiagramEdgePorts.End(edgeIndex: edgeIndex, isSourceEnd: isSourceEnd, node: isSourceEnd ? edge.source : edge.target, side: side,
                                             neighborAlongSide: runsVertically ? next.x : next.y, cardinalityWidth: cardinality?.size.width ?? 0,
                                             isTextAfter: axes.flowIsVertical ? bend >= 0 : bend > 0)
        }
        return [end(isSourceEnd: true), end(isSourceEnd: false)]
    }

    /// The namespaces' boxes, each title along its box's top, clear of the relations where it can be.
    mutating func placeNamespaces(clustered: ReferenceClassDiagramClusterGraph, placement: LayeredClusterPlacement) {
        nodeNamespaces = clustered.nodeNamespaces
        namespaceParents = clustered.namespaceParents
        let crossings = FlowchartRoutePointIndex(edgePoints)
        namespaces = placement.clusterFrames.enumerated().map { index, frame in
            let title = clustered.titles[index].map { title in FlowchartClusterTitles.placed(title, in: frame, crossings: crossings) }
            return FlowchartLayoutCluster(frame: frame, title: title?.title, depth: clustered.depths[index], isTitleCrossed: title?.isCrossed ?? false)
        }
    }

    /// The loops of every class that has relations to itself.
    mutating func placeSelfLoops(_ selfLoops: [[Int]]) {
        for (node, loopEdgeIndices) in selfLoops.enumerated() {
            for (loopIndex, edgeIndex) in loopEdgeIndices.enumerated() {
                let edge = measured.edges[edgeIndex]
                let loop = ReferenceClassDiagramSelfLoops.loop(center: nodeCenters[node], boxSize: measured.sizes[node], loopIndex: loopIndex,
                                                      startTrim: ClassDiagramMarkGeometry.lineTrim(for: edge.sourceEnd),
                                                      endTrim: ClassDiagramMarkGeometry.lineTrim(for: edge.targetEnd),
                                                      textWidth: edge.text?.size.width ?? 0)
                let intoBox = CGVector(dx: -1, dy: 0)
                edges[edgeIndex] = ClassDiagramLayoutEdge(
                    line: edge.line, path: loop.path, sourceMark: mark(edge.sourceEnd, tip: loop.leave, direction: intoBox),
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
    private func cardinality(_ text: DiagramTextBlock?, at point: CGPoint, side: DiagramSide, isTextAfter: Bool) -> DiagramTextBlock? {
        guard let text else { return nil }
        let width = text.size.width
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
        return centered(text, at: center)
    }

    /// `text` centered at `center`, or nil when there is no text.
    private func centeredIfPresent(_ text: DiagramTextBlock?, at center: CGPoint) -> DiagramTextBlock? {
        text.map { text in centered(text, at: center) }
    }

    private func centered(_ text: DiagramTextBlock, at center: CGPoint) -> DiagramTextBlock {
        var placed = text
        placed.center = center
        return placed
    }

    /// The finished layout: everything moved so that the drawing starts `padding` from the top left, below the
    /// title, and centered under the title when the title is wider.
    /// The diagram's parts that nothing joins set in rows `rowWidth` wide, `gap` apart, as Pele's `wrapComponents` sets
    /// them for a diagram wider than its container (`ReferenceClassDiagramComponentRows`), with the size of the rows; nil when
    /// nothing moves.
    func wrappedInRows(rowWidth: CGFloat, gap: CGFloat) -> (page: ReferenceClassDiagramPageAssembly, size: CGSize)? {
        let frames = nodeCenters.indices.map { node in
            CGRect(x: nodeCenters[node].x - measured.sizes[node].width / 2, y: nodeCenters[node].y - measured.sizes[node].height / 2,
                   width: measured.sizes[node].width, height: measured.sizes[node].height)
        }
        let placedEdges = measured.edges.indices.map { index in
            edges[index].map { placed in ReferenceClassDiagramComponentRows.Edge(source: measured.edges[index].source, target: measured.edges[index].target, placed: placed) }
        }
        guard let rows = ReferenceClassDiagramComponentRows.placement(namespaceFrames: namespaces.map(\.frame), namespaceParents: namespaceParents,
                                                             nodeFrames: frames,
                                                             nodeNamespaces: nodeNamespaces.isEmpty ? Array(repeating: nil, count: frames.count) : nodeNamespaces,
                                                             edges: placedEdges, rowWidth: rowWidth, gap: gap) else { return nil }
        var wrapped = self
        wrapped.nodeCenters = zip(nodeCenters, rows.nodeOffsets).map { center, offset in center.translated(by: offset) }
        wrapped.edges = zip(edges, rows.edgeOffsets).map { edge, offset in edge?.translated(by: offset) }
        wrapped.namespaces = zip(namespaces, rows.namespaceOffsets).map { namespace, offset in namespace.translated(by: offset) }
        return (wrapped, rows.size)
    }

    /// `drawingBounds`: the rectangle the drawing is taken to cover, when it is set in rows; else the union of its parts.
    func finished(font: DiagramFont, title: DiagramTextBlock?, padding: CGFloat, titleGap: CGFloat, drawingBounds: CGRect? = nil) -> ClassDiagramLayout {
        let (classes, notes, interfaces) = placedNodes()
        var relations: [ClassDiagramLayoutEdge] = []
        var noteLinks: [ClassDiagramLayoutEdge] = []
        for (edgeIndex, edge) in measured.edges.enumerated() {
            guard let placed = edges[edgeIndex] else { continue }
            if edge.relationIndex == nil { noteLinks.append(placed) } else { relations.append(placed) }
        }
        let bounds = drawingBounds
            ?? ReferenceClassDiagramLayoutBounds.union(frames: classes.map(\.frame) + notes.map(\.frame) + interfaces.map(\.frame) + namespaces.map(\.frame),
                                              edges: relations + noteLinks)
        let titleSize = title?.size ?? .zero
        let innerWidth = max(bounds.width, titleSize.width)
        let titleHeight = title == nil ? 0 : titleSize.height + titleGap
        let offset = CGVector(dx: padding + (innerWidth - bounds.width) / 2 - bounds.minX, dy: padding + titleHeight - bounds.minY)
        let size = CGSize(width: (innerWidth + 2 * padding).rounded(.up), height: (bounds.height + titleHeight + 2 * padding).rounded(.up))
        var placedTitle = title
        placedTitle?.center = CGPoint(x: size.width / 2, y: padding + titleSize.height / 2)
        return ClassDiagramLayout(size: size, font: font, classes: classes.map { box in box.translated(by: offset) },
                                  notes: notes.map { note in note.translated(by: offset) },
                                  interfaces: interfaces.map { text in text.translated(by: offset) },
                                  relations: relations.map { edge in edge.translated(by: offset) },
                                  noteLinks: noteLinks.map { edge in edge.translated(by: offset) }, title: placedTitle,
                                  namespaces: namespaces.map { namespace in namespace.translated(by: offset) })
    }

    /// The classes' boxes, the notes and the interfaces' names at their nodes' centers.
    private func placedNodes() -> ([ClassDiagramLayoutClass], [ClassDiagramLayoutNote], [DiagramTextBlock]) {
        var classes: [ClassDiagramLayoutClass] = []
        var notes: [ClassDiagramLayoutNote] = []
        var interfaces: [DiagramTextBlock] = []
        for (node, kind) in measured.nodes.enumerated() {
            let center = nodeCenters[node]
            switch kind {
            case .classBox(let boxIndex): classes.append(measured.boxes[boxIndex].placed(at: center))
            case .note(let noteIndex):
                let size = measured.sizes[node]
                notes.append(ClassDiagramLayoutNote(frame: CGRect(x: center.x - size.width / 2, y: center.y - size.height / 2, width: size.width,
                                                                  height: size.height),
                                                    text: centered(measured.noteTexts[noteIndex], at: center)))
            case .interface(let interfaceIndex): interfaces.append(centered(measured.interfaceTexts[interfaceIndex], at: center))
            }
        }
        return (classes, notes, interfaces)
    }
}
