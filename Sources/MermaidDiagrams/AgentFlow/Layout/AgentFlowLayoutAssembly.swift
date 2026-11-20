/**
 * File: AgentFlowLayoutAssembly.swift
 * -----------------------------------
 * Layer: Core
 * Description: An agent flow's layout from the flowchart's: nodes and flows with their palette slots and styles, the
 *              laid-out edges by meaning, and the edges between a node and a flow around it drawn as Pele draws them.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 19/11/2026
 */

import CoreGraphics

struct AgentFlowLayoutAssembly {
    let layout: AgentFlowLayout

    init(diagram: AgentFlowDiagram, clustered: AgentFlowClusterGraph, measurement: AgentFlowMeasurement, laidOut: FlowchartLayout) {
        let graph = diagram.graph
        let nodes = zip(clustered.drawnGraphIndices, laidOut.nodes).map { graphIndex, placed in
            let node = graph.nodes[graphIndex]
            let isCollapsed = node.shape == "collapsedGroup"
            return AgentFlowLayoutNode(identifier: node.identifier, shape: placed.shape, isCollapsedFlow: isCollapsed, frame: placed.frame,
                                       text: placed.text,
                                       paletteSlot: isCollapsed ? node.colorIndex ?? AgentFlowVertexKind.allCases.count : (node.kind ?? .task).paletteSlot,
                                       kind: isCollapsed ? nil : node.kind ?? .task, style: measurement.styles[graphIndex],
                                       isBold: measurement.textLooks[graphIndex].isBold, isItalic: measurement.textLooks[graphIndex].isItalic)
        }
        let flows = zip(clustered.subgraphGraphIndices, laidOut.clusters).map { graphIndex, cluster in
            AgentFlowLayoutFlow(identifier: graph.nodes[graphIndex].identifier, frame: cluster.frame, title: cluster.title,
                                paletteSlot: graph.nodes[graphIndex].colorIndex ?? AgentFlowVertexKind.allCases.count, style: measurement.styles[graphIndex])
        }
        var edges = zip(clustered.laidOutEdgeIndices, laidOut.edges).map { edgeIndex, placed in
            Self.edge(graph.edges[edgeIndex], path: placed.path, mark: placed.targetMark, text: placed.text)
        }
        var frames = [CGRect](repeating: .null, count: graph.nodes.count)
        for (graphIndex, node) in zip(clustered.drawnGraphIndices, nodes) { frames[graphIndex] = node.frame }
        for (graphIndex, flow) in zip(clustered.subgraphGraphIndices, flows) { frames[graphIndex] = flow.frame }
        let held = AgentFlowHeldEdges(clustered: clustered, frames: frames,
                                      shapes: Dictionary(uniqueKeysWithValues: zip(clustered.drawnGraphIndices, nodes.map(\.shape))))
        for (edgeIndex, source, target) in clustered.heldEdges {
            let edge = graph.edges[edgeIndex]
            let arrowhead = AgentFlowClusterGraph.arrowhead(of: edge)
            let route = held.route(source: source, target: target, arrowhead: arrowhead, isCareful: clustered.heldEdges.count * graph.nodes.count < 2_000_000)
            let text = measurement.heldEdgeTexts[edgeIndex].map { text in
                var centered = text
                centered.center = route.textCenter
                return centered
            }
            edges.append(Self.edge(edge, path: route.path, mark: route.mark, text: text))
        }
        layout = AgentFlowLayout(size: laidOut.size, font: laidOut.font, title: laidOut.title, flows: flows, nodes: nodes, edges: edges)
    }

    private static func edge(_ edge: AgentFlowGraphEdge, path: DiagramPath, mark: DiagramEdgeMark?, text: DiagramTextBlock?) -> AgentFlowLayoutEdge {
        let isDotted = edge.thickness == "dotted"
        let semantic: AgentFlowEdgeSemantic = isDotted ? .reference : edge.arrowTypeEnd == "arrow_cross" ? .failure : .sequence
        return AgentFlowLayoutEdge(identifier: edge.identifier, semantic: semantic, isDotted: isDotted, path: path, targetMark: mark, text: text,
                                   style: AgentFlowMeasurement.style(edge.compiledStyles + edge.style))
    }
}

/// The edges between a node and a flow around it, which the layout has no place for, as Pele's render.ts draws them:
/// straight between the node and the flow's border, out along the flow's direction or in against it; when another
/// node is in the way, from another side instead, and failing that from the far side.
struct AgentFlowHeldEdges {
    let clustered: AgentFlowClusterGraph
    let frames: [CGRect]
    let shapes: [Int: FlowchartNodeShape]

