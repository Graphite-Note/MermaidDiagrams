/**
 * File: LayeredCompoundPlacing.swift
 * ----------------------------------
 * Layer: Core
 * Description: One placing of Pele's compound layout: the sides edges cross groups on, each level laid out children
 *              first and moved to its box, its routes written as ranges of the layout's route points.
 *
 * Authors: Bahey Shalash
 * Version: 0.3
 * Date: 24/11/2026
 */

import CoreGraphics

extension LayeredCompoundLayout {
    /// Pele's `place`: the sides of the groups that edges cross from the ranks of their parents, the levels laid out
    /// children first so that their sizes are known, each level moved to its box, and every edge's route joined from
    /// the pieces in the levels it passes. False when a level would need more vertices than the limit.
    mutating func place() -> Bool {
        assignPortSides()
        var vertexBudget = maximumVertexCount
        for levelIndex in stride(from: levels.count - 1, through: 0, by: -1) {
            guard layOut(levelIndex, vertexBudget: &vertexBudget) else { return false }
        }
        for levelIndex in 0..<levels.count {
            let origin = levels[levelIndex].origin
            for position in levels[levelIndex].items {
                let item = levelItems[position]
                nodes[item].x += origin.x
                nodes[item].y += origin.y
                if nodes[item].isGroup {
                    levels[levelOfGroup[item]].origin = CGPoint(x: nodes[item].x - nodes[item].width / 2, y: nodes[item].y - nodes[item].height / 2)
                }
            }
        }
        joinRoutes()
        return true
    }

    /// Ranks each level's parents first to decide which side of a group each edge crosses: a port in a group takes the
    /// side of the port its edge passes through in the level above, and an edge between two items of a level leaves a
    /// group on the side facing where it is ranked to go.
    private mutating func assignPortSides() {
        for levelIndex in 0..<levels.count {
            let level = levels[levelIndex]
            for port in level.ports {
                let inner = ports[port].inner
                guard nodes[inner].isGroup && endsBelow(inner, edge: ports[port].edgeIndex, isOutgoing: ports[port].isOutgoing) else { continue }
                let innerPort = self.port(in: levelOfGroup[inner], edge: ports[port].edgeIndex, isOutgoing: ports[port].isOutgoing)
                if innerPort >= 0 { ports[innerPort].side = ports[port].side }
            }
            var isNeeded = false
            for position in level.edges where crossesIntoGroup(levelEdges[position]) { isNeeded = true }
            if !isNeeded { continue }
            let mark = arena.mark()
            defer { arena.release(to: mark) }
            let graph = buildGraph(of: levelIndex, isSized: false)
            LayeredFlatRanking.orientAndRank(nodes: graph.nodes.elements, edges: graph.edges.elements, step: 1, arena: arena)
            let start = level.direction.startSide
            for (index, position) in level.edges.enumerated() {
                let levelEdge = levelEdges[position]
                let isFirstAbove = !graph.edges[index].isReversed
                if nodes[levelEdge.first].isGroup && edges[levelEdge.edgeIndex].source != levelEdge.first {
                    setSide(of: levelEdge.first, edge: levelEdge.edgeIndex, isOutgoing: true, to: isFirstAbove ? start.opposite : start)
                }
                if nodes[levelEdge.second].isGroup && edges[levelEdge.edgeIndex].target != levelEdge.second {
                    setSide(of: levelEdge.second, edge: levelEdge.edgeIndex, isOutgoing: false, to: isFirstAbove ? start : start.opposite)
                }
            }
        }
    }

    /// Whether an edge of a level passes into a group at either end.
    private func crossesIntoGroup(_ levelEdge: LayeredCompoundLevelEdge) -> Bool {
        (nodes[levelEdge.first].isGroup && edges[levelEdge.edgeIndex].source != levelEdge.first)
            || (nodes[levelEdge.second].isGroup && edges[levelEdge.edgeIndex].target != levelEdge.second)
    }

    private mutating func setSide(of group: Int, edge: Int, isOutgoing: Bool, to side: DiagramSide) {
        let port = self.port(in: levelOfGroup[group], edge: edge, isOutgoing: isOutgoing)
        if port >= 0 { ports[port].side = side }
    }

    /// Lays one level out as a flat graph and turns it onto the page inside its box.
    private mutating func layOut(_ levelIndex: Int, vertexBudget: inout Int) -> Bool {
        let mark = arena.mark()
        defer { arena.release(to: mark) }
        let built = buildGraph(of: levelIndex, isSized: true)
        var points = arena.list(capacity: 4 * built.edges.count, of: CGPoint.self)
        guard let size = LayeredFlatLayout.layout(nodes: built.nodes.elements, edges: built.edges.elements, points: &points, options: options,
                                                  maximumVertexCount: vertexBudget, arena: arena) else {
            return false
        }
        vertexBudget -= built.nodes.count
        let level = levels[levelIndex]
        let group = level.identifier >= 0 ? nodes[level.identifier] : nil
        let box = LayeredCompoundBox(direction: level.direction, size: size, group: group)
        for (index, position) in level.items.enumerated() {
            let point = box.pagePoint(CGPoint(x: built.nodes[index].x, y: built.nodes[index].y))
            nodes[levelItems[position]].x = point.x
            nodes[levelItems[position]].y = point.y
        }
        writeRoutes(of: levelIndex, built: built, points: points.elements, box: box)
        if level.identifier >= 0 {
            nodes[level.identifier].width = box.width
            nodes[level.identifier].height = box.height
        } else {
            total = (box.width, box.height)
        }
        return true
    }

    /// The routes of the level's edges and ports on the page, and its edges' label centers.
    private mutating func writeRoutes(of levelIndex: Int, built: LayeredCompoundLevelGraph, points: ScratchSpan<CGPoint>, box: LayeredCompoundBox) {
        func route(of flatEdge: LayeredSpanEdge) -> ScratchSpan<CGPoint> {
            flatEdge.pointStart >= 0 ? points.part(flatEdge.pointStart..<(flatEdge.pointStart + flatEdge.pointCount)) : .empty
        }
        let level = levels[levelIndex]
        for (index, position) in level.edges.enumerated() {
            let flatEdge = built.edges[index]
            let start = routePoints.count
            box.appendRoute(route(of: flatEdge), to: &routePoints)
            levelEdges[position].routeStart = start
            levelEdges[position].routeCount = routePoints.count - start
            let edgeIndex = levelEdges[position].edgeIndex
            if edges[edgeIndex].labelWidth > 0 { edges[edgeIndex].labelCenter = box.pagePoint(flatEdge.labelCenter) }
        }
        var portEdge = level.edges.count
        for (index, port) in level.ports.enumerated() {
            if built.portVertex[index] >= 0 {
                placeBorderPort(port, route: route(of: built.edges[portEdge]), box: box)
                portEdge += 1
            } else {
                placeSidePort(port, box: box)
            }
        }
    }
}
