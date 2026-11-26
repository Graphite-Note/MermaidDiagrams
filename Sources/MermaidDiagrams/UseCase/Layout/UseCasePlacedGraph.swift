/**
 * File: UseCasePlacedGraph.swift
 * ------------------------------
 * Layer: Core
 * Description: A use case diagram laid out on spans of the calling thread's scratch arena: without boundaries by the
 *              flat layered layout, with them by the compound layout, the nodes, boxes, routes and label centers read
 *              from the layout's own lists, as the 0.7.0 cluster layout placed them, to the bit.
 *
 * Authors: Bahey Shalash
 * Version: 0.2
 * Date: 25/11/2026
 */

import CoreGraphics

/// The routes of the edges a use case layout laid out, one after the other in one list of points: each route a range of
/// it, and for each segment of a route, at the index of its first point, whether it follows a vertical flow.
struct UseCaseRoutes {
    let starts: ScratchSpan<Int>
    let counts: ScratchSpan<Int>
    let points: ScratchSpan<CGPoint>
    let segmentsRunVertically: ScratchSpan<Bool>

    var count: Int { starts.count }

    @inline(__always)
    func points(of route: Int) -> ScratchSpan<CGPoint> { points.part(starts[route]..<(starts[route] + counts[route])) }

    /// One per segment of the route.
    @inline(__always)
    func axes(of route: Int) -> ScratchSpan<Bool> {
        segmentsRunVertically.part(starts[route]..<(starts[route] + max(counts[route] - 1, 0)))
    }
}

/// Where the layered layout put a use case diagram, on the page from the origin: each node's center by its place among the
/// layout's nodes, each boundary's box by its place among the clusters, each laid-out edge's route and its label's center
/// (when it has a label), and the size. Built straight into the arena, as the 0.7.0 cluster layout placed the
/// diagram's boundaries as clusters, with the same arithmetic in the same order: a diagram without boundaries through
/// the flat layout, its one level as the compound layout would lay it out, any other through the compound layout.
struct UseCasePlacedGraph {
    let size: CGSize
    let nodeCenters: ScratchSpan<CGPoint>
    let clusterFrames: ScratchSpan<CGRect>
    let routes: UseCaseRoutes
    /// Each laid-out edge's label center, read only where `hasLabelCenter` says it has one.
    let labelCenters: ScratchSpan<CGPoint>
    let hasLabelCenter: ScratchSpan<Bool>

    /// The layout of `pass`, its `layoutPlaces` set; nil when it would need more than `maximumPointCount` points.
    init?(pass: inout UseCaseLayoutPass, spacing: LayeredSpacing, maximumPointCount: Int, arena: DiagramScratchArena) {
        let views = pass.views
        var clusterCount = 0
        var places = arena.list(capacity: views.count, of: Int.self)
        for view in views {
            if view.node.isGroup {
                places.append(clusterCount)
                clusterCount += 1
            } else {
                places.append(places.count - clusterCount)
            }
        }
        pass.layoutPlaces = Array(places.elements)
        let edgeCount = pass.laidOutEdges.count
        let direction = UseCaseLayoutEngine.layeredDirection(of: pass.diagram.direction)
        if clusterCount == 0 {
            guard let placed = Self.flat(pass, direction: direction, spacing: spacing, maximumPointCount: maximumPointCount, arena: arena) else {
                return nil
            }
            self = placed
        } else {
            guard let placed = Self.compound(pass, clusterCount: clusterCount, direction: direction, spacing: spacing,
                                             maximumPointCount: maximumPointCount, arena: arena) else {
                return nil
            }
            self = placed
        }
        assert(routes.count == edgeCount)
    }

    private init(size: CGSize, nodeCenters: ScratchSpan<CGPoint>, clusterFrames: ScratchSpan<CGRect>, routes: UseCaseRoutes,
                 labelCenters: ScratchSpan<CGPoint>, hasLabelCenter: ScratchSpan<Bool>) {
        self.size = size
        self.nodeCenters = nodeCenters
        self.clusterFrames = clusterFrames
        self.routes = routes
        self.labelCenters = labelCenters
        self.hasLabelCenter = hasLabelCenter
    }

