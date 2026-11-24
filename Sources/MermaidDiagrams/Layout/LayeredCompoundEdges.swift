/**
 * File: LayeredCompoundEdges.swift
 * --------------------------------
 * Layer: Core
 * Description: Where each edge of Pele's compound layout is laid out, the ports it passes through, and the placings
 *              kept or undone by how much their routes cross.
 *
 * Authors: Bahey Shalash
 * Version: 0.3
 * Date: 24/11/2026
 */

import CoreGraphics

extension LayeredCompoundLayout {
    /// Each edge to the level where its ends meet, a port in every level it crosses the border of on the way; edges
    /// from a node to itself and between a group and what it holds kept aside. Each level's edges and ports are ranges,
    /// in the order of the edges.
    mutating func assignEdges() {
        let levelCount = levels.count
        let edgeStarts = arena.span(count: levelCount + 1, repeating: 0)
        let portStarts = arena.span(count: levelCount + 1, repeating: 0)
        var firstPath = arena.list(capacity: 8, of: Int.self)
        var secondPath = arena.list(capacity: 8, of: Int.self)
        for edgeIndex in 0..<edges.count {
            guard let (first, _) = meeting(of: edgeIndex, firstPath: &firstPath, secondPath: &secondPath) else { continue }
            edgeStarts[levelIndex(of: nodes[first].parent) + 1] += 1
            for inner in firstPath { portStarts[levelIndex(of: nodes[inner].parent) + 1] += 1 }
            for inner in secondPath { portStarts[levelIndex(of: nodes[inner].parent) + 1] += 1 }
        }
        for levelIndex in 0..<levelCount {
            edgeStarts[levelIndex + 1] += edgeStarts[levelIndex]
            portStarts[levelIndex + 1] += portStarts[levelIndex]
            levels[levelIndex].edges = edgeStarts[levelIndex]..<edgeStarts[levelIndex + 1]
            levels[levelIndex].ports = portStarts[levelIndex]..<portStarts[levelIndex + 1]
        }
        levelEdges = arena.uninitializedSpan(count: edgeStarts[levelCount])
        ports = arena.uninitializedSpan(count: portStarts[levelCount])
        firstPortOfEdgeEnd = arena.span(count: 2 * edges.count, repeating: -1)
        for edgeIndex in 0..<edges.count {
            edges[edgeIndex].routeStart = 0
            edges[edgeIndex].routeCount = 0
            if edges[edgeIndex].source == edges[edgeIndex].target {
                loops.append(edgeIndex)
                continue
            }
            guard let (first, second) = meeting(of: edgeIndex, firstPath: &firstPath, secondPath: &secondPath) else {
                strays.append(edgeIndex)
                continue
            }
            let level = levelIndex(of: nodes[first].parent)
            levelEdges[edgeStarts[level]] = LayeredCompoundLevelEdge(edgeIndex: edgeIndex, first: first, second: second)
            edgeStarts[level] += 1
            for inner in firstPath { addPort(edgeIndex, inner: inner, isOutgoing: true, filling: portStarts) }
            for inner in secondPath { addPort(edgeIndex, inner: inner, isOutgoing: false, filling: portStarts) }
        }
    }

    /// The items an edge is laid out between, in the level where its ends meet, and the items it passes through the
    /// borders of on the way from its source and to its target; nil for an edge from a node to itself or between a
    /// group and something inside it.
    private func meeting(of edgeIndex: Int, firstPath: inout ScratchList<Int>, secondPath: inout ScratchList<Int>) -> (Int, Int)? {
        firstPath.removeAll()
        secondPath.removeAll()
        if edges[edgeIndex].source == edges[edgeIndex].target { return nil }
        var first = edges[edgeIndex].source
        var second = edges[edgeIndex].target
        while depth[first] > depth[second] {
            firstPath.append(first)
            first = nodes[first].parent
        }
        while depth[second] > depth[first] {
            secondPath.append(second)
            second = nodes[second].parent
        }
        if first == second { return nil }
        while nodes[first].parent != nodes[second].parent {
            firstPath.append(first)
            secondPath.append(second)
            first = nodes[first].parent
            second = nodes[second].parent
        }
        return (first, second)
    }

    /// The port of `edgeIndex` at `inner`'s border, in the level holding `inner`, chained to the other ports of its end.
    private mutating func addPort(_ edgeIndex: Int, inner: Int, isOutgoing: Bool, filling starts: ScratchSpan<Int>) {
        let level = levelIndex(of: nodes[inner].parent)
        let port = starts[level]
        starts[level] += 1
        let endKey = edgeIndex * 2 + (isOutgoing ? 0 : 1)
        ports[port] = LayeredCompoundPort(edgeIndex: edgeIndex, inner: inner, isOutgoing: isOutgoing, level: level)
        ports[port].nextOfSameEnd = firstPortOfEdgeEnd[endKey]
        firstPortOfEdgeEnd[endKey] = port
    }

    /// Lays the levels out keyed by the flat layout where it applies, keeps an independent ordering instead when its
    /// routes cross less, refines the ports' order from the routes outside each group, and places the edges kept aside.
    /// False when a level would need more vertices than the limit.
    mutating func arrange() -> Bool {
        var isFlat = levels.count > 1 && isOrdered
        for levelIndex in 0..<levels.count where levels[levelIndex].direction != rootDirection { isFlat = false }
        if isFlat { keyByFlatLayout() }
        let style = LayeredRouteStyle(options)
        isKeyed = isFlat
        guard place() else { return false }
        var crossings = -1
        if isFlat {
            crossings = routeCrossings(style: style)
            if Double(crossings) > Double(flatCrossings) * LayeredCompoundConstants.flatSlack + LayeredCompoundConstants.flatSpare {
                let first = snapshot()
                isKeyed = false
                guard place() else { return false }
                let own = routeCrossings(style: style)
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
            let before = crossings >= 0 ? crossings : routeCrossings(style: style)
            if before > 0 {
                let first = snapshot()
                guard place() else { return false }
                if routeCrossings(style: style) >= before { restore(first) }
            }
        }
        placeEdgesKeptAside()
        return true
    }

    /// How often the routes cross, as Pele counts them (`LayeredRouteCrossings`).
    private func routeCrossings(style: LayeredRouteStyle) -> Int {
        routePoints.withUnsafeBufferPointer { buffer in
            let points = buffer.baseAddress.map { start in ScratchSpan(start: UnsafeMutablePointer(mutating: start), count: buffer.count) } ?? .empty
            return LayeredRouteCrossings.count(nodes: nodes, edges: edges, routePoints: points, style: style, arena: arena)
        }
    }

    private mutating func placeEdgesKeptAside() {
        for edgeIndex in strays {
            let source = nodes[edges[edgeIndex].source]
            let target = nodes[edges[edgeIndex].target]
            edges[edgeIndex].routeStart = routePoints.count
            edges[edgeIndex].routeCount = 2
            routePoints.append(LayeredRoutePoint(point: CGPoint(x: source.x, y: source.y), runsHorizontally: false))
            routePoints.append(LayeredRoutePoint(point: CGPoint(x: target.x, y: target.y), runsHorizontally: false))
            edges[edgeIndex].labelCenter = CGPoint(x: (source.x + target.x) / 2, y: (source.y + target.y) / 2)
        }
        for edgeIndex in loops {
            let node = nodes[edges[edgeIndex].source]
            edges[edgeIndex].labelCenter = CGPoint(x: node.x + node.width / 2 + LayeredCompoundConstants.loopLabelGap + edges[edgeIndex].labelWidth / 2, y: node.y)
        }
    }
}
