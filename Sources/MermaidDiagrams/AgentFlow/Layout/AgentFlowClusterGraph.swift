/**
 * File: AgentFlowClusterGraph.swift
 * ---------------------------------
 * Layer: Core
 * Description: An agent flow's graph as a flowchart of nested boxes to lay out, as Pele's render.ts hands it to its
 *              compound layout: flows as boxes, nodes in them, directions crossed edges take away, and the edges
 *              between a node and a flow around it held back to be drawn afterwards.
 *
 * Authors: Bahey Shalash
 * Version: 0.5
 * Date: 26/11/2026
 */

/// An agent flow's graph as a flowchart (`FlowchartDiagram`) to lay out with the flowchart's boxes
/// (`FlowchartClusterGraph`): the graph's nodes that are not open flows first, in the graph's order, then one node
/// standing for each open flow (`representingNodeIndex`), which edges to the flow meet; the flows as subgraphs, each
/// before the flows inside it. An edge between a node and a flow around it has no place in the layout (Pele's `held`
/// edges): it is left out and drawn afterwards. The flowchart's model is written straight from the graph, its records
/// made once (`flowchart(titles:title:)`), with no list of nodes, edges or subgraphs in between.
struct AgentFlowClusterGraph {
    /// The flowchart's direction.
    let direction: FlowchartDirection
    /// The flowchart's nodes and edges as its model keeps them, their identifiers' bytes, and for each subgraph what it
    /// directly holds: its node indices, then its subgraph indices, by `subgraphMembers`' starts.
    private var nodeRecords: [FlowchartNodeRecord] = []
    private var edgeRecords: [FlowchartEdgeRecord] = []
    private var identifierBytes: [UInt8] = []
    private var subgraphIdentifiers: [MermaidTextRange] = []
    private var subgraphMembers: [Int32] = []
    private var subgraphMemberStarts: [Int] = [0]
    private var subgraphChildStarts: [Int] = []
    /// For each flowchart node standing for itself, its graph node.
    private(set) var drawnGraphIndices: [Int] = []
    /// For each subgraph, its graph node.
    private(set) var subgraphGraphIndices: [Int] = []
    /// For each graph node, its flowchart node: a flow's is the node standing for it.
    private(set) var flowchartIndices: [Int] = []
    /// For each graph node, its subgraph, or nil when it is not an open flow.
    private(set) var subgraphIndices: [Int?] = []
    /// For each graph node, the open flow holding it, by graph index, or -1.
    private(set) var parents: [Int] = []
    private(set) var depths: [Int] = []
    /// For each open flow, its direction once crossed edges took it away, by graph index.
    private(set) var directions: [FlowchartDirection?] = []
    /// The graph's edges laid out, in the order of the flowchart's edges, and those held back.
    private(set) var laidOutEdgeIndices: [Int] = []
    private(set) var heldEdges: [(edgeIndex: Int, source: Int, target: Int)] = []

    init(graph: AgentFlowGraph, direction: FlowchartDirection) {
        self.direction = direction
        let nodes = graph.nodes
        // Each node and edge is read where it lies in its list, not copied out.
        var indexByIdentifier: [String: Int] = [:]
        indexByIdentifier.reserveCapacity(nodes.count)
        for index in nodes.indices where indexByIdentifier[nodes[index].identifier] == nil { indexByIdentifier[nodes[index].identifier] = index }
        parents = [Int](repeating: -1, count: nodes.count)
        directions = [FlowchartDirection?](repeating: nil, count: nodes.count)
        for index in nodes.indices {
            if let parent = nodes[index].parentIdentifier.flatMap({ parent in indexByIdentifier[parent] }), nodes[parent].isGroup { parents[index] = parent }
            if nodes[index].isGroup { directions[index] = nodes[index].directionKeyword.flatMap(FlowchartDirection.init(keyword:)) }
        }
        depths = Self.depths(parents: parents)
        // Each edge's ends, -1 for an end no node is named for.
        var ends: [(source: Int, target: Int)] = []
        ends.reserveCapacity(graph.edges.count)
        for index in graph.edges.indices {
            ends.append((indexByIdentifier[graph.edges[index].start] ?? -1, indexByIdentifier[graph.edges[index].end] ?? -1))
            if ends[index].source >= 0, ends[index].target >= 0 { inheritCrossedDirections(source: ends[index].source, target: ends[index].target) }
        }
        placeNodes(graph: graph)
        placeEdges(graph: graph, ends: ends)
    }

    /// How many nodes the flowchart has: the graph's nodes that are not open flows, and one for each open flow.
    var flowchartNodeCount: Int { nodeRecords.count }

