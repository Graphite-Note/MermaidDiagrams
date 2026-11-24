/**
 * File: AgentFlowClusterGraph.swift
 * ---------------------------------
 * Layer: Core
 * Description: An agent flow's graph as a flowchart of nested boxes to lay out, as Pele's render.ts hands it to its
 *              compound layout: flows as boxes, nodes in them, directions crossed edges take away, and the edges
 *              between a node and a flow around it held back to be drawn afterwards.
 *
 * Authors: Bahey Shalash
 * Version: 0.2
 * Date: 24/11/2026
 */

/// An agent flow's graph as a flowchart (`FlowchartDiagram`) to lay out with the flowchart's boxes
/// (`LayeredClusterLayout`): the graph's nodes that are not open flows first, in the graph's order, then one node
/// standing for each open flow (`representingNodeIndex`), which edges to the flow meet; the flows as subgraphs, each
/// before the flows inside it. An edge between a node and a flow around it has no place in the layout (Pele's `held`
/// edges): it is left out and drawn afterwards.
struct AgentFlowClusterGraph {
    var flowchart = FlowchartDiagram()
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
        var indexByIdentifier: [String: Int] = [:]
        for (index, node) in graph.nodes.enumerated() where indexByIdentifier[node.identifier] == nil { indexByIdentifier[node.identifier] = index }
        parents = graph.nodes.map { node in
            node.parentIdentifier.flatMap { parent in indexByIdentifier[parent] }.flatMap { parent in graph.nodes[parent].isGroup ? parent : nil } ?? -1
        }
        depths = Self.depths(parents: parents)
        directions = graph.nodes.map { node in node.isGroup ? node.directionKeyword.flatMap(FlowchartDirection.init(keyword:)) : nil }
        let ends = graph.edges.compactMap { edge -> (Int, Int)? in
            guard let source = indexByIdentifier[edge.start], let target = indexByIdentifier[edge.end] else { return nil }
            return (source, target)
        }
        for (source, target) in ends { inheritCrossedDirections(source: source, target: target) }
        // The flowchart is made once, from its lists, as it keeps them as one model.
        let (nodes, subgraphs) = placeNodes(graph: graph)
        let edges = placeEdges(graph: graph, indexByIdentifier: indexByIdentifier)
        flowchart = FlowchartDiagram(direction: direction, nodes: nodes, edges: edges, subgraphs: subgraphs)
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
    private mutating func placeNodes(graph: AgentFlowGraph) -> (nodes: [FlowchartNode], subgraphs: [FlowchartSubgraph]) {
        var nodes: [FlowchartNode] = []
        var subgraphs: [FlowchartSubgraph] = []
        flowchartIndices = Array(repeating: 0, count: graph.nodes.count)
        subgraphIndices = Array(repeating: nil, count: graph.nodes.count)
        for (index, node) in graph.nodes.enumerated() where !node.isGroup {
            flowchartIndices[index] = nodes.count
            drawnGraphIndices.append(index)
            let shape = node.shape == "collapsedGroup" ? FlowchartNodeShape.rectangle : AgentFlowShapes.drawnShape(node.shape)
            nodes.append(FlowchartNode(identifier: node.identifier, label: DiagramLabel(lines: []), shape: shape))
        }
        let groups = graph.nodes.indices.filter { index in graph.nodes[index].isGroup }.sorted { first, second in
            depths[first] != depths[second] ? depths[first] < depths[second] : first < second
        }
        for group in groups {
            subgraphIndices[group] = subgraphs.count
            subgraphGraphIndices.append(group)
            flowchartIndices[group] = nodes.count
            nodes.append(FlowchartNode(identifier: graph.nodes[group].identifier, label: DiagramLabel(lines: [])))
            subgraphs.append(FlowchartSubgraph(identifier: graph.nodes[group].identifier, title: DiagramLabel(lines: []),
                                               direction: directions[group], representingNodeIndex: nodes.count - 1))
        }
        for (index, parent) in parents.enumerated() where parent >= 0 {
            guard let subgraph = subgraphIndices[parent] else { continue }
            if let child = subgraphIndices[index] {
                subgraphs[subgraph].childSubgraphIndices.append(child)
            } else {
                subgraphs[subgraph].nodeIndices.append(flowchartIndices[index])
            }
        }
        return (nodes, subgraphs)
    }

    /// Each edge between drawn ends, laid out unless it joins a node and a flow around it.
    private mutating func placeEdges(graph: AgentFlowGraph, indexByIdentifier: [String: Int]) -> [FlowchartEdge] {
        var edges: [FlowchartEdge] = []
        for (edgeIndex, edge) in graph.edges.enumerated() {
            guard let source = indexByIdentifier[edge.start], let target = indexByIdentifier[edge.end] else { continue }
            if contains(source, target) || contains(target, source) {
                heldEdges.append((edgeIndex, source, target))
                continue
            }
            laidOutEdgeIndices.append(edgeIndex)
            edges.append(FlowchartEdge(sourceIndex: flowchartIndices[source], targetIndex: flowchartIndices[target],
                                                 stroke: edge.thickness == "dotted" ? .dotted : .solid, targetArrowhead: Self.arrowhead(of: edge),
                                                 minimumRankSpan: max(1, edge.minimumLength ?? 1)))
        }
        return edges
    }

    static func arrowhead(of edge: AgentFlowGraphEdge) -> FlowchartArrowhead {
        switch edge.arrowTypeEnd {
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
        return flowchart.direction
    }
}
