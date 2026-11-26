/**
 * File: AgentFlowClusterGraph.swift
 * ---------------------------------
 * Layer: Core
 * Description: An agent flow's graph as a flowchart of nested boxes to lay out, as Pele's render.ts hands it to its
 *              compound layout: flows as boxes, nodes in them, directions crossed edges take away, and the edges
 *              between a node and a flow around it held back to be drawn afterwards.
 *
 * Authors: Bahey Shalash
 * Version: 0.6
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
    private var subgraphIdentifiers: [MermaidTextRange] = []
    private var subgraphMembers: [Int32] = []
    private var subgraphMemberStarts: ScratchList<Int>
    private var subgraphChildStarts: ScratchList<Int>
    /// For each flowchart node standing for itself, its graph node.
    private(set) var drawnGraphIndices: ScratchList<Int>
    /// For each subgraph, its graph node.
    private(set) var subgraphGraphIndices: ScratchList<Int>
    /// What the layout keeps of each graph node, in one list (`AgentFlowClusterNode`).
    private(set) var clusterNodes: ScratchSpan<AgentFlowClusterNode>
    /// The graph's edges laid out, in the order of the flowchart's edges, and those held back.
    private(set) var laidOutEdgeIndices: ScratchList<Int>
    private(set) var heldEdges: ScratchList<AgentFlowHeldEdge>
    /// The thread's scratch arena, which holds the lists above for the layout's run.
    private let arena: DiagramScratchArena

    init(model: AgentFlowModel, direction: FlowchartDirection, arena: DiagramScratchArena) {
        self.direction = direction
        self.arena = arena
        let nodes = model.graph.nodes
        subgraphMemberStarts = arena.list(capacity: 8)
        subgraphMemberStarts.append(0)
        subgraphChildStarts = arena.list(capacity: 8)
        drawnGraphIndices = arena.list(capacity: nodes.count)
        subgraphGraphIndices = arena.list(capacity: 8)
        laidOutEdgeIndices = arena.list(capacity: model.graph.edges.count)
        heldEdges = arena.list(capacity: 4)
        // Each node is read where it lies in the records: its flow is its parent's graph node, kept when an open flow.
        clusterNodes = arena.span(count: nodes.count, repeating: AgentFlowClusterNode())
        for index in nodes.indices {
            let parent = Int(nodes[index].parent)
            if parent >= 0, nodes[parent].isGroup { clusterNodes[index].parent = parent }
            if nodes[index].isGroup, nodes[index].flow >= 0, let keyword = model.flows[Int(nodes[index].flow)].directionKeyword {
                clusterNodes[index].direction = FlowchartDirection(keyword: model.text.string(keyword))
            }
        }
        findDepths()
        let edges = model.graph.edges
        for index in edges.indices where edges[index].startNode >= 0 && edges[index].endNode >= 0 {
            inheritCrossedDirections(source: Int(edges[index].startNode), target: Int(edges[index].endNode))
        }
        placeNodes(model: model)
        placeEdges(model: model)
    }

    /// How many nodes the flowchart has: the graph's nodes that are not open flows, and one for each open flow.
    var flowchartNodeCount: Int { nodeRecords.count }

    /// The flowchart's edges from a node to itself, by node.
    var selfLoopEdgeIndices: FlowchartSelfLoopIndex { FlowchartSelfLoopIndex(nodeCount: nodeRecords.count, edges: edgeRecords) }

    /// The flowchart, each subgraph titled by `titles` in the subgraphs' order and the diagram by `title`.
    func flowchart(titles: [DiagramLabel], title: String?, text: AgentFlowTextBytes) -> FlowchartDiagram {
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
                                                        title: .decoded(at: subgraph), direction: clusterNodes[graphIndex].direction,
                                                        representingNodeIndex: Int32(clusterNodes[graphIndex].flowchartIndex), isCollapsed: false,
                                                        nodeIndices: Int32(subgraphMemberStarts[subgraph])..<Int32(subgraphChildStarts[subgraph]),
                                                        childGroupIndices: Int32(subgraphChildStarts[subgraph])..<Int32(subgraphMemberStarts[subgraph + 1])))
            }
        }
        return FlowchartDiagram(direction: direction, model: parts.takeModel(text: MermaidSourceText(bytes: text.bytes)), title: title,
                                accessibilityTitle: nil, accessibilityDescription: nil, unappliedStatementCount: 0)
    }

    /// How many open flows each node is inside; a chain that loops is cut where it meets itself.
    private mutating func findDepths() {
        var chain: ScratchList<Int> = arena.list(capacity: 8)
        for start in clusterNodes.indices where clusterNodes[start].depth < 0 {
            chain.removeAll()
            var node = start
            while node >= 0, clusterNodes[node].depth < 0, chain.count <= clusterNodes.count {
                chain.append(node)
                clusterNodes[node].depth = -2
                node = clusterNodes[node].parent
            }
            var depth = node >= 0 && clusterNodes[node].depth >= 0 ? clusterNodes[node].depth + 1 : 0
            for link in chain.reversed() {
                clusterNodes[link].depth = depth
                depth += 1
            }
        }
    }

    /// Whether the open flow `group` holds `node`, directly or through flows inside it.
    func contains(_ group: Int, _ node: Int) -> Bool {
        guard node != group, clusterNodes[node].depth > clusterNodes[group].depth else { return false }
        var ancestor = node
        for _ in 0..<(clusterNodes[node].depth - clusterNodes[group].depth) { ancestor = clusterNodes[ancestor].parent }
        return ancestor == group
    }

    /// As Mermaid does, a flow that an edge crosses runs as the flow around it: every flow around one end and not the
    /// other loses its direction.
    private mutating func inheritCrossedDirections(source: Int, target: Int) {
        guard source != target else { return }
        var first = clusterNodes[source].parent
        var second = clusterNodes[target].parent
        while first != second {
            if first >= 0, second < 0 || clusterNodes[first].depth >= clusterNodes[second].depth {
                clusterNodes[first].direction = nil
                first = clusterNodes[first].parent
            } else if second >= 0 {
                clusterNodes[second].direction = nil
                second = clusterNodes[second].parent
            } else {
                break
            }
        }
    }

    /// The nodes, then a node standing for each open flow, and the flows as subgraphs, outer ones first.
    private mutating func placeNodes(model: AgentFlowModel) {
        let nodes = model.graph.nodes
        nodeRecords.reserveCapacity(nodes.count)
        var groups: ScratchList<Int> = arena.list(capacity: 8)
        for index in nodes.indices {
            guard !nodes[index].isGroup else {
                groups.append(index)
                continue
            }
            clusterNodes[index].flowchartIndex = nodeRecords.count
            drawnGraphIndices.append(index)
            let shape = nodes[index].shape == AgentFlowShapeNames.collapsedGroup ? FlowchartNodeShape.rectangle : AgentFlowShapeNames.drawnShapes[Int(nodes[index].shape)]
            nodeRecords.append(FlowchartNodeRecord(identifier: nodes[index].identifier, label: .none, shape: shape))
        }
        let nodeFacts = clusterNodes
        var groupOrder = groups.elements.buffer
        groupOrder.sort { first, second in
            nodeFacts[first].depth != nodeFacts[second].depth ? nodeFacts[first].depth < nodeFacts[second].depth : first < second
        }
        subgraphGraphIndices.reserveCapacity(groups.count)
        subgraphMemberStarts.reserveCapacity(groups.count + 1)
        subgraphChildStarts.reserveCapacity(groups.count)
        subgraphIdentifiers.reserveCapacity(groups.count)
        for group in groups {
            clusterNodes[group].subgraphIndex = subgraphGraphIndices.count
            subgraphGraphIndices.append(group)
            clusterNodes[group].flowchartIndex = nodeRecords.count
            nodeRecords.append(FlowchartNodeRecord(identifier: nodes[group].identifier, label: .none, shape: .rectangle))
        }
        for group in groups { subgraphIdentifiers.append(nodes[group].identifier) }
        placeSubgraphMembers()
    }

    /// What each subgraph holds directly, in the graph's order: its nodes, then its subgraphs.
    private mutating func placeSubgraphMembers() {
        let subgraphCount = subgraphGraphIndices.count
        guard subgraphCount > 0 else { return }
        let nodeCounts = arena.span(count: subgraphCount, repeating: 0)
        let childCounts = arena.span(count: subgraphCount, repeating: 0)
        for index in clusterNodes.indices where clusterNodes[index].parent >= 0 {
            let parent = clusterNodes[index].parent
            guard let subgraph = clusterNodes[parent].subgraphIndex else { continue }
            if clusterNodes[index].subgraphIndex != nil { childCounts[subgraph] += 1 } else { nodeCounts[subgraph] += 1 }
        }
        subgraphChildStarts.removeAll()
        var nodeFill: ScratchList<Int> = arena.list(capacity: subgraphCount)
        var childFill: ScratchList<Int> = arena.list(capacity: subgraphCount)
        for subgraph in 0..<subgraphCount {
            nodeFill.append(subgraphMemberStarts[subgraph])
            subgraphChildStarts.append(subgraphMemberStarts[subgraph] + nodeCounts[subgraph])
            childFill.append(subgraphChildStarts[subgraph])
            subgraphMemberStarts.append(subgraphChildStarts[subgraph] + childCounts[subgraph])
        }
        subgraphMembers = [Int32](repeating: 0, count: subgraphMemberStarts[subgraphCount])
        for index in clusterNodes.indices where clusterNodes[index].parent >= 0 {
            let parent = clusterNodes[index].parent
            guard let subgraph = clusterNodes[parent].subgraphIndex else { continue }
            if let child = clusterNodes[index].subgraphIndex {
                subgraphMembers[childFill[subgraph]] = Int32(child)
                childFill[subgraph] += 1
            } else {
                subgraphMembers[nodeFill[subgraph]] = Int32(clusterNodes[index].flowchartIndex)
                nodeFill[subgraph] += 1
            }
        }
    }

    /// Each edge between drawn ends, laid out unless it joins a node and a flow around it.
    private mutating func placeEdges(model: AgentFlowModel) {
        let edges = model.graph.edges
        edgeRecords.reserveCapacity(edges.count)
        for edgeIndex in edges.indices {
            let (source, target) = (Int(edges[edgeIndex].startNode), Int(edges[edgeIndex].endNode))
            guard source >= 0, target >= 0 else { continue }
            if contains(source, target) || contains(target, source) {
                heldEdges.append(AgentFlowHeldEdge(edgeIndex: edgeIndex, source: source, target: target))
                continue
            }
            laidOutEdgeIndices.append(edgeIndex)
            let raw = model.edges[Int(edges[edgeIndex].edge)]
            edgeRecords.append(FlowchartEdgeRecord(sourceIndex: Int32(clusterNodes[source].flowchartIndex), targetIndex: Int32(clusterNodes[target].flowchartIndex),
                                                   minimumRankSpan: max(1, raw.length < 0 ? 1 : raw.length),
                                                   stroke: raw.stroke == .dotted ? .dotted : .solid, sourceArrowhead: .none,
                                                   targetArrowhead: edges[edgeIndex].arrowTypeEnd, label: .none))
        }
    }

    /// The direction of the level a node sits in: that of the nearest flow around it that keeps one, else the diagram's.
    func flowDirection(of node: Int) -> FlowchartDirection {
        var parent = clusterNodes[node].parent
        var hops = 0
        while parent >= 0, hops <= clusterNodes.count {
            if let direction = clusterNodes[parent].direction { return direction }
            parent = clusterNodes[parent].parent
            hops += 1
        }
        return direction
    }
}

/// What an agent flow's layout keeps of a graph node: the open flow holding it (-1 for none), how many open flows it is
/// inside, an open flow's direction once crossed edges took it away, its flowchart node (a flow's is the node standing
/// for it), and an open flow's subgraph.
struct AgentFlowClusterNode: BitwiseCopyable {
    var parent = -1
    var depth = -1
    /// The direction's place among `FlowchartDirection.allCases`, or -1, so that the record is plain bits.
    private var directionNumber: Int8 = -1
    var flowchartIndex = 0
    var subgraphIndex: Int?

    var direction: FlowchartDirection? {
        get { directionNumber < 0 ? nil : FlowchartDirection.allCases[Int(directionNumber)] }
        set { directionNumber = newValue.flatMap { direction in FlowchartDirection.allCases.firstIndex(of: direction) }.map(Int8.init) ?? -1 }
    }
}

/// An edge between a node and a flow around it, which the layout has no place for: its graph edge and its ends' graph
/// nodes.
struct AgentFlowHeldEdge {
    var edgeIndex: Int
    var source: Int
    var target: Int
}
