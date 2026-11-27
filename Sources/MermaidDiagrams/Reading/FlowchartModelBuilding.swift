/**
 * File: FlowchartModelBuilding.swift
 * ----------------------------------
 * Layer: Core
 * Description: A flowchart's flat model made from made nodes, edges and groups (an agent flow's graph, a flowchart
 *              whose collapsed groups are folded), and the same model with its groups' directions changed.
 *
 * Authors: Bahey Shalash
 * Version: 0.2
 * Date: 26/11/2026
 */

extension FlowchartModel {
    /// The model of `nodes`, `edges` and `subgraphs`: their identifiers become the text the model indexes, their labels
    /// are kept decoded.
    init(nodes: [FlowchartNode], edges: [FlowchartEdge], subgraphs: [FlowchartSubgraph]) {
        var bytes: [UInt8] = []
        var parts = FlowchartModelParts()
        func appended(_ text: String) -> MermaidTextRange {
            let start = bytes.count
            bytes.append(contentsOf: text.utf8)
            return MermaidTextRange(start: start, end: bytes.count)
        }
        func reference(_ label: DiagramLabel?) -> FlowchartLabelReference {
            guard let label else { return .none }
            parts.rare.decodedLabels.append(label)
            return .decoded(at: parts.rare.decodedLabels.count - 1)
        }
        parts.nodes.reserveCapacity(nodes.count)
        for node in nodes {
            var record = FlowchartNodeRecord(identifier: appended(node.identifier), label: reference(node.label), shape: node.shape)
            if node.assetAttributes != FlowchartNodeAssetAttributes() {
                record.assetIndex = Int32(parts.rare.assetAttributes.count)
                parts.rare.assetAttributes.append(node.assetAttributes)
            }
            parts.nodes.append(record)
        }
        if nodes.contains(where: { node in node.style != nil }) { parts.rare.nodeStyles = nodes.map(\.style) }
        parts.edges = edges.map { edge in
            FlowchartEdgeRecord(sourceIndex: Int32(edge.sourceIndex), targetIndex: Int32(edge.targetIndex), minimumRankSpan: Int32(edge.minimumRankSpan),
                                stroke: edge.stroke, sourceArrowhead: edge.sourceArrowhead, targetArrowhead: edge.targetArrowhead, label: reference(edge.label))
        }
        if edges.contains(where: { edge in edge.style != nil }) { parts.rare.edgeStyles = edges.map(\.style) }
        for subgraph in subgraphs {
            let nodesStart = Int32(parts.rare.groupMembers.count)
            parts.rare.groupMembers.append(contentsOf: subgraph.nodeIndices.map(Int32.init))
            let childrenStart = Int32(parts.rare.groupMembers.count)
            parts.rare.groupMembers.append(contentsOf: subgraph.childSubgraphIndices.map(Int32.init))
            parts.rare.groups.append(FlowchartGroupRecord(identifier: appended(subgraph.identifier), generatedNumber: -1, title: reference(subgraph.title),
                                                     direction: subgraph.direction, representingNodeIndex: Int32(subgraph.representingNodeIndex ?? -1),
                                                     isCollapsed: subgraph.isCollapsed, nodeIndices: nodesStart..<childrenStart,
                                                     childGroupIndices: childrenStart..<Int32(parts.rare.groupMembers.count)))
        }
        self = parts.takeModel(text: MermaidSourceText(bytes: bytes))
    }

    /// The model with each group's direction changed by `turn`.
    func turningGroupDirections(_ turn: (FlowchartDirection?) -> FlowchartDirection?) -> FlowchartModel {
        guard let extras, !extras.groups.isEmpty else { return self }
        var groups = extras.groups
        for index in groups.indices { groups[index].direction = turn(groups[index].direction) }
        return withGroups(groups, decodedLabels: extras.decodedLabels)
    }

