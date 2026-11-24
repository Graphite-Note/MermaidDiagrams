/**
 * File: FlowchartModelViews.swift
 * -------------------------------
 * Layer: Core
 * Description: The public values of a flowchart made from its flat model when they are asked for: a node, an edge
 *              or a group by its index, each made with its identifier and its labels decoded.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 24/11/2026
 */

extension FlowchartModel {
    /// The node at `index`, made.
    func node(at index: Int) -> FlowchartNode {
        let record = nodes[index]
        var node = FlowchartNode(identifier: string(record.identifier), label: label(record.label) ?? DiagramLabel(lines: []), shape: record.shape,
                                 style: nodeStyle(at: index))
        if record.assetIndex >= 0, let extras { node.assetAttributes = extras.assetAttributes[Int(record.assetIndex)] }
        return node
    }

    /// The edge at `index`, made.
    func edge(at index: Int) -> FlowchartEdge {
        let record = edges[index]
        return FlowchartEdge(sourceIndex: Int(record.sourceIndex), targetIndex: Int(record.targetIndex), stroke: record.stroke,
                             sourceArrowhead: record.sourceArrowhead, targetArrowhead: record.targetArrowhead,
                             minimumRankSpan: Int(record.minimumRankSpan), label: label(record.label), style: edgeStyle(at: index))
    }

    /// The group at `index`, made.
    func subgraph(at index: Int) -> FlowchartSubgraph {
        guard let extras else { preconditionFailure("A flowchart without groups has no group \(index)") }
        let group = extras.groups[index]
        let members = extras.groupMembers
        return FlowchartSubgraph(identifier: groupIdentifier(group), title: label(group.title) ?? DiagramLabel(lines: []),
                                 nodeIndices: members[Int(group.nodeIndices.lowerBound)..<Int(group.nodeIndices.upperBound)].map(Int.init),
                                 childSubgraphIndices: members[Int(group.childGroupIndices.lowerBound)..<Int(group.childGroupIndices.upperBound)].map(Int.init),
                                 direction: group.direction, representingNodeIndex: group.representingNodeIndex >= 0 ? Int(group.representingNodeIndex) : nil,
                                 isCollapsed: group.isCollapsed)
    }

    var groupCount: Int { extras?.groups.count ?? 0 }

    /// The direction of the group at `index`, or nil when it runs as the group around it does.
    func subgraphDirection(at index: Int) -> FlowchartDirection? { extras?.groups[index].direction }

    /// What the statements that style the diagram set for the node at `index`, or nil.
    func nodeStyle(at index: Int) -> DiagramElementStyle? {
        guard let extras, !extras.nodeStyles.isEmpty else { return nil }
        return extras.nodeStyles[index]
    }

    /// What `linkStyle` sets for the edge at `index`, or nil.
    func edgeStyle(at index: Int) -> DiagramElementStyle? {
        guard let extras, !extras.edgeStyles.isEmpty else { return nil }
        return extras.edgeStyles[index]
    }

    /// Every node, edge and group, made.
    var materializedNodes: [FlowchartNode] { nodes.indices.map(node(at:)) }
    var materializedEdges: [FlowchartEdge] { edges.indices.map(edge(at:)) }
    var materializedSubgraphs: [FlowchartSubgraph] { (0..<groupCount).map(subgraph(at:)) }
}