    struct Route {
        let path: DiagramPath
        let mark: DiagramEdgeMark?
        let textCenter: CGPoint
    }

    func route(source: Int, target: Int, arrowhead: FlowchartArrowhead, isCareful: Bool) -> Route {
        let goesOut = clustered.contains(target, source)
        let outer = goesOut ? target : source
        let inner = goesOut ? source : target
        let flowEnd = Self.flowEndSide(clustered.flowDirection(of: outer))
        let first = goesOut ? flowEnd : (flowEnd + 2) & 3
        var points = toward(first, inner: inner, outer: outer, goesOut: goesOut)
        if isCareful, isBlocked(points, inner: inner) {
            for side in [(first + 1) & 3, (first + 3) & 3, (first + 2) & 3] {
                let other = toward(side, inner: inner, outer: outer, goesOut: goesOut)
                if !isBlocked(other, inner: inner) {
                    points = other
                    break
                }
            }
        }
        let textCenter = CGPoint(x: (points.start.x + points.end.x) / 2, y: (points.start.y + points.end.y) / 2)
        var start = points.start
        var end = points.end
        if let shape = shapes[inner] {
            if goesOut { start = inset(start, inner: inner, shape: shape) } else { end = inset(end, inner: inner, shape: shape) }
        }
        let length = max(((end.x - start.x) * (end.x - start.x) + (end.y - start.y) * (end.y - start.y)).squareRoot(), 0.0001)
        let direction = CGVector(dx: (end.x - start.x) / length, dy: (end.y - start.y) / length)
        let trim = min(DiagramEdgeMark.lineTrim(for: arrowhead), length)
        let lineEnd = CGPoint(x: end.x - direction.dx * trim, y: end.y - direction.dy * trim)
        let mark = arrowhead == .none ? nil : DiagramEdgeMark(arrowhead: arrowhead, tip: end, direction: direction)
        return Route(path: DiagramPath(start: start, segments: [.line(to: lineEnd)]), mark: mark, textCenter: textCenter)
    }

    /// The side a flow runs toward, the sides numbered clockwise from the top.
    private static func flowEndSide(_ direction: FlowchartDirection) -> Int {
        switch direction {
        case .topToBottom: 2
        case .rightToLeft: 3
        case .bottomToTop: 0
        case .leftToRight: 1
        }
    }

    /// From the node's side to the flow's border straight across from it: out of the node when the edge goes out, else in.
    private func toward(_ side: Int, inner: Int, outer: Int, goesOut: Bool) -> (start: CGPoint, end: CGPoint) {
        let node = frames[inner]
        let box = frames[outer]
        let isUpright = side & 1 == 0
        let sign: CGFloat = side == 0 || side == 3 ? -1 : 1
        let nodePoint = isUpright ? CGPoint(x: node.midX, y: node.midY + sign * node.height / 2) : CGPoint(x: node.midX + sign * node.width / 2, y: node.midY)
        let borderPoint = isUpright ? CGPoint(x: node.midX, y: box.midY + sign * box.height / 2) : CGPoint(x: box.midX + sign * box.width / 2, y: node.midY)
        return goesOut ? (nodePoint, borderPoint) : (borderPoint, nodePoint)
    }

    /// Whether a node other than the edge's own lies on the way, a point either side.
    private func isBlocked(_ points: (start: CGPoint, end: CGPoint), inner: Int) -> Bool {
        let way = CGRect(x: min(points.start.x, points.end.x) - 1, y: min(points.start.y, points.end.y) - 1,
                         width: abs(points.end.x - points.start.x) + 2, height: abs(points.end.y - points.start.y) + 2)
        return shapes.keys.contains { node in node != inner && frames[node].intersects(way) && !frames[node].isNull }
    }

    /// An end on a node's box moved in to its shape's outline.
    private func inset(_ point: CGPoint, inner: Int, shape: FlowchartNodeShape) -> CGPoint {
        let frame = frames[inner]
        let side: DiagramSide = abs(point.y - frame.minY) < 0.5 ? .top : abs(point.y - frame.maxY) < 0.5 ? .bottom
            : point.x < frame.midX ? .left : .right
        let offset = side.isHorizontal ? point.x - frame.midX : point.y - frame.midY
        let amount = FlowchartShapeGeometry.inset(of: shape, size: frame.size, side: side, offset: offset)
        switch side {
        case .top: return CGPoint(x: point.x, y: point.y + amount)
        case .bottom: return CGPoint(x: point.x, y: point.y - amount)
        case .left: return CGPoint(x: point.x + amount, y: point.y)
        case .right: return CGPoint(x: point.x - amount, y: point.y)
        }
    }
}