    /// The model with the groups' titles `titles`, in the groups' order.
    func retitlingGroups(_ titles: [DiagramLabel]) -> FlowchartModel {
        guard let extras, !extras.groups.isEmpty else { return self }
        var groups = extras.groups
        var decodedLabels = extras.decodedLabels
        for (index, title) in zip(groups.indices, titles) {
            groups[index].title = .decoded(at: decodedLabels.count)
            decodedLabels.append(title)
        }
        return withGroups(groups, decodedLabels: decodedLabels)
    }

    private func withGroups(_ groups: [FlowchartGroupRecord], decodedLabels: [DiagramLabel]) -> FlowchartModel {
        guard let extras else { return self }
        return FlowchartModel(text: text, nodes: nodes, edges: edges,
                              extras: FlowchartModelExtras(groups: groups, groupMembers: extras.groupMembers, decodedLabels: decodedLabels,
                                                           assetAttributes: extras.assetAttributes, nodeStyles: extras.nodeStyles,
                                                           edgeStyles: extras.edgeStyles, sideBytes: extras.sideBytes))
    }
}

extension FlowchartDiagram {
    /// The shape of the node at `index`.
    func nodeShape(at index: Int) -> FlowchartNodeShape { model.nodes[index].shape }

    /// The text of the node at `index`, decoded now.
    func nodeLabel(at index: Int) -> DiagramLabel { model.label(model.nodes[index].label) ?? DiagramLabel(lines: []) }

    /// What the statements that style the diagram set for the node at `index`, or nil.
    func nodeStyle(at index: Int) -> DiagramElementStyle? { model.nodeStyle(at: index) }

    /// What the node at `index` shows when it is written as an icon or a picture, or nil.
    func nodeAsset(at index: Int) -> FlowchartNodeAsset? {
        let assetIndex = model.nodes[index].assetIndex
        guard assetIndex >= 0, let extras = model.extras else { return nil }
        return extras.assetAttributes[Int(assetIndex)].asset
    }

    /// The node indexes the edge at `index` runs from and to.
    func edgeEnds(at index: Int) -> (source: Int, target: Int) {
        let record = model.edges[index]
        return (Int(record.sourceIndex), Int(record.targetIndex))
    }

    /// The edge at `index` without its text: its ends, how it is drawn and how many ranks it spans.
    func edgeDrawing(at index: Int) -> FlowchartEdgeDrawing {
        let record = model.edges[index]
        return FlowchartEdgeDrawing(sourceIndex: Int(record.sourceIndex), targetIndex: Int(record.targetIndex), stroke: record.stroke,
                                    sourceArrowhead: record.sourceArrowhead, targetArrowhead: record.targetArrowhead,
                                    minimumRankSpan: Int(record.minimumRankSpan), style: model.edgeStyle(at: index))
    }

    /// Every edge without its text, in order.
    var edgeDrawings: [FlowchartEdgeDrawing] { (0..<edgeCount).map(edgeDrawing(at:)) }

    /// How many ranks the edge at `index` asks to span at least.
    func edgeMinimumRankSpan(at index: Int) -> Int { Int(model.edges[index].minimumRankSpan) }

    /// How the edge at `index` is drawn.
    func edgeStroke(at index: Int) -> FlowchartEdgeStroke { model.edges[index].stroke }

    /// The text on the edge at `index`, decoded now, or nil.
    func edgeLabel(at index: Int) -> DiagramLabel? { model.label(model.edges[index].label) }

    /// Whether any group is drawn as one node.
    var hasCollapsedSubgraph: Bool { model.extras?.groups.contains { group in group.isCollapsed } ?? false }
}

/// An edge of a flowchart without its text, which the layout reads from its measured texts.
struct FlowchartEdgeDrawing {
    let sourceIndex: Int
    let targetIndex: Int
    let stroke: FlowchartEdgeStroke
    let sourceArrowhead: FlowchartArrowhead
    let targetArrowhead: FlowchartArrowhead
    let minimumRankSpan: Int
    let style: DiagramElementStyle?
}
