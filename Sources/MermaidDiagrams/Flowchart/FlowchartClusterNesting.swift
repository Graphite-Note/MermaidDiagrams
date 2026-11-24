/**
 * File: FlowchartClusterNesting.swift
 * -----------------------------------
 * Layer: Core
 * Description: Where each node and group of a flowchart sits among its groups, and which way each runs.
 *
 * Authors: Félix Chevalier, Bahey Shalash
 * Version: 0.3
 * Date: 24/11/2026
 */

/// Where each node and group of a flowchart sits among its groups, and which way each runs.
struct FlowchartClusterNesting {
    /// For each node, the group directly holding it, or nil.
    let nodeSubgraphs: [Int?]
    /// For each node, the group it stands for, or nil.
    let representedSubgraphs: [Int?]
    /// For each group, the group directly holding it, or nil.
    let subgraphParents: [Int?]
    let subgraphDepths: [Int]
    /// For each group, the direction it keeps of its own: the one written for it, unless an edge crosses its border,
    /// when it runs as the group around it does, as Pele's `inheritCrossedDirections` has it (after Mermaid).
    let subgraphDirections: [FlowchartDirection?]
    /// For each node, the direction of the box it is in: its group's, else the nearest group's around it that keeps
    /// one, else the diagram's.
    let nodeDirections: [FlowchartDirection]
    /// For each group, its place in Pele's order of groups: the reverse of the order their ends are written in (an inner
    /// group's end comes before its outer group's), so that an outer group comes first.
    let subgraphOrder: [Int]

    init(diagram: FlowchartDiagram) {
        let subgraphs = diagram.subgraphs
        var nodeSubgraphs = [Int?](repeating: nil, count: diagram.nodeCount)
        var representedSubgraphs = [Int?](repeating: nil, count: diagram.nodeCount)
        var subgraphParents = [Int?](repeating: nil, count: subgraphs.count)
        for (index, subgraph) in subgraphs.enumerated() {
            for node in subgraph.nodeIndices { nodeSubgraphs[node] = index }
            for child in subgraph.childSubgraphIndices { subgraphParents[child] = index }
            if let node = subgraph.representingNodeIndex { representedSubgraphs[node] = index }
        }
        let crossed = Self.crossedSubgraphs(of: diagram, nodeSubgraphs: nodeSubgraphs, representedSubgraphs: representedSubgraphs,
                                            subgraphParents: subgraphParents)
        let kept = subgraphs.indices.map { index in crossed.contains(index) ? nil : subgraphs[index].direction }
        // `FlowchartDiagram.subgraphs` lists each group before the groups inside it.
        var depths = [Int](repeating: 0, count: subgraphs.count)
        var directions = [FlowchartDirection](repeating: diagram.direction, count: subgraphs.count)
        for index in subgraphs.indices {
            let parent = subgraphParents[index]
            depths[index] = parent.map { depths[$0] + 1 } ?? 0
            directions[index] = kept[index] ?? parent.map { directions[$0] } ?? diagram.direction
        }
        self.nodeSubgraphs = nodeSubgraphs
        self.representedSubgraphs = representedSubgraphs
        self.subgraphParents = subgraphParents
        subgraphDepths = depths
        subgraphDirections = kept
        nodeDirections = nodeSubgraphs.map { subgraph in subgraph.map { directions[$0] } ?? diagram.direction }
        var order = Array(subgraphs.indices)
        for (place, subgraph) in Self.closingOrder(of: subgraphs, subgraphParents: subgraphParents).reversed().enumerated() { order[subgraph] = place }
        subgraphOrder = order
    }

    /// The groups an edge crosses the border of: those around one of its ends and not the other.
    private static func crossedSubgraphs(of diagram: FlowchartDiagram, nodeSubgraphs: [Int?], representedSubgraphs: [Int?],
                                         subgraphParents: [Int?]) -> Set<Int> {
        func around(_ node: Int) -> Set<Int> {
            var groups = Set<Int>()
            var group = representedSubgraphs[node].map { subgraph in subgraphParents[subgraph] } ?? nodeSubgraphs[node]
            while let current = group, !groups.contains(current) {
                groups.insert(current)
                group = subgraphParents[current]
            }
            return groups
        }
        var crossed = Set<Int>()
        for edgeIndex in 0..<diagram.edgeCount {
            let (source, target) = diagram.edgeEnds(at: edgeIndex)
            guard source != target else { continue }
            let sourceGroups = around(source)
            let targetGroups = around(target)
            crossed.formUnion(sourceGroups.symmetricDifference(targetGroups))
        }
        return crossed
    }

    /// The groups in the order their ends are written: each group's inner groups, in order, before it.
    private static func closingOrder(of subgraphs: [FlowchartSubgraph], subgraphParents: [Int?]) -> [Int] {
        var order: [Int] = []
        var isListed = [Bool](repeating: false, count: subgraphs.count)
        for root in subgraphs.indices where subgraphParents[root] == nil {
            var stack: [(subgraph: Int, isClosing: Bool)] = [(root, false)]
            while let (subgraph, isClosing) = stack.popLast() {
                if isClosing {
                    order.append(subgraph)
                    continue
                }
                if isListed[subgraph] { continue }
                isListed[subgraph] = true
                stack.append((subgraph, true))
                for child in subgraphs[subgraph].childSubgraphIndices.reversed() where !isListed[child] { stack.append((child, false)) }
            }
        }
        return order
    }
}
