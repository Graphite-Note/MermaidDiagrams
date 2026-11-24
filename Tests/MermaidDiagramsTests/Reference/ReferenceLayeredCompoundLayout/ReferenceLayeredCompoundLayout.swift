/**
 * File: ReferenceLayeredCompoundLayout.swift
 * ------------------------------------------
 * Layer: Tests
 * Description: The 0.7.0 compound layout kept as the reference the layout is checked against: pele's compound layout of
 *              a graph in nested groups, ported step for step from layout/compound.ts.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 24/11/2026
 */

import CoreGraphics
@testable import MermaidDiagrams

/// Pele's `compoundLayout` (layout/compound.ts): each group is laid out on its own, in its own direction, by the flat
/// layered layout, then placed in its parent as one box; an edge that crosses a group's border passes through a port on
/// the side facing its other end. A flat layout of every node first keys the orders of all groups alike, and the port
/// order is refined from the routes outside each group, each kept only when its routes cross less.
struct ReferenceLayeredCompoundLayout {
    var nodes: [LayeredCompoundNode]
    var edges: [LayeredCompoundEdge]
    let options: LayeredFlatOptions
    let rootDirection: LayeredDirection
    let maximumVertexCount: Int
    /// The levels in breadth-first order, the top level first, and the level of each group by node (-1 for none).
    var levels: [ReferenceLayeredCompoundLevel] = []
    var levelOfGroup: [Int]
    var depth: [Int]
    /// Each item's index in the level being built.
    var local: [Int]
    var key: [Double]
    var isKeyed = false
    var isOrdered = false
    var flatCrossings = 0
    /// From the flat layout: each edge's flat edge (-1 for none), the flat edges' (rank, position) points, and the
    /// last flat rank each group occupies.
    var flatEdgeOf: [Int] = []
    var flatEdgePoints: [[CGPoint]] = []
    var lastFlatRank: [Int] = []
    var hasFarHint = false
    var total = (width: 0.0, height: 0.0)
    var loops: [Int] = []
    var strays: [Int] = []
    /// The working lists of every flat layout this layout runs.
    let workspace = ReferenceLayeredFlatWorkspace()

    init(nodes: [LayeredCompoundNode], edges: [LayeredCompoundEdge], rootDirection: LayeredDirection, options: LayeredFlatOptions,
         maximumVertexCount: Int) {
        self.nodes = nodes
        self.edges = edges
        self.options = options
        self.rootDirection = rootDirection
        self.maximumVertexCount = maximumVertexCount
        levelOfGroup = [Int](repeating: -1, count: nodes.count)
        depth = [Int](repeating: 0, count: nodes.count)
        local = [Int](repeating: 0, count: nodes.count)
        key = [Double](repeating: .nan, count: nodes.count)
    }

    /// Lays the graph out in place and returns its width and height, or nil when a level would need more vertices
    /// than the limit.
    static func layout(nodes: inout [LayeredCompoundNode], edges: inout [LayeredCompoundEdge], rootDirection: LayeredDirection,
                       options: LayeredFlatOptions, maximumVertexCount: Int = .max) -> (width: Double, height: Double)? {
        var layout = ReferenceLayeredCompoundLayout(nodes: nodes, edges: edges, rootDirection: rootDirection, options: options,
                                           maximumVertexCount: maximumVertexCount)
        layout.buildLevels()
        let ports = layout.budgetPorts()
        layout.assignEdges()
        layout.isOrdered = ports > 1 && ports <= LayeredCompoundConstants.maximumOrderedPorts && edges.count <= LayeredCompoundConstants.maximumOrderedEdges
        guard layout.arrange() else { return nil }
        nodes = layout.nodes
        edges = layout.edges
        return layout.total
    }

    /// The top level and each group's level, breadth first; groups that contain each other, unreachable from the top,
    /// lifted out to it. Each level's items in declaration order, a group's the smallest of what it holds.
    private mutating func buildLevels() {
        let nodeCount = nodes.count
        var children = [[Int]](repeating: [], count: nodeCount)
        var root = ReferenceLayeredCompoundLevel(identifier: -1, direction: rootDirection)
        for node in 0..<nodeCount {
            let parent = nodes[node].parent
            if parent >= 0 && parent < nodeCount && parent != node && nodes[parent].isGroup {
                children[parent].append(node)
            } else {
                nodes[node].parent = -1
                root.items.append(node)
            }
        }
        levels = [root]
        var isPlaced = [Bool](repeating: false, count: nodeCount)
        descend(from: 0, children: children, isPlaced: &isPlaced)
        for node in 0..<nodeCount where !isPlaced[node] {
            let former = nodes[node].parent
            children[former].removeAll { child in child == node }
            nodes[node].parent = -1
            levels[0].items.append(node)
            isPlaced[node] = true
            depth[node] = 0
            if nodes[node].isGroup {
                let from = levels.count
                appendLevel(of: node, direction: nodes[node].direction ?? rootDirection, items: children[node])
                descend(from: from, children: children, isPlaced: &isPlaced)
            }
        }
        for levelIndex in stride(from: levels.count - 1, to: 0, by: -1) {
            let smallest = levels[levelIndex].items.map { item in nodes[item].sequence }.min() ?? .infinity
            if smallest != .infinity { nodes[levels[levelIndex].identifier].sequence = smallest }
        }
        for levelIndex in levels.indices {
            levels[levelIndex].items.sortStably { first, second in
                nodes[first].sequence != nodes[second].sequence ? nodes[first].sequence - nodes[second].sequence : Double(first - second)
            }
        }
    }

    private mutating func appendLevel(of group: Int, direction: LayeredDirection, items: [Int]) {
        var level = ReferenceLayeredCompoundLevel(identifier: group, direction: direction)
        level.items = items
        levelOfGroup[group] = levels.count
        levels.append(level)
    }

    private mutating func descend(from start: Int, children: [[Int]], isPlaced: inout [Bool]) {
        var levelIndex = start
        while levelIndex < levels.count {
            let level = levels[levelIndex]
            for item in level.items {
                isPlaced[item] = true
                depth[item] = level.identifier < 0 ? 0 : depth[level.identifier] + 1
                if nodes[item].isGroup { appendLevel(of: item, direction: nodes[item].direction ?? level.direction, items: children[item]) }
            }
            levelIndex += 1
        }
    }

    /// The level that holds what sits directly in `group` (-1 for the top level).
    func levelIndex(of group: Int) -> Int { group < 0 ? 0 : levelOfGroup[group] }

    /// Whether the end of `edge` at `item` lies inside it rather than at it.
    func endsBelow(_ item: Int, edge: Int, isOutgoing: Bool) -> Bool {
        (isOutgoing ? edges[edge].source : edges[edge].target) != item
    }
}
