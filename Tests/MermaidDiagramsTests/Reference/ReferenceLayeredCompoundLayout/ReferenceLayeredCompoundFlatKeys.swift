/**
 * File: ReferenceLayeredCompoundFlatKeys.swift
 * --------------------------------------------
 * Layer: Tests
 * Description: The 0.7.0 compound layout kept as the reference the layout is checked against: keys the levels of Pele's
 *              compound layout from one flat layout of every node, groups kept contiguous.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 24/11/2026
 */

@testable import MermaidDiagrams

extension ReferenceLayeredCompoundLayout {
    /// Orders every node of the graph in one flat layout that keeps each group contiguous, without boxes; each node's
    /// position there is its key, a group's the mean of its nodes', so that node and port order agree across groups.
    mutating func keyByFlatLayout() {
        let isVertical = rootDirection.runsVertically
        let (leaf, flatNodeList, groupOfNode, parentOfGroup) = flatNodes(isVertical: isVertical)
        var flatNodes = flatNodeList
        var flatEdges: [LayeredFlatEdge] = []
        flatEdgeOf = [Int](repeating: -1, count: edges.count)
        for (edgeIndex, edge) in edges.enumerated() where edge.source != edge.target && leaf[edge.source] >= 0 && leaf[edge.target] >= 0 {
            flatEdgeOf[edgeIndex] = flatEdges.count
            flatEdges.append(LayeredFlatEdge(tail: leaf[edge.source], head: leaf[edge.target], minimumLength: edge.minimumLength,
                                             labelWidth: isVertical ? edge.labelWidth : edge.labelHeight,
                                             labelHeight: isVertical ? edge.labelHeight : edge.labelWidth))
        }
        var flatOptions = options
        flatOptions.groupOfNode = groupOfNode
        flatOptions.parentOfGroup = parentOfGroup
        flatOptions.ordersOnly = true
        let result = ReferenceLayeredFlatLayout.layout(nodes: &flatNodes, edges: &flatEdges, options: flatOptions, workspace: workspace)
            ?? LayeredFlatResult(width: 0, height: 0)
        flatCrossings = min(result.crossings, result.declaredCrossings)
        flatEdgePoints = flatEdges.map(\.points)
        keyNodes(leaf: leaf, flatNodes: flatNodes)
        hasFarHint = true
    }

    /// The graph's nodes without its groups, in flow space, each node's flat index (-1 for a group), each flat node's
    /// group and each group's parent, numbered among the groups.
    private func flatNodes(isVertical: Bool) -> (leaf: [Int], nodes: [LayeredFlatNode], groupOfNode: [Int], parentOfGroup: [Int]) {
        let nodeCount = nodes.count
        var leaf = [Int](repeating: -1, count: nodeCount)
        var group = [Int](repeating: -1, count: nodeCount)
        var flatNodes: [LayeredFlatNode] = []
        var groupOfNode: [Int] = []
        var parentOfGroup: [Int] = []
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
        return (leaf, flatNodes, groupOfNode, parentOfGroup)
    }

    /// Each node's key its flat position, each group's the mean of its nodes' and its last flat rank.
    private mutating func keyNodes(leaf: [Int], flatNodes: [LayeredFlatNode]) {
        let nodeCount = nodes.count
        var sum = [Double](repeating: 0, count: nodeCount)
        var count = [Int](repeating: 0, count: nodeCount)
        lastFlatRank = [Int](repeating: -1, count: nodeCount)
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
