/**
 * File: ArchitectureEdgeLayout.swift
 * ----------------------------------
 * Layer: Core
 * Description: Lays out an architecture diagram's edges as Pele's renderer does: a port on each side named, through a
 *              group's border for `{group}`, routes, arrows, each text on its longest run (its longest level one when
 *              that holds it) moved off the boxes it would cover, and what the drawing then reaches.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 19/11/2026
 */

import CoreGraphics

/// The edges of an architecture diagram laid out in the grid's coordinates.
struct ArchitectureEdgeLayout {
    private(set) var edges: [ArchitectureLayoutEdge] = []
    private(set) var texts: [DiagramTextBlock] = []
    /// What is drawn: the grid, grown by the routes (4 points round each point) and the texts.
    private(set) var extent: CGRect
    /// The vertical runs of the routes, as x and the run's top and bottom, which group titles keep from under.
    private(set) var verticalRuns: [(x: CGFloat, top: CGFloat, bottom: CGFloat)] = []
    let frames: ArchitectureGroupFrames
    let diagram: ArchitectureDiagram
    let iconSize: CGFloat

    /// The radius of a junction's dot, where an arrow stops short of it.
    static let junctionRadius: CGFloat = 3
    /// How far apart the two ends of an edge from a side back to the same side are put.
    static let loopSpread: CGFloat = 8

    init(_ diagram: ArchitectureDiagram, frames: ArchitectureGroupFrames, iconSize: CGFloat) {
        self.diagram = diagram
        self.frames = frames
        self.iconSize = iconSize
        extent = CGRect(origin: .zero, size: frames.innerSize)
        for index in diagram.edges.indices { layOut(index) }
    }

    /// Pele's `port`: where an edge meets `node`'s `side`, or its group's border when it crosses it.
    func port(of node: Int, side: ArchitectureSide, throughGroup: Bool) -> ArchitecturePort {
        let normal = CGVector(dx: CGFloat(side.step.dx), dy: CGFloat(side.step.dy))
        let anchor = frames.nodeAnchor(node)
        let half = iconSize / 2
        let box = frames.sizes.boxSizes[node]
        var port = ArchitecturePort(point: CGPoint(x: anchor.x, y: anchor.y + half), normal: normal,
                                    box: CGRect(x: anchor.x - box.width / 2, y: anchor.y, width: box.width, height: box.height), gap: 0,
                                    continuesToJunction: false)
        let isJunction = diagram.nodes[node].kind == .junction
        if isJunction {
            port.box = CGRect(origin: port.point, size: .zero)
            port.gap = Self.junctionRadius
        } else if normal.dx != 0 {
            port.point.x = anchor.x + normal.dx * half
        } else {
            port.point.y = normal.dy < 0 ? anchor.y : anchor.y + box.height + (frames.sizes.nodeTitles[node] == nil ? 0 : 2)
        }
        guard throughGroup, let group = diagram.nodes[node].groupIndex else { return port }
        port.box = frames.frame(of: group)
        port.gap = 0
        port.continuesToJunction = isJunction
        if normal.dx != 0 { port.point.x = normal.dx < 0 ? port.box.minX : port.box.maxX } else { port.point.y = normal.dy < 0 ? port.box.minY : port.box.maxY }
        return port
    }

