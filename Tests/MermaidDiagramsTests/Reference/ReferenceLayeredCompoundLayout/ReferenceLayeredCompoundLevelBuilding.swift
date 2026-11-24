/**
 * File: ReferenceLayeredCompoundLevelBuilding.swift
 * -------------------------------------------------
 * Layer: Tests
 * Description: The 0.7.0 compound layout kept as the reference the layout is checked against: builds the flat layered
 *              graph of one level of Pele's compound layout, its ports and held ends included.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 24/11/2026
 */

import CoreGraphics
@testable import MermaidDiagrams

/// One level as a flat layered graph: its items, then a port vertex for each edge crossing the border on the side the
/// flow starts or ends at; `portVertex` gives each port's vertex, -1 for a port on another side, which pins its item.
struct ReferenceLayeredCompoundLevelGraph {
    var nodes: [LayeredFlatNode] = []
    var edges: [LayeredFlatEdge] = []
    var portVertex: [Int] = []
}

extension ReferenceLayeredCompoundLayout {
    /// The flat graph of `level`, its sizes in flow space when `isSized` (else every node empty, for ranking only).
    mutating func buildGraph(of levelIndex: Int, isSized: Bool) -> ReferenceLayeredCompoundLevelGraph {
        let level = levels[levelIndex]
        let isVertical = level.direction.runsVertically
        let start = level.direction.startSide
        var graph = ReferenceLayeredCompoundLevelGraph()
        for (index, item) in level.items.enumerated() {
            local[item] = index
            let node = nodes[item]
            var flatNode = isSized ? LayeredFlatNode(width: isVertical ? node.width : node.height, height: isVertical ? node.height : node.width)
                : LayeredFlatNode(width: 0, height: 0)
            flatNode.sideSpan = node.isGroup ? min(node.sideSpan, flatNode.width - 2 * node.paddingSide) : node.sideSpan
            flatNode.orderKey = isKeyed ? key[item] : .nan
            graph.nodes.append(flatNode)
        }
        for levelEdge in level.edges {
            let edge = edges[levelEdge.edgeIndex]
            var flatEdge = LayeredFlatEdge(tail: local[levelEdge.first], head: local[levelEdge.second], minimumLength: edge.minimumLength)
            if isSized {
                flatEdge.labelWidth = isVertical ? edge.labelWidth : edge.labelHeight
                flatEdge.labelHeight = isVertical ? edge.labelHeight : edge.labelWidth
                flatEdge.tailOffset = heldOffset(levelEdge.first, edge: levelEdge.edgeIndex, isOutgoing: true, isVertical: isVertical, isSized: true)
                flatEdge.headOffset = heldOffset(levelEdge.second, edge: levelEdge.edgeIndex, isOutgoing: false, isVertical: isVertical, isSized: true)
                flatEdge.isTailHeld = isHeld(levelEdge.first, edge: levelEdge.edgeIndex, isOutgoing: true)
                flatEdge.isHeadHeld = isHeld(levelEdge.second, edge: levelEdge.edgeIndex, isOutgoing: false)
            }
            graph.edges.append(flatEdge)
        }
        graph.portVertex = [Int](repeating: -1, count: level.ports.count)
        for (portIndex, port) in level.ports.enumerated() {
            if port.side == start || port.side == start.opposite {
                addPortVertex(port, index: portIndex, to: &graph, isStart: port.side == start, isVertical: isVertical, isSized: isSized, level: level)
            } else {
                graph.nodes[local[port.inner]].pin = port.side == .top || port.side == .left ? -1 : 1
            }
        }
        return graph
    }

    private mutating func addPortVertex(_ port: ReferenceLayeredCompoundPort, index: Int, to graph: inout ReferenceLayeredCompoundLevelGraph, isStart: Bool,
                                        isVertical: Bool, isSized: Bool, level: ReferenceLayeredCompoundLevel) {
        let vertex = graph.nodes.count
        var flatNode = LayeredFlatNode(width: 0, height: 0, kind: isStart ? .startPort : .endPort)
        flatNode.orderKey = isKeyed ? key[port.isOutgoing ? edges[port.edgeIndex].target : edges[port.edgeIndex].source] : .nan
        flatNode.portHint = port.hint.isNaN && isKeyed && hasFarHint ? farHint(level: level, port: port) : port.hint
        graph.nodes.append(flatNode)
        graph.portVertex[index] = vertex
        var flatEdge = port.isOutgoing ? LayeredFlatEdge(tail: local[port.inner], head: vertex) : LayeredFlatEdge(tail: vertex, head: local[port.inner])
        if port.isOutgoing {
            flatEdge.tailOffset = heldOffset(port.inner, edge: port.edgeIndex, isOutgoing: true, isVertical: isVertical, isSized: isSized)
            flatEdge.isTailHeld = isHeld(port.inner, edge: port.edgeIndex, isOutgoing: true)
        } else {
            flatEdge.headOffset = heldOffset(port.inner, edge: port.edgeIndex, isOutgoing: false, isVertical: isVertical, isSized: isSized)
            flatEdge.isHeadHeld = isHeld(port.inner, edge: port.edgeIndex, isOutgoing: false)
        }
        graph.edges.append(flatEdge)
    }

    /// Whether an end at `item` is a group's port the edge passes through, which is held where the group's inside put it.
    private func isHeld(_ item: Int, edge: Int, isOutgoing: Bool) -> Bool {
        nodes[item].isGroup && endsBelow(item, edge: edge, isOutgoing: isOutgoing)
    }

    /// How far across from its middle an end meets a group whose inside it passes into: where its port is on the border.
    private func heldOffset(_ item: Int, edge: Int, isOutgoing: Bool, isVertical: Bool, isSized: Bool) -> Double {
        guard isSized, isHeld(item, edge: edge, isOutgoing: isOutgoing),
              let port = levels[levelIndex(of: item)].port(edge: edge, isOutgoing: isOutgoing) else { return 0 }
        return isVertical ? port.borderPoint.x - nodes[item].width / 2 : port.borderPoint.y - nodes[item].height / 2
    }

    /// An outgoing port on the side a group's flow ends at, ordered by where its flat edge runs at the group's last rank,
    /// ties broken by the rank after (Pele's `farHint`).
    private func farHint(level: ReferenceLayeredCompoundLevel, port: ReferenceLayeredCompoundPort) -> Double {
        let flatEdge = flatEdgeOf[port.edgeIndex]
        if flatEdge < 0 || level.identifier < 0 || !port.isOutgoing || port.side != level.direction.endSide { return .nan }
        var inside = key[edges[port.edgeIndex].source]
        var outside: Double = 0
        for point in flatEdgePoints[flatEdge] {
            if Int(point.x) == lastFlatRank[level.identifier] { inside = point.y }
            if Int(point.x) == lastFlatRank[level.identifier] + 1 { outside = point.y }
        }
        return inside + outside * 1e-6
    }
}