    /// An edge's label room in the layout: its text and the room beyond it, or none for an edge without text.
    @inline(__always)
    private static func labelRoom(of label: DiagramTextBlock) -> (width: Double, height: Double) {
        guard label.size.width > 0 else { return (0, 0) }
        return (Double(label.size.width + UseCaseLayoutEngine.edgeLabelRoom.width), Double(label.size.height + UseCaseLayoutEngine.edgeLabelRoom.height))
    }

    /// A diagram without boundaries, as the compound layout lays out a graph of one level: one flat layout of the nodes
    /// and the edges that are not loops, turned onto the page in an unpadded box, each route without its repeated points.
    private static func flat(_ pass: UseCaseLayoutPass, direction: LayeredDirection, spacing: LayeredSpacing, maximumPointCount: Int,
                             arena: DiagramScratchArena) -> UseCasePlacedGraph? {
        let isVertical = direction.runsVertically
        let nodeCount = pass.views.count
        let nodes: ScratchSpan<LayeredFlatNode> = arena.uninitializedSpan(count: nodeCount)
        for node in 0..<nodeCount {
            let width = Double(pass.layoutSizes[node].width)
            let height = Double(pass.layoutSizes[node].height)
            nodes[node] = LayeredFlatNode(width: isVertical ? width : height, height: isVertical ? height : width)
        }
        var edges = arena.list(capacity: pass.laidOutEdges.count, of: LayeredSpanEdge.self)
        for drawn in pass.laidOutEdges where pass.layoutPlaces[drawn.source] != pass.layoutPlaces[drawn.target] {
            let room = labelRoom(of: drawn.label)
            edges.append(LayeredSpanEdge(tail: pass.layoutPlaces[drawn.source], head: pass.layoutPlaces[drawn.target],
                                         minimumLength: pass.graph.edges[drawn.edge].minimumLength,
                                         labelWidth: isVertical ? room.width : room.height, labelHeight: isVertical ? room.height : room.width,
                                         tailOffset: 0, headOffset: 0))
        }
        var flowPoints = arena.list(capacity: 4 * edges.count, of: CGPoint.self)
        guard let laidOut = LayeredFlatLayout.layout(nodes: nodes, edges: edges.elements, points: &flowPoints, options: LayeredFlatOptions(spacing),
                                                     maximumVertexCount: maximumPointCount, arena: arena) else {
            return nil
        }
        return flatPlacement(pass, nodes: nodes, edges: edges.elements, flowPoints: flowPoints.elements,
                             box: LayeredCompoundBox(direction: direction, size: laidOut, group: nil), arena: arena)
    }

    /// The flat layout turned onto the page: centers, routes and label centers as the compound layout writes them.
    private static func flatPlacement(_ pass: UseCaseLayoutPass, nodes: ScratchSpan<LayeredFlatNode>, edges: ScratchSpan<LayeredSpanEdge>,
                                      flowPoints: ScratchSpan<CGPoint>, box: LayeredCompoundBox, arena: DiagramScratchArena) -> UseCasePlacedGraph {
        // The compound layout moves a top-level box's points by its origin, (0, 0), which turns a -0 into 0.
        let origin = CGPoint.zero
        func onPage(_ flowPoint: CGPoint) -> CGPoint {
            let point = box.pagePoint(flowPoint)
            return CGPoint(x: point.x + origin.x, y: point.y + origin.y)
        }
        let centers: ScratchSpan<CGPoint> = arena.uninitializedSpan(count: nodes.count)
        for node in 0..<nodes.count { centers[node] = onPage(CGPoint(x: nodes[node].x, y: nodes[node].y)) }
        let routeCount = pass.laidOutEdges.count
        let starts: ScratchSpan<Int> = arena.uninitializedSpan(count: routeCount)
        let counts: ScratchSpan<Int> = arena.uninitializedSpan(count: routeCount)
        let labelCenters: ScratchSpan<CGPoint> = arena.uninitializedSpan(count: routeCount)
        let hasLabelCenter: ScratchSpan<Bool> = arena.uninitializedSpan(count: routeCount)
        var points = arena.list(capacity: flowPoints.count, of: CGPoint.self)
        var flatEdge = 0
        for (route, drawn) in pass.laidOutEdges.enumerated() {
            let source = pass.layoutPlaces[drawn.source]
            let labelWidth = labelRoom(of: drawn.label).width
            starts[route] = points.count
            hasLabelCenter[route] = labelWidth > 0
            if source == pass.layoutPlaces[drawn.target] {
                counts[route] = 0
                let node = centers[source]
                let width = Double(pass.layoutSizes[source].width)
                labelCenters[route] = CGPoint(x: node.x + width / 2 + LayeredCompoundConstants.loopLabelGap + labelWidth / 2, y: node.y)
                continue
            }
            let edge = edges[flatEdge]
            flatEdge += 1
            counts[route] = appendRoute(flowPoints.part(edge.pointStart..<(edge.pointStart + edge.pointCount)), to: &points, onPage: onPage)
            labelCenters[route] = onPage(edge.labelCenter)
        }
        let routes = UseCaseRoutes(starts: starts, counts: counts, points: points.elements,
                                   segmentsRunVertically: arena.span(count: points.count, repeating: box.direction.runsVertically))
        return UseCasePlacedGraph(size: CGSize(width: box.width, height: box.height), nodeCenters: centers, clusterFrames: .empty, routes: routes,
                                  labelCenters: labelCenters, hasLabelCenter: hasLabelCenter)
    }