    private mutating func layOut(_ index: Int) {
        let edge = diagram.edges[index]
        var start = port(of: edge.sourceIndex, side: edge.sourceSide, throughGroup: edge.leavesSourceGroup)
        var end = port(of: edge.targetIndex, side: edge.targetSide, throughGroup: edge.entersTargetGroup)
        if start.point == end.point, start.normal.dx == end.normal.dx {
            // From a side back to the same side: the two ends parted so that it shows as a loop.
            let across = CGVector(dx: Self.loopSpread * abs(start.normal.dy), dy: Self.loopSpread * abs(start.normal.dx))
            start.point = CGPoint(x: start.point.x - across.dx, y: start.point.y - across.dy)
            end.point = CGPoint(x: end.point.x + across.dx, y: end.point.y + across.dy)
        }
        var routed = ArchitectureEdgeRouting.route(from: start, to: end)
        if start.continuesToJunction { routed.insert(junctionCenter(edge.sourceIndex), at: 0) }
        if end.continuesToJunction { routed.append(junctionCenter(edge.targetIndex)) }
        let points = ArchitectureEdgeRouting.simplified(routed)
        guard points.count >= 2 else { return }
        let trim = DiagramEdgeMark.lineTrim(for: .arrow)
        let path = ArchitectureEdgeRouting.path(through: points, startTrim: edge.hasSourceArrow && !start.continuesToJunction ? trim + start.gap : 0,
                                                endTrim: edge.hasTargetArrow && !end.continuesToJunction ? trim + end.gap : 0)
        edges.append(ArchitectureLayoutEdge(sourceIdentifier: diagram.nodes[edge.sourceIndex].identifier, targetIdentifier: diagram.nodes[edge.targetIndex].identifier,
                                            path: path, sourceArrow: edge.hasSourceArrow ? Self.arrow(at: start) : nil,
                                            targetArrow: edge.hasTargetArrow ? Self.arrow(at: end) : nil))
        for point in points { extent = extent.union(CGRect(x: point.x - 4, y: point.y - 4, width: 8, height: 8)) }
        placeText(frames.sizes.edgeTitles[index], along: points, ports: [start, end])
    }

    /// The arrow at a port, its tip short of a junction's dot, pointing into the side.
    private static func arrow(at port: ArchitecturePort) -> DiagramEdgeMark {
        DiagramEdgeMark(arrowhead: .arrow, tip: CGPoint(x: port.point.x + port.normal.dx * port.gap, y: port.point.y + port.normal.dy * port.gap),
                        direction: CGVector(dx: -port.normal.dx, dy: -port.normal.dy))
    }

    private func junctionCenter(_ node: Int) -> CGPoint {
        let anchor = frames.nodeAnchor(node)
        return CGPoint(x: anchor.x, y: anchor.y + iconSize / 2)
    }

    /// The text at the middle of the longest run (the longest level run when it holds the text and 8 points), moved off
    /// a box it would land on beside a short run.
    private mutating func placeText(_ text: DiagramTextBlock?, along points: [CGPoint], ports: [ArchitecturePort]) {
        var best = (index: -1, length: CGFloat(-1))
        var level = (index: -1, length: CGFloat(-1))
        for index in 0..<(points.count - 1) {
            let (from, to) = (points[index], points[index + 1])
            let isLevel = abs(from.y - to.y) < 0.01
            let length = abs(from.x - to.x) + abs(from.y - to.y)
            if !isLevel { verticalRuns.append((from.x, min(from.y, to.y), max(from.y, to.y))) }
            if length > best.length { best = (index, length) }
            if isLevel, length > level.length { level = (index, length) }
        }
        guard let text, text.size.width > 0 else { return }
        let size = CGSize(width: text.size.width + 8, height: text.size.height)
        let at = level.length >= size.width ? level.index : best.index
        var center = CGPoint(x: (points[at].x + points[at + 1].x) / 2, y: (points[at].y + points[at + 1].y) / 2)
        let isUpright = abs(points[at].x - points[at + 1].x) < 0.01
        for port in ports {
            let box = port.box
            if center.x + size.width / 2 <= box.minX || center.x - size.width / 2 >= box.maxX
                || center.y + size.height / 2 <= box.minY || center.y - size.height / 2 >= box.maxY { continue }
            if isUpright {
                center.x = center.x >= box.midX ? box.maxX + size.width / 2 + 4 : box.minX - size.width / 2 - 4
            } else {
                center.y = center.y >= box.midY ? box.maxY + size.height / 2 + 4 : box.minY - size.height / 2 - 4
            }
        }
        extent = extent.union(CGRect(x: center.x - size.width / 2, y: center.y - size.height / 2, width: size.width, height: size.height))
        texts.append(PlaneMapLabel.placed(text, at: center))
    }
}
