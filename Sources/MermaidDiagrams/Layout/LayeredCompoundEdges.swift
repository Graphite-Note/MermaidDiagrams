/**
 * File: LayeredCompoundEdges.swift
 * --------------------------------
 * Layer: Core
 * Description: Puts each edge of Pele's compound layout in the level where its ends meet, with ports on the way.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 23/11/2026
 */

import CoreGraphics

extension LayeredCompoundLayout {
    /// Every group border an edge crosses costs a port; past the budget, an edge is drawn between the groups that hold
    /// its ends, at the level they share. Returns the ports spent.
    mutating func budgetPorts() -> Int {
        var ports = 0
        for edgeIndex in edges.indices {
            var first = edges[edgeIndex].source
            var second = edges[edgeIndex].target
            var crossed = 0
            while depth[first] > depth[second] {
                first = nodes[first].parent
                crossed += 1
            }
            while depth[second] > depth[first] {
                second = nodes[second].parent
                crossed += 1
            }
            while first != second && nodes[first].parent != nodes[second].parent {
                first = nodes[first].parent
                second = nodes[second].parent
                crossed += 2
            }
            if first == second { continue }
            if ports + crossed > LayeredCompoundConstants.maximumPorts {
                edges[edgeIndex].source = first
                edges[edgeIndex].target = second
            } else {
                ports += crossed
            }
        }
        return ports
    }

    /// Each edge to the level where its ends meet, a port in every level it crosses the border of on the way; edges
    /// from a node to itself and between a group and what it holds kept aside.
    mutating func assignEdges() {
        for edgeIndex in edges.indices {
            edges[edgeIndex].route = []
            if edges[edgeIndex].source == edges[edgeIndex].target {
                loops.append(edgeIndex)
                continue
            }
            var first = edges[edgeIndex].source
            var second = edges[edgeIndex].target
            var firstPath: [Int] = []
            var secondPath: [Int] = []
            while depth[first] > depth[second] {
                firstPath.append(first)
                first = nodes[first].parent
            }
            while depth[second] > depth[first] {
                secondPath.append(second)
                second = nodes[second].parent
            }
            if first == second {
                strays.append(edgeIndex)
                continue
            }
            while nodes[first].parent != nodes[second].parent {
                firstPath.append(first)
                secondPath.append(second)
                first = nodes[first].parent
                second = nodes[second].parent
            }
            levels[levelIndex(of: nodes[first].parent)].edges.append(LayeredCompoundLevelEdge(edgeIndex: edgeIndex, first: first, second: second))
            for (path, isOutgoing) in [(firstPath, true), (secondPath, false)] {
                for inner in path {
                    let level = levelIndex(of: nodes[inner].parent)
                    levels[level].portIndex[edgeIndex * 2 + (isOutgoing ? 0 : 1)] = levels[level].ports.count
                    levels[level].ports.append(LayeredCompoundPort(edgeIndex: edgeIndex, inner: inner, isOutgoing: isOutgoing))
                }
            }
        }
    }

    /// Lays the levels out keyed by the flat layout where it applies, keeps an independent ordering instead when its
    /// routes cross less, refines the ports' order from the routes outside each group, and places the edges kept aside.
    /// False when a level would need more vertices than the limit.
    mutating func arrange() -> Bool {
        let isFlat = levels.count > 1 && isOrdered && levels.allSatisfy { level in level.direction == rootDirection }
        if isFlat { keyByFlatLayout() }
        let style = LayeredRouteStyle(options)
        isKeyed = isFlat
        guard place() else { return false }
        var crossings = -1
        if isFlat {
            crossings = LayeredRouteCrossings.count(nodes: nodes, edges: edges, style: style)
            if Double(crossings) > Double(flatCrossings) * LayeredCompoundConstants.flatSlack + LayeredCompoundConstants.flatSpare {
                let first = snapshot()
                isKeyed = false
                guard place() else { return false }
                let own = LayeredRouteCrossings.count(nodes: nodes, edges: edges, style: style)
                if own >= crossings {
                    isKeyed = true
                    restore(first)
                } else {
                    crossings = own
                }
            }
        }
        // Refine port order from routes outside each group, unless independent ordering won.
        if isKeyed == isFlat && isOrdered && hintPorts() {
            let before = crossings >= 0 ? crossings : LayeredRouteCrossings.count(nodes: nodes, edges: edges, style: style)
            if before > 0 {
                let first = snapshot()
                guard place() else { return false }
                if LayeredRouteCrossings.count(nodes: nodes, edges: edges, style: style) >= before { restore(first) }
            }
        }
        placeEdgesKeptAside()
        return true
    }

    private mutating func placeEdgesKeptAside() {
        for edgeIndex in strays {
            let source = nodes[edges[edgeIndex].source]
            let target = nodes[edges[edgeIndex].target]
            edges[edgeIndex].route = [LayeredRoutePoint(point: CGPoint(x: source.x, y: source.y), runsHorizontally: false),
                                      LayeredRoutePoint(point: CGPoint(x: target.x, y: target.y), runsHorizontally: false)]
            edges[edgeIndex].labelCenter = CGPoint(x: (source.x + target.x) / 2, y: (source.y + target.y) / 2)
        }
        for edgeIndex in loops {
            let node = nodes[edges[edgeIndex].source]
            edges[edgeIndex].labelCenter = CGPoint(x: node.x + node.width / 2 + LayeredCompoundConstants.loopLabelGap + edges[edgeIndex].labelWidth / 2, y: node.y)
        }
    }
}