    /// A flat route's points appended on the page, each within 0.01 of the one before it left out; returns how many were.
    private static func appendRoute(_ flowPoints: ScratchSpan<CGPoint>, to points: inout ScratchList<CGPoint>,
                                    onPage: (CGPoint) -> CGPoint) -> Int {
        let start = points.count
        for flowPoint in flowPoints {
            let point = onPage(flowPoint)
            if points.count > start, abs(points[points.count - 1].x - point.x) < 0.01, abs(points[points.count - 1].y - point.y) < 0.01 { continue }
            points.append(point)
        }
        return points.count - start
    }

    /// A diagram with boundaries, as the compound layout places it: the nodes in declaration order
    /// then each boundary as a group after them, laid out by the compound layout, read from its lists.
    private static func compound(_ pass: UseCaseLayoutPass, clusterCount: Int, direction: LayeredDirection, spacing: LayeredSpacing,
                                 maximumPointCount: Int, arena: DiagramScratchArena) -> UseCasePlacedGraph? {
        let nodes = compoundNodes(pass, clusterCount: clusterCount, arena: arena)
        let edges: ScratchSpan<LayeredCompoundSpanEdge> = arena.uninitializedSpan(count: pass.laidOutEdges.count)
        for (edgeIndex, drawn) in pass.laidOutEdges.enumerated() {
            let room = labelRoom(of: drawn.label)
            edges[edgeIndex] = LayeredCompoundSpanEdge(source: pass.layoutPlaces[drawn.source], target: pass.layoutPlaces[drawn.target],
                                                       minimumLength: pass.graph.edges[drawn.edge].minimumLength,
                                                       labelWidth: room.width, labelHeight: room.height)
        }
        var layout = LayeredCompoundLayout(nodes: nodes, edges: edges, rootDirection: direction, options: LayeredFlatOptions(spacing),
                                           maximumVertexCount: maximumPointCount, arena: arena)
        guard LayeredCompoundLayout.layout(&layout) != nil else { return nil }
        return compoundPlacement(layout, nodeCount: nodes.count - clusterCount, clusterCount: clusterCount, arena: arena)
    }

