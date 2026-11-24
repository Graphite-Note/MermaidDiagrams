/**
 * File: LayeredCompoundPlacing.swift
 * ----------------------------------
 * Layer: Core
 * Description: One placing of Pele's compound layout: port sides, every level laid out inside out, routes joined.
 *
 * Authors: Bahey Shalash
 * Version: 0.2
 * Date: 23/11/2026
 */

import CoreGraphics

extension LayeredCompoundLayout {
    /// Pele's `place`: the sides of the groups that edges cross from the ranks of their parents, the levels laid out
    /// children first so that their sizes are known, each level moved to its box, and every edge's route joined from
    /// the pieces in the levels it passes. False when a level would need more vertices than the limit.
    mutating func place() -> Bool {
        assignPortSides()
        var vertexBudget = maximumVertexCount
        for levelIndex in levels.indices.reversed() {
            guard layOut(levelIndex, vertexBudget: &vertexBudget) else { return false }
        }
        for levelIndex in levels.indices {
            let origin = levels[levelIndex].origin
            for item in levels[levelIndex].items {
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
        for levelIndex in levels.indices {
            for port in levels[levelIndex].ports where nodes[port.inner].isGroup && endsBelow(port.inner, edge: port.edgeIndex, isOutgoing: port.isOutgoing) {
                let inner = levelOfGroup[port.inner]
                if let index = levels[inner].portIndex[port.edgeIndex * 2 + (port.isOutgoing ? 0 : 1)] { levels[inner].ports[index].side = port.side }
            }
            let level = levels[levelIndex]
            let isNeeded = level.edges.contains { levelEdge in
                (nodes[levelEdge.first].isGroup && edges[levelEdge.edgeIndex].source != levelEdge.first)
                    || (nodes[levelEdge.second].isGroup && edges[levelEdge.edgeIndex].target != levelEdge.second)
            }
            if !isNeeded { continue }
            var graph = buildGraph(of: levelIndex, isSized: false)
            #if DEBUG
            LayeredLayoutRecording.current?.rankings.append((graph.nodes, graph.edges))
            #endif
            LayeredFlatRanking.orient(nodes: graph.nodes, edges: &graph.edges, workspace: workspace)
            LayeredFlatRanking.rank(nodes: &graph.nodes, edges: graph.edges, step: 1, workspace: workspace)
            let start = level.direction.startSide
            for (index, levelEdge) in level.edges.enumerated() {
                let isFirstAbove = !graph.edges[index].isReversed
                if nodes[levelEdge.first].isGroup && edges[levelEdge.edgeIndex].source != levelEdge.first {
                    setSide(of: levelEdge.first, key: levelEdge.edgeIndex * 2, to: isFirstAbove ? start.opposite : start)
                }
                if nodes[levelEdge.second].isGroup && edges[levelEdge.edgeIndex].target != levelEdge.second {
                    setSide(of: levelEdge.second, key: levelEdge.edgeIndex * 2 + 1, to: isFirstAbove ? start : start.opposite)
                }
            }
        }
    }

    private mutating func setSide(of group: Int, key: Int, to side: DiagramSide) {
        let level = levelOfGroup[group]
        if let index = levels[level].portIndex[key] { levels[level].ports[index].side = side }
    }

    /// Lays one level out as a flat graph and turns it onto the page inside its box.
    private mutating func layOut(_ levelIndex: Int, vertexBudget: inout Int) -> Bool {
        var built = buildGraph(of: levelIndex, isSized: true)
        guard let size = LayeredFlatLayout.layout(nodes: &built.nodes, edges: &built.edges, options: options, maximumVertexCount: vertexBudget,
                                                  workspace: workspace) else {
            return false
        }
        vertexBudget -= built.nodes.count
        let level = levels[levelIndex]
        let group = level.identifier >= 0 ? nodes[level.identifier] : nil
        let box = LayeredCompoundBox(direction: level.direction, size: size, group: group)
        for (index, item) in level.items.enumerated() {
            let point = box.pagePoint(CGPoint(x: built.nodes[index].x, y: built.nodes[index].y))
            nodes[item].x = point.x
            nodes[item].y = point.y
        }
        for (index, levelEdge) in level.edges.enumerated() {
            let flatEdge = built.edges[index]
            levels[levelIndex].routes[levelEdge.edgeIndex] = box.route(flatEdge.points)
            if edges[levelEdge.edgeIndex].labelWidth > 0 { edges[levelEdge.edgeIndex].labelCenter = box.pagePoint(flatEdge.labelCenter) }
        }
        var portEdge = level.edges.count
        for portIndex in level.ports.indices {
            if built.portVertex[portIndex] >= 0 {
                placeBorderPort(portIndex, of: levelIndex, route: box.route(built.edges[portEdge].points), box: box)
                portEdge += 1
            } else {
                placeSidePort(portIndex, of: levelIndex, box: box)
            }
        }
        if let identifier = group.map({ _ in level.identifier }) {
            nodes[identifier].width = box.width
            nodes[identifier].height = box.height
        } else {
            total = (box.width, box.height)
        }
        return true
    }
}
