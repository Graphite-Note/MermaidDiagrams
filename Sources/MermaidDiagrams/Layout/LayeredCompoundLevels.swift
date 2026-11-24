/**
 * File: LayeredCompoundLevels.swift
 * ---------------------------------
 * Layer: Core
 * Description: The levels of Pele's compound layout, top level and each group's inside breadth first, with their items
 *              as ranges of one list in the scratch arena.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 24/11/2026
 */

import CoreGraphics

extension LayeredCompoundLayout {
    /// The top level and each group's level, breadth first; groups that contain each other, unreachable from the top,
    /// lifted out to it. Each level's items in declaration order, a group's the smallest of what it holds.
    mutating func buildLevels() {
        let nodeCount = nodes.count
        let children = LayeredCompoundChildren(nodes: nodes, arena: arena)
        var placing = LayeredCompoundLevelPlacing(nodeCount: nodeCount, arena: arena)
        var root = LayeredCompoundLevel(identifier: -1, direction: rootDirection)
        for node in 0..<nodeCount where nodes[node].parent < 0 { placing.add(node, toLevel: 0) }
        root.items = 0..<placing.items.count
        levels.append(root)
        descend(from: 0, children: children, placing: &placing)
        for node in 0..<nodeCount where !placing.isPlaced[node] {
            // Lifted out of the group it was in: that group's level, made later, leaves it out.
            placing.isLifted[node] = true
            nodes[node].parent = -1
            placing.add(node, toLevel: 0)
            placing.isPlaced[node] = true
            depth[node] = 0
            if nodes[node].isGroup {
                let from = levels.count
                appendLevel(of: node, direction: nodes[node].direction ?? rootDirection, children: children, placing: &placing)
                descend(from: from, children: children, placing: &placing)
            }
        }
        groupItemsByLevel(placing)
        for levelIndex in stride(from: levels.count - 1, to: 0, by: -1) {
            let items = levels[levelIndex].items
            guard !items.isEmpty else { continue }
            // The first smallest as `Sequence.min()` finds it.
            var smallest = nodes[levelItems[items.lowerBound]].sequence
            for position in items.dropFirst() where nodes[levelItems[position]].sequence < smallest { smallest = nodes[levelItems[position]].sequence }
            if smallest != .infinity { nodes[levels[levelIndex].identifier].sequence = smallest }
        }
        let nodes = nodes
        for levelIndex in 0..<levels.count {
            levelItems.part(levels[levelIndex].items).sortStably(in: arena) { first, second in
                (nodes[first].sequence != nodes[second].sequence ? nodes[first].sequence - nodes[second].sequence : Double(first - second)) < 0
            }
        }
    }

    /// A level for `group`, holding its children but those lifted out of it.
    private mutating func appendLevel(of group: Int, direction: LayeredDirection, children: LayeredCompoundChildren,
                                      placing: inout LayeredCompoundLevelPlacing) {
        var level = LayeredCompoundLevel(identifier: group, direction: direction)
        let start = placing.items.count
        for child in children.of(group) where !placing.isLifted[child] { placing.add(child, toLevel: levels.count) }
        level.items = start..<placing.items.count
        levelOfGroup[group] = levels.count
        levels.append(level)
    }

    private mutating func descend(from start: Int, children: LayeredCompoundChildren, placing: inout LayeredCompoundLevelPlacing) {
        var levelIndex = start
        while levelIndex < levels.count {
            let level = levels[levelIndex]
            for position in level.items {
                let item = placing.items[position]
                placing.isPlaced[item] = true
                depth[item] = level.identifier < 0 ? 0 : depth[level.identifier] + 1
                if nodes[item].isGroup { appendLevel(of: item, direction: nodes[item].direction ?? level.direction, children: children, placing: &placing) }
            }
            levelIndex += 1
        }
    }

    /// The items in the order each level got them, level after level, each level's items a range.
    private mutating func groupItemsByLevel(_ placing: LayeredCompoundLevelPlacing) {
        let levelCount = levels.count
        let starts = arena.span(count: levelCount + 1, repeating: 0)
        for position in 0..<placing.items.count { starts[placing.levels[position] + 1] += 1 }
        for levelIndex in 0..<levelCount { starts[levelIndex + 1] += starts[levelIndex] }
        let fill = arena.copy(of: starts.part(0..<levelCount))
        levelItems = arena.uninitializedSpan(count: placing.items.count)
        for position in 0..<placing.items.count {
            let levelIndex = placing.levels[position]
            levelItems[fill[levelIndex]] = placing.items[position]
            fill[levelIndex] += 1
        }
        for levelIndex in 0..<levelCount { levels[levelIndex].items = starts[levelIndex]..<starts[levelIndex + 1] }
    }

    /// Every group border an edge crosses costs a port; past the budget, an edge is drawn between the groups that hold
    /// its ends, at the level they share. Returns the ports spent.
    mutating func budgetPorts() -> Int {
        var ports = 0
        for edgeIndex in 0..<edges.count {
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
}

/// Each node's children in the compound graph, node by node, a child listed under a parent that is a group other than
/// itself; a node whose parent is none of these is set at the top level.
struct LayeredCompoundChildren {
    let starts: ScratchSpan<Int>
    let children: ScratchSpan<Int>

    init(nodes: ScratchSpan<LayeredCompoundNode>, arena: DiagramScratchArena) {
        let nodeCount = nodes.count
        starts = arena.span(count: nodeCount + 1, repeating: 0)
        for node in 0..<nodeCount {
            let parent = nodes[node].parent
            if parent >= 0 && parent < nodeCount && parent != node && nodes[parent].isGroup {
                starts[parent + 1] += 1
            } else {
                nodes[node].parent = -1
            }
        }
        for node in 0..<nodeCount { starts[node + 1] += starts[node] }
        children = arena.uninitializedSpan(count: starts[nodeCount])
        let fill = arena.copy(of: starts.part(0..<nodeCount))
        for node in 0..<nodeCount where nodes[node].parent >= 0 {
            let parent = nodes[node].parent
            children[fill[parent]] = node
            fill[parent] += 1
        }
    }

    func of(_ node: Int) -> ScratchSpan<Int> { children.part(starts[node]..<starts[node + 1]) }
}

/// The items levels get while they are built, each with its level, and which nodes are placed or lifted out so far.
struct LayeredCompoundLevelPlacing {
    var items: ScratchList<Int>
    var levels: ScratchList<Int>
    let isPlaced: ScratchSpan<Bool>
    let isLifted: ScratchSpan<Bool>

    init(nodeCount: Int, arena: DiagramScratchArena) {
        items = arena.list(capacity: nodeCount, of: Int.self)
        levels = arena.list(capacity: nodeCount, of: Int.self)
        isPlaced = arena.span(count: nodeCount, repeating: false)
        isLifted = arena.span(count: nodeCount, repeating: false)
    }

    mutating func add(_ item: Int, toLevel level: Int) {
        items.append(item)
        levels.append(level)
    }
}