    /// The flowchart's edges from a node to itself, by node.
    var selfLoopEdgeIndices: FlowchartSelfLoopIndex { FlowchartSelfLoopIndex(nodeCount: nodeRecords.count, edges: edgeRecords) }

    /// The flowchart, each subgraph titled by `titles` in the subgraphs' order and the diagram by `title`.
    func flowchart(titles: [DiagramLabel], title: String?) -> FlowchartDiagram {
        var parts = FlowchartModelParts()
        parts.nodes = nodeRecords
        parts.edges = edgeRecords
        if !subgraphIdentifiers.isEmpty {
            let rare = parts.rare
            rare.groupMembers = subgraphMembers
            rare.decodedLabels = titles
            for subgraph in subgraphIdentifiers.indices {
                let graphIndex = subgraphGraphIndices[subgraph]
                rare.groups.append(FlowchartGroupRecord(identifier: subgraphIdentifiers[subgraph], generatedNumber: -1,
                                                        title: .decoded(at: subgraph), direction: directions[graphIndex],
                                                        representingNodeIndex: Int32(flowchartIndices[graphIndex]), isCollapsed: false,
                                                        nodeIndices: Int32(subgraphMemberStarts[subgraph])..<Int32(subgraphChildStarts[subgraph]),
                                                        childGroupIndices: Int32(subgraphChildStarts[subgraph])..<Int32(subgraphMemberStarts[subgraph + 1])))
            }
        }
        return FlowchartDiagram(direction: direction, model: parts.takeModel(text: MermaidSourceText(bytes: identifierBytes)), title: title,
                                accessibilityTitle: nil, accessibilityDescription: nil, unappliedStatementCount: 0)
    }

    /// How many open flows each node is inside; a chain that loops is cut where it meets itself.
    private static func depths(parents: [Int]) -> [Int] {
        var depths = [Int](repeating: -1, count: parents.count)
        for start in parents.indices where depths[start] < 0 {
            var chain: [Int] = []
            var node = start
            while node >= 0, depths[node] < 0, chain.count <= parents.count {
                chain.append(node)
                depths[node] = -2
                node = parents[node]
            }
            var depth = node >= 0 && depths[node] >= 0 ? depths[node] + 1 : 0
            for link in chain.reversed() {
                depths[link] = depth
                depth += 1
            }
        }
        return depths
    }

    /// Whether the open flow `group` holds `node`, directly or through flows inside it.
    func contains(_ group: Int, _ node: Int) -> Bool {
        guard node != group, depths[node] > depths[group] else { return false }
        var ancestor = node
        for _ in 0..<(depths[node] - depths[group]) { ancestor = parents[ancestor] }
        return ancestor == group
    }

    /// As Mermaid does, a flow that an edge crosses runs as the flow around it: every flow around one end and not the
    /// other loses its direction.
    private mutating func inheritCrossedDirections(source: Int, target: Int) {
        guard source != target else { return }
        var first = parents[source]
        var second = parents[target]
        while first != second {
            if first >= 0, second < 0 || depths[first] >= depths[second] {
                directions[first] = nil
                first = parents[first]
            } else if second >= 0 {
                directions[second] = nil
                second = parents[second]
            } else {
                break
            }
        }
    }

    /// The nodes, then a node standing for each open flow, and the flows as subgraphs, outer ones first.
    private mutating func placeNodes(graph: AgentFlowGraph) {
        let nodes = graph.nodes
        flowchartIndices = Array(repeating: 0, count: nodes.count)
        subgraphIndices = Array(repeating: nil, count: nodes.count)
        nodeRecords.reserveCapacity(nodes.count)
        drawnGraphIndices.reserveCapacity(nodes.count)
        var groups: [Int] = []
        for index in nodes.indices {
            guard !nodes[index].isGroup else {
                groups.append(index)
                continue
            }
            flowchartIndices[index] = nodeRecords.count
            drawnGraphIndices.append(index)
            let shape = nodes[index].shape == "collapsedGroup" ? FlowchartNodeShape.rectangle : AgentFlowShapes.drawnShape(nodes[index].shape)
            nodeRecords.append(FlowchartNodeRecord(identifier: appendedIdentifier(nodes[index].identifier), label: .none, shape: shape))
        }
        groups.sort { first, second in depths[first] != depths[second] ? depths[first] < depths[second] : first < second }
        subgraphGraphIndices.reserveCapacity(groups.count)
        subgraphIdentifiers.reserveCapacity(groups.count)
        for group in groups {
            subgraphIndices[group] = subgraphGraphIndices.count
            subgraphGraphIndices.append(group)
            flowchartIndices[group] = nodeRecords.count
            nodeRecords.append(FlowchartNodeRecord(identifier: appendedIdentifier(nodes[group].identifier), label: .none, shape: .rectangle))
        }
        for group in groups { subgraphIdentifiers.append(appendedIdentifier(nodes[group].identifier)) }
        placeSubgraphMembers()
    }