    /// The nodes in their places among the layout's nodes, then each boundary as a group after them, in its place among the
    /// clusters.
    private static func compoundNodes(_ pass: UseCaseLayoutPass, clusterCount: Int, arena: DiagramScratchArena) -> ScratchSpan<LayeredCompoundNode> {
        let views = pass.views
        let nodeCount = views.count - clusterCount
        // A node finds its boundary by the boundary's identifier, the last boundary listed under it, wherever it was listed.
        var clusterOfIdentifier: [String: Int] = [:]
        for (place, view) in views.enumerated() where view.node.isGroup { clusterOfIdentifier[view.node.identifier] = pass.layoutPlaces[place] }
        let nodes: ScratchSpan<LayeredCompoundNode> = arena.uninitializedSpan(count: views.count)
        for (place, view) in views.enumerated() {
            let layoutPlace = pass.layoutPlaces[place]
            guard view.node.isGroup else {
                let cluster = view.node.parentIdentifier.flatMap { parent in clusterOfIdentifier[parent] }
                var node = LayeredCompoundNode(width: Double(pass.layoutSizes[place].width), height: Double(pass.layoutSizes[place].height),
                                               parent: cluster.map { cluster in nodeCount + cluster } ?? -1)
                node.sequence = Double(layoutPlace)
                node.sideSpan = 0
                nodes[layoutPlace] = node
                continue
            }
            var group = LayeredCompoundNode(width: 0, height: 0, parent: -1)
            group.isGroup = true
            group.direction = nil
            group.paddingSide = Double(view.clusterPadding.side)
            group.paddingTop = Double(view.clusterPadding.top)
            group.paddingBottom = Double(view.clusterPadding.bottom)
            group.minimumWidth = Double(view.clusterMinimumWidth)
            group.sequence = Double(CGFloat(nodeCount + layoutPlace))
            group.sideSpan = 0
            nodes[nodeCount + layoutPlace] = group
        }
        return nodes
    }

    /// The compound layout read from its lists: the boxes, each route's points with its segments' flows, the label
    /// centers of edges with labels and of edges between a box and what it holds, the centers and the size.
    private static func compoundPlacement(_ layout: LayeredCompoundLayout, nodeCount: Int, clusterCount: Int,
                                          arena: DiagramScratchArena) -> UseCasePlacedGraph {
        let nodes = layout.nodes
        let edges = layout.edges
        let frames: ScratchSpan<CGRect> = arena.uninitializedSpan(count: clusterCount)
        for cluster in 0..<clusterCount {
            let node = nodes[nodeCount + cluster]
            frames[cluster] = CGRect(x: node.x - node.width / 2, y: node.y - node.height / 2, width: node.width, height: node.height)
        }
        let starts: ScratchSpan<Int> = arena.uninitializedSpan(count: edges.count)
        let counts: ScratchSpan<Int> = arena.uninitializedSpan(count: edges.count)
        let labelCenters: ScratchSpan<CGPoint> = arena.uninitializedSpan(count: edges.count)
        let hasLabelCenter: ScratchSpan<Bool> = arena.uninitializedSpan(count: edges.count)
        var totalPointCount = 0
        for edgeIndex in 0..<edges.count { totalPointCount += edges[edgeIndex].routeCount }
        let points: ScratchSpan<CGPoint> = arena.uninitializedSpan(count: totalPointCount)
        let axes = arena.span(count: totalPointCount, repeating: false)
        var next = 0
        for edgeIndex in 0..<edges.count {
            starts[edgeIndex] = next
            let range = layout.routeRange(of: edgeIndex)
            counts[edgeIndex] = range.count
            for (offset, routePoint) in layout.routePoints[range].enumerated() {
                points[next + offset] = routePoint.point
                if offset > 0 { axes[next + offset - 1] = !routePoint.runsHorizontally }
            }
            next += range.count
            labelCenters[edgeIndex] = edges[edgeIndex].labelCenter
            hasLabelCenter[edgeIndex] = edges[edgeIndex].labelWidth > 0 || layout.isStray(edgeIndex)
        }
        let centers: ScratchSpan<CGPoint> = arena.uninitializedSpan(count: nodeCount)
        for node in 0..<nodeCount { centers[node] = CGPoint(x: nodes[node].x, y: nodes[node].y) }
        return UseCasePlacedGraph(size: CGSize(width: layout.total.width, height: layout.total.height), nodeCenters: centers, clusterFrames: frames,
                                  routes: UseCaseRoutes(starts: starts, counts: counts, points: points, segmentsRunVertically: axes),
                                  labelCenters: labelCenters, hasLabelCenter: hasLabelCenter)
    }
}
