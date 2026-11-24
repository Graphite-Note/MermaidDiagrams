/**
 * File: LayeredCompoundRoutes.swift
 * ---------------------------------
 * Layer: Core
 * Description: Joins the routes of Pele's compound layout across levels, keeps placings to compare, and hints ports.
 *
 * Authors: Bahey Shalash
 * Version: 0.2
 * Date: 23/11/2026
 */

import CoreGraphics

/// What one placing of a compound layout put where, to come back to when another placing crosses more: copies of the
/// nodes', edges' and ports' plain values in the arena. The routes it points at stay, as the route points only grow.
struct LayeredCompoundSnapshot {
    let nodes: ScratchSpan<LayeredCompoundNode>
    let edges: ScratchSpan<LayeredCompoundSpanEdge>
    let origins: ScratchSpan<CGPoint>
    let borderPoints: ScratchSpan<CGPoint>
    let total: (width: Double, height: Double)
}

extension LayeredCompoundLayout {
    func snapshot() -> LayeredCompoundSnapshot {
        let origins: ScratchSpan<CGPoint> = arena.uninitializedSpan(count: levels.count)
        for levelIndex in 0..<levels.count { origins[levelIndex] = levels[levelIndex].origin }
        let borderPoints: ScratchSpan<CGPoint> = arena.uninitializedSpan(count: ports.count)
        for port in 0..<ports.count { borderPoints[port] = ports[port].borderPoint }
        return LayeredCompoundSnapshot(nodes: arena.copy(of: nodes), edges: arena.copy(of: edges), origins: origins, borderPoints: borderPoints,
                                       total: total)
    }

    mutating func restore(_ snapshot: LayeredCompoundSnapshot) {
        for index in 0..<nodes.count {
            nodes[index].x = snapshot.nodes[index].x
            nodes[index].y = snapshot.nodes[index].y
            nodes[index].width = snapshot.nodes[index].width
            nodes[index].height = snapshot.nodes[index].height
        }
        for index in 0..<edges.count {
            edges[index].routeStart = snapshot.edges[index].routeStart
            edges[index].routeCount = snapshot.edges[index].routeCount
            edges[index].labelCenter = snapshot.edges[index].labelCenter
        }
        for levelIndex in 0..<levels.count { levels[levelIndex].origin = snapshot.origins[levelIndex] }
        for port in 0..<ports.count { ports[port].borderPoint = snapshot.borderPoints[port] }
        total = snapshot.total
    }

    /// Every edge's route from its source through the ports of the groups it leaves, its level's route, and the ports of
    /// the groups it enters, repeated points left out; its label moved with its level.
    mutating func joinRoutes() {
        var inward = arena.list(capacity: 8, of: Int.self)
        for meetingLevel in 0..<levels.count {
            let level = levels[meetingLevel]
            for position in level.edges {
                let levelEdge = levelEdges[position]
                let edge = edges[levelEdge.edgeIndex]
                let start = routePoints.count
                var item = edge.source
                while nodes[item].parent != level.identifier {
                    let outward = levelIndex(of: nodes[item].parent)
                    appendRoute(ofPortIn: outward, edge: levelEdge.edgeIndex, isOutgoing: true, from: start)
                    item = nodes[item].parent
                }
                appendRoute(levelEdge.routeStart, count: levelEdge.routeCount, origin: level.origin, from: start)
                inward.removeAll()
                item = edge.target
                while nodes[item].parent != level.identifier {
                    inward.append(levelIndex(of: nodes[item].parent))
                    item = nodes[item].parent
                }
                for index in stride(from: inward.count - 1, through: 0, by: -1) {
                    appendRoute(ofPortIn: inward[index], edge: levelEdge.edgeIndex, isOutgoing: false, from: start)
                }
                edges[levelEdge.edgeIndex].routeStart = start
                edges[levelEdge.edgeIndex].routeCount = routePoints.count - start
                if edge.labelWidth > 0 {
                    edges[levelEdge.edgeIndex].labelCenter.x += level.origin.x
                    edges[levelEdge.edgeIndex].labelCenter.y += level.origin.y
                }
            }
        }
    }

