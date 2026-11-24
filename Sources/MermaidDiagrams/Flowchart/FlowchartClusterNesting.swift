/**
 * File: FlowchartClusterNesting.swift
 * -----------------------------------
 * Layer: Core
 * Description: Where each node and group of a flowchart sits among its groups, and which way each runs, read from the
 *              group records of the flowchart's model.
 *
 * Authors: Félix Chevalier, Bahey Shalash
 * Version: 0.4
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
        let groups = diagram.model.extras?.groups ?? []
        let members = diagram.model.extras?.groupMembers ?? []
        var nodeSubgraphs = [Int?](repeating: nil, count: diagram.nodeCount)
        var representedSubgraphs = [Int?](repeating: nil, count: diagram.nodeCount)
        var subgraphParents = [Int?](repeating: nil, count: groups.count)
        for (index, group) in groups.enumerated() {
            for member in group.nodeIndices { nodeSubgraphs[Int(members[Int(member)])] = index }
            for member in group.childGroupIndices { subgraphParents[Int(members[Int(member)])] = index }
            if group.representingNodeIndex >= 0 { representedSubgraphs[Int(group.representingNodeIndex)] = index }
        }
        let crossed = Self.crossedSubgraphs(of: diagram, nodeSubgraphs: nodeSubgraphs, representedSubgraphs: representedSubgraphs,
                                            subgraphParents: subgraphParents)
        // The model lists each group before the groups inside it.
        var depths = [Int](repeating: 0, count: groups.count)
        var kept = [FlowchartDirection?](repeating: nil, count: groups.count)
        var directions = [FlowchartDirection](repeating: diagram.direction, count: groups.count)
        for index in groups.indices {
            let parent = subgraphParents[index]
            kept[index] = crossed[index] ? nil : groups[index].direction
            depths[index] = parent.map { depths[$0] + 1 } ?? 0
            directions[index] = kept[index] ?? parent.map { directions[$0] } ?? diagram.direction
        }
        self.nodeSubgraphs = nodeSubgraphs
        self.representedSubgraphs = representedSubgraphs
        self.subgraphParents = subgraphParents
        subgraphDepths = depths
        subgraphDirections = kept
        nodeDirections = nodeSubgraphs.map { subgraph in subgraph.map { directions[$0] } ?? diagram.direction }
        var order = Array(groups.indices)
        for (place, subgraph) in Self.closingOrder(of: groups, members: members, subgraphParents: subgraphParents).reversed().enumerated() {
            order[subgraph] = place
        }
        subgraphOrder = order
    }

    /// For each group, whether an edge crosses its border: it is around one of the edge's ends and not the other.
    private static func crossedSubgraphs(of diagram: FlowchartDiagram, nodeSubgraphs: [Int?], representedSubgraphs: [Int?],
                                         subgraphParents: [Int?]) -> [Bool] {
        var crossed = [Bool](repeating: false, count: subgraphParents.count)
        guard !subgraphParents.isEmpty else { return crossed }
        // The edge whose ends' groups were last marked around its source, and around its target; a chain that comes
        // back to a group it passed stops there.
        var aroundSource = [Int](repeating: -1, count: subgraphParents.count)
        var aroundTarget = [Int](repeating: -1, count: subgraphParents.count)
        func firstGroup(around node: Int) -> Int? {
            representedSubgraphs[node].map { subgraph in subgraphParents[subgraph] } ?? nodeSubgraphs[node]
        }
        func mark(around node: Int, edge: Int, in marks: inout [Int]) {
            var group = firstGroup(around: node)
            while let current = group, marks[current] != edge {
                marks[current] = edge
                group = subgraphParents[current]
            }
        }
        func markCrossed(around node: Int, edge: Int, marks: [Int], others: [Int]) {
            var group = firstGroup(around: node)
            var visited = 0
            while let current = group, marks[current] == edge, visited < marks.count {
                if others[current] != edge { crossed[current] = true }
                visited += 1
                group = subgraphParents[current]
            }
        }
        for edgeIndex in 0..<diagram.edgeCount {
            let (source, target) = diagram.edgeEnds(at: edgeIndex)
            guard source != target else { continue }
            mark(around: source, edge: edgeIndex, in: &aroundSource)
            mark(around: target, edge: edgeIndex, in: &aroundTarget)
            markCrossed(around: source, edge: edgeIndex, marks: aroundSource, others: aroundTarget)
            markCrossed(around: target, edge: edgeIndex, marks: aroundTarget, others: aroundSource)
        }
        return crossed
    }

    /// The groups in the order their ends are written: each group's inner groups, in order, before it.
    private static func closingOrder(of groups: [FlowchartGroupRecord], members: [Int32], subgraphParents: [Int?]) -> [Int] {
        var order: [Int] = []
        order.reserveCapacity(groups.count)
        var isListed = [Bool](repeating: false, count: groups.count)
        var stack: [(subgraph: Int, isClosing: Bool)] = []
        for root in groups.indices where subgraphParents[root] == nil {
            stack.append((root, false))
            while let (subgraph, isClosing) = stack.popLast() {
                if isClosing {
                    order.append(subgraph)
                    continue
                }
                if isListed[subgraph] { continue }
                isListed[subgraph] = true
                stack.append((subgraph, true))
                for member in groups[subgraph].childGroupIndices.reversed() {
                    let child = Int(members[Int(member)])
                    if !isListed[child] { stack.append((child, false)) }
                }
            }
        }
        return order
    }
}
