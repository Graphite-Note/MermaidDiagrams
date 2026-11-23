/**
 * File: LayeredCompoundRoutes.swift
 * ---------------------------------
 * Layer: Core
 * Description: Joins the routes of Pele's compound layout across levels, keeps placings to compare, and hints ports.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 23/11/2026
 */

import CoreGraphics

/// What one placing of a compound layout put where, to come back to when another placing crosses more.
struct LayeredCompoundSnapshot {
    var nodes: [LayeredCompoundNode]
    var edges: [LayeredCompoundEdge]
    var origins: [CGPoint]
    var borderPoints: [[CGPoint]]
    var total: (width: Double, height: Double)
}

extension LayeredCompoundLayout {
    func snapshot() -> LayeredCompoundSnapshot {
        LayeredCompoundSnapshot(nodes: nodes, edges: edges, origins: levels.map(\.origin),
                                borderPoints: levels.map { level in level.ports.map(\.borderPoint) }, total: total)
    }

    mutating func restore(_ snapshot: LayeredCompoundSnapshot) {
        for index in nodes.indices {
            nodes[index].x = snapshot.nodes[index].x
            nodes[index].y = snapshot.nodes[index].y
            nodes[index].width = snapshot.nodes[index].width
            nodes[index].height = snapshot.nodes[index].height
        }
        for index in edges.indices {
            edges[index].route = snapshot.edges[index].route
            edges[index].labelCenter = snapshot.edges[index].labelCenter
        }
        for levelIndex in levels.indices {
            levels[levelIndex].origin = snapshot.origins[levelIndex]
            for portIndex in levels[levelIndex].ports.indices { levels[levelIndex].ports[portIndex].borderPoint = snapshot.borderPoints[levelIndex][portIndex] }
        }
        total = snapshot.total
    }

    /// Every edge's route from its source through the ports of the groups it leaves, its level's route, and the ports of
    /// the groups it enters, repeated points left out; its label moved with its level.
    mutating func joinRoutes() {
        for level in levels {
            for levelEdge in level.edges {
                let edge = edges[levelEdge.edgeIndex]
                var route: [LayeredRoutePoint] = []
                var item = edge.source
                while nodes[item].parent != level.identifier {
                    let outward = levels[levelIndex(of: nodes[item].parent)]
                    Self.append(outward.port(edge: levelEdge.edgeIndex, isOutgoing: true)?.route ?? [], to: &route, origin: outward.origin)
                    item = nodes[item].parent
                }
                Self.append(level.routes[levelEdge.edgeIndex] ?? [], to: &route, origin: level.origin)
                var inward: [Int] = []
                item = edge.target
                while nodes[item].parent != level.identifier {
                    inward.append(levelIndex(of: nodes[item].parent))
                    item = nodes[item].parent
                }
                for inner in inward.reversed() {
                    Self.append(levels[inner].port(edge: levelEdge.edgeIndex, isOutgoing: false)?.route ?? [], to: &route, origin: levels[inner].origin)
                }
                edges[levelEdge.edgeIndex].route = route
                if edge.labelWidth > 0 {
                    edges[levelEdge.edgeIndex].labelCenter.x += level.origin.x
                    edges[levelEdge.edgeIndex].labelCenter.y += level.origin.y
                }
            }
        }
    }

    private static func append(_ part: [LayeredRoutePoint], to route: inout [LayeredRoutePoint], origin: CGPoint) {
        for routePoint in part {
            let point = CGPoint(x: routePoint.point.x + origin.x, y: routePoint.point.y + origin.y)
            if let last = route.last, abs(last.point.x - point.x) < 0.01, abs(last.point.y - point.y) < 0.01 { continue }
            route.append(LayeredRoutePoint(point: point, runsHorizontally: routePoint.runsHorizontally))
        }
    }

    /// Hints each port on the side a group's flow ends at with where its edge turns outside the group, past the straight
    /// run out of the port; whether some ports are hinted out of their order along the border.
    mutating func hintPorts() -> Bool {
        var isOutOfOrder = false
        for levelIndex in levels.indices where levels[levelIndex].identifier >= 0 {
            let level = levels[levelIndex]
            let box = nodes[level.identifier]
            let isVertical = level.direction.runsVertically
            var seen: [(along: Double, hint: Double)] = []
            for (portIndex, port) in level.ports.enumerated() where port.side == level.direction.endSide {
                guard let turn = turningAcross(of: port, origin: level.origin, isVertical: isVertical) else { continue }
                let hint = turn - (isVertical ? box.x - box.width / 2 : box.y - box.height / 2)
                levels[levelIndex].ports[portIndex].hint = hint
                seen.append((isVertical ? port.borderPoint.x : port.borderPoint.y, hint))
            }
            seen.sortStably { first, second in first.along - second.along }
            for index in seen.indices.dropFirst() where seen[index - 1].hint > seen[index].hint { isOutOfOrder = true }
        }
        return isOutOfOrder
    }

    /// Where across the flow the edge through `port` is when it first leaves the line out of the port, or nil.
    private func turningAcross(of port: LayeredCompoundPort, origin: CGPoint, isVertical: Bool) -> Double? {
        let route = edges[port.edgeIndex].route
        let border = CGPoint(x: origin.x + port.borderPoint.x, y: origin.y + port.borderPoint.y)
        var at = -1
        var index = 0
        while index < route.count && (at < 0 || port.isOutgoing) {
            if abs(route[index].point.x - border.x) < 0.01 && abs(route[index].point.y - border.y) < 0.01 { at = index }
            index += 1
        }
        if at < 0 { return nil }
        func across(_ index: Int) -> Double { isVertical ? route[index].point.x : route[index].point.y }
        var next = port.isOutgoing ? at + 1 : at - 1
        while next >= 0 && next < route.count && abs(across(next) - across(at)) < LayeredCompoundConstants.inLine { next += port.isOutgoing ? 1 : -1 }
        if next < 0 || next >= route.count { return nil }
        return across(next)
    }
}