    /// The route of the port of an edge's end in the level `levelIndex`, moved by the level's origin; none when it has none.
    private mutating func appendRoute(ofPortIn levelIndex: Int, edge: Int, isOutgoing: Bool, from start: Int) {
        let port = self.port(in: levelIndex, edge: edge, isOutgoing: isOutgoing)
        guard port >= 0 else { return }
        appendRoute(ports[port].routeStart, count: ports[port].routeCount, origin: levels[levelIndex].origin, from: start)
    }

    /// The route points `routeStart..<routeStart + count`, moved by `origin`, appended to the route begun at `start`; a
    /// point within a hundredth of the last one is left out.
    private mutating func appendRoute(_ routeStart: Int, count: Int, origin: CGPoint, from start: Int) {
        for index in routeStart..<(routeStart + count) {
            let routePoint = routePoints[index]
            let point = CGPoint(x: routePoint.point.x + origin.x, y: routePoint.point.y + origin.y)
            if routePoints.count > start {
                let last = routePoints[routePoints.count - 1]
                if abs(last.point.x - point.x) < 0.01, abs(last.point.y - point.y) < 0.01 { continue }
            }
            routePoints.append(LayeredRoutePoint(point: point, runsHorizontally: routePoint.runsHorizontally))
        }
    }

    /// Hints each port on the side a group's flow ends at with where its edge turns outside the group, past the straight
    /// run out of the port; whether some ports are hinted out of their order along the border.
    mutating func hintPorts() -> Bool {
        var isOutOfOrder = false
        var seen = arena.list(capacity: 8, of: LayeredCompoundPortHint.self)
        for levelIndex in 0..<levels.count where levels[levelIndex].identifier >= 0 {
            let level = levels[levelIndex]
            let box = nodes[level.identifier]
            let isVertical = level.direction.runsVertically
            seen.removeAll()
            for port in level.ports where ports[port].side == level.direction.endSide {
                guard let turn = turningAcross(of: ports[port], origin: level.origin, isVertical: isVertical) else { continue }
                let hint = turn - (isVertical ? box.x - box.width / 2 : box.y - box.height / 2)
                ports[port].hint = hint
                seen.append(LayeredCompoundPortHint(along: isVertical ? ports[port].borderPoint.x : ports[port].borderPoint.y, hint: hint))
            }
            seen.sortStably(in: arena) { first, second in first.along - second.along < 0 }
            for index in 1..<max(seen.count, 1) where seen[index - 1].hint > seen[index].hint { isOutOfOrder = true }
        }
        return isOutOfOrder
    }

    /// Where across the flow the edge through `port` is when it first leaves the line out of the port, or nil.
    private func turningAcross(of port: LayeredCompoundPort, origin: CGPoint, isVertical: Bool) -> Double? {
        let route = routeRange(of: port.edgeIndex)
        let border = CGPoint(x: origin.x + port.borderPoint.x, y: origin.y + port.borderPoint.y)
        var at = -1
        var index = 0
        while index < route.count && (at < 0 || port.isOutgoing) {
            let point = routePoints[route.lowerBound + index].point
            if abs(point.x - border.x) < 0.01 && abs(point.y - border.y) < 0.01 { at = index }
            index += 1
        }
        if at < 0 { return nil }
        func across(_ index: Int) -> Double { isVertical ? routePoints[route.lowerBound + index].point.x : routePoints[route.lowerBound + index].point.y }
        var next = port.isOutgoing ? at + 1 : at - 1
        while next >= 0 && next < route.count && abs(across(next) - across(at)) < LayeredCompoundConstants.inLine { next += port.isOutgoing ? 1 : -1 }
        if next < 0 || next >= route.count { return nil }
        return across(next)
    }
}

/// Where along a group's border a port is, and the hint its edge's turn outside gives it.
struct LayeredCompoundPortHint {
    let along: Double
    let hint: Double
}