    /// What each subgraph holds directly, in the graph's order: its nodes, then its subgraphs.
    private mutating func placeSubgraphMembers() {
        let subgraphCount = subgraphGraphIndices.count
        guard subgraphCount > 0 else { return }
        var nodeCounts = [Int](repeating: 0, count: subgraphCount)
        var childCounts = [Int](repeating: 0, count: subgraphCount)
        for (index, parent) in parents.enumerated() where parent >= 0 {
            guard let subgraph = subgraphIndices[parent] else { continue }
            if subgraphIndices[index] != nil { childCounts[subgraph] += 1 } else { nodeCounts[subgraph] += 1 }
        }
        subgraphChildStarts = []
        var nodeFill: [Int] = []
        var childFill: [Int] = []
        for subgraph in 0..<subgraphCount {
            nodeFill.append(subgraphMemberStarts[subgraph])
            subgraphChildStarts.append(subgraphMemberStarts[subgraph] + nodeCounts[subgraph])
            childFill.append(subgraphChildStarts[subgraph])
            subgraphMemberStarts.append(subgraphChildStarts[subgraph] + childCounts[subgraph])
        }
        subgraphMembers = [Int32](repeating: 0, count: subgraphMemberStarts[subgraphCount])
        for (index, parent) in parents.enumerated() where parent >= 0 {
            guard let subgraph = subgraphIndices[parent] else { continue }
            if let child = subgraphIndices[index] {
                subgraphMembers[childFill[subgraph]] = Int32(child)
                childFill[subgraph] += 1
            } else {
                subgraphMembers[nodeFill[subgraph]] = Int32(flowchartIndices[index])
                nodeFill[subgraph] += 1
            }
        }
    }

    /// `identifier`'s bytes appended to the flowchart's text, and their range.
    private mutating func appendedIdentifier(_ identifier: String) -> MermaidTextRange {
        let start = identifierBytes.count
        identifierBytes.append(contentsOf: identifier.utf8)
        return MermaidTextRange(start: start, end: identifierBytes.count)
    }

    /// Each edge between drawn ends, laid out unless it joins a node and a flow around it.
    private mutating func placeEdges(graph: AgentFlowGraph, ends: [(source: Int, target: Int)]) {
        let edges = graph.edges
        edgeRecords.reserveCapacity(edges.count)
        laidOutEdgeIndices.reserveCapacity(edges.count)
        for edgeIndex in edges.indices {
            let (source, target) = ends[edgeIndex]
            guard source >= 0, target >= 0 else { continue }
            if contains(source, target) || contains(target, source) {
                heldEdges.append((edgeIndex, source, target))
                continue
            }
            laidOutEdgeIndices.append(edgeIndex)
            edgeRecords.append(FlowchartEdgeRecord(sourceIndex: Int32(flowchartIndices[source]), targetIndex: Int32(flowchartIndices[target]),
                                                   minimumRankSpan: Int32(max(1, edges[edgeIndex].minimumLength ?? 1)),
                                                   stroke: edges[edgeIndex].thickness == "dotted" ? .dotted : .solid,
                                                   sourceArrowhead: .none, targetArrowhead: Self.arrowhead(of: edges[edgeIndex].arrowTypeEnd), label: .none))
        }
    }

    static func arrowhead(of edge: AgentFlowGraphEdge) -> FlowchartArrowhead { arrowhead(of: edge.arrowTypeEnd) }

    /// The arrowhead Pele draws for an edge's `arrowTypeEnd`.
    static func arrowhead(of arrowTypeEnd: String) -> FlowchartArrowhead {
        switch arrowTypeEnd {
        case "none": .none
        case "arrow_cross": .cross
        default: .arrow
        }
    }

    /// The direction of the level a node sits in: that of the nearest flow around it that keeps one, else the diagram's.
    func flowDirection(of node: Int) -> FlowchartDirection {
        var parent = parents[node]
        var hops = 0
        while parent >= 0, hops <= parents.count {
            if let direction = directions[parent] { return direction }
            parent = parents[parent]
            hops += 1
        }
        return direction
    }
}
