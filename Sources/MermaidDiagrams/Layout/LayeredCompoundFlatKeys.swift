/**
 * File: LayeredCompoundFlatKeys.swift
 * -----------------------------------
 * Layer: Core
 * Description: Keys the levels of Pele's compound layout from one flat layout of every node, groups kept contiguous.
 *
 * Authors: Bahey Shalash
 * Version: 0.4
 * Date: 24/11/2026
 */

import CoreGraphics

extension LayeredCompoundLayout {
    /// Orders every node of the graph in one flat layout that keeps each group contiguous, without boxes; each node's
    /// position there is its key, a group's the mean of its nodes', so that node and port order agree across groups.
    /// The flat graph and its points are written to the arena; its points stay there, as ranges, for the far hints.
    mutating func keyByFlatLayout() {
        let isVertical = rootDirection.runsVertically
        let flat = flatNodes(isVertical: isVertical)
        flatEdgeOf = arena.span(count: edges.count, repeating: -1)
        var flatEdges = arena.list(capacity: edges.count, of: LayeredSpanEdge.self)
        for edgeIndex in 0..<edges.count {
            let edge = edges[edgeIndex]
            guard edge.source != edge.target && flat.leaf[edge.source] >= 0 && flat.leaf[edge.target] >= 0 else { continue }
            flatEdgeOf[edgeIndex] = flatEdges.count
            flatEdges.append(LayeredSpanEdge(LayeredFlatEdge(tail: flat.leaf[edge.source], head: flat.leaf[edge.target], minimumLength: edge.minimumLength,
                                                             labelWidth: isVertical ? edge.labelWidth : edge.labelHeight,
                                                             labelHeight: isVertical ? edge.labelHeight : edge.labelWidth)))
        }
        var flatOptions = options
        flatOptions.groupOfNode = flat.groupOfNode
        flatOptions.parentOfGroup = flat.parentOfGroup
        flatOptions.ordersOnly = true
        var points = arena.list(capacity: 4 * flatEdges.count, of: CGPoint.self)
        let result = LayeredFlatLayout.layout(nodes: flat.nodes, edges: flatEdges.elements, points: &points, options: flatOptions,
                                              maximumVertexCount: .max, arena: arena) ?? LayeredFlatResult(width: 0, height: 0)
        flatCrossings = min(result.crossings, result.declaredCrossings)
        flatEdgePoints = points.elements
        flatEdgePointRanges = arena.uninitializedSpan(count: flatEdges.count)
        for flatEdge in 0..<flatEdges.count {
            let laidOut = flatEdges[flatEdge]
            flatEdgePointRanges[flatEdge] = LayeredIndexRange(laidOut.pointStart >= 0 ? laidOut.pointStart..<(laidOut.pointStart + laidOut.pointCount) : 0..<0)
        }
        keyNodes(leaf: flat.leaf, flatNodes: flat.nodes)
        hasFarHint = true
    }

    /// The graph's nodes without its groups, in flow space, each node's flat index (-1 for a group), each flat node's
    /// group and each group's parent, numbered among the groups.
    private func flatNodes(isVertical: Bool) -> (leaf: ScratchSpan<Int>, nodes: ScratchSpan<LayeredFlatNode>, groupOfNode: [Int], parentOfGroup: [Int]) {
        let nodeCount = nodes.count
        let leaf = arena.span(count: nodeCount, repeating: -1)
        let group = arena.span(count: nodeCount, repeating: -1)
        var flatNodes = arena.list(capacity: nodeCount, of: LayeredFlatNode.self)
        var groupOfNode: [Int] = []
        var parentOfGroup: [Int] = []
        groupOfNode.reserveCapacity(nodeCount)
        for node in 0..<nodeCount where nodes[node].isGroup {
            group[node] = parentOfGroup.count
            parentOfGroup.append(-1)
        }
        for node in 0..<nodeCount {
            let parent = nodes[node].parent
            if nodes[node].isGroup {
                parentOfGroup[group[node]] = parent >= 0 ? group[parent] : -1
            } else {
                leaf[node] = flatNodes.count
                flatNodes.append(LayeredFlatNode(width: isVertical ? nodes[node].width : nodes[node].height,
                                                 height: isVertical ? nodes[node].height : nodes[node].width))
                groupOfNode.append(parent >= 0 ? group[parent] : -1)
            }
        }
        return (leaf, flatNodes.elements, groupOfNode, parentOfGroup)
    }

    /// Each node's key its flat position, each group's the mean of its nodes' and its last flat rank.
    private mutating func keyNodes(leaf: ScratchSpan<Int>, flatNodes: ScratchSpan<LayeredFlatNode>) {
        let nodeCount = nodes.count
        let sum = arena.span(count: nodeCount, repeating: 0.0)
        let count = arena.span(count: nodeCount, repeating: 0)
        lastFlatRank = arena.span(count: nodeCount, repeating: -1)
        for node in 0..<nodeCount where leaf[node] >= 0 {
            key[node] = flatNodes[leaf[node]].x
            var parent = nodes[node].parent
            while parent >= 0 {
                sum[parent] += key[node]
                count[parent] += 1
                lastFlatRank[parent] = max(lastFlatRank[parent], flatNodes[leaf[node]].rank)
                parent = nodes[parent].parent
            }
        }
        for node in 0..<nodeCount where count[node] > 0 { key[node] = sum[node] / Double(count[node]) }
    }
}
