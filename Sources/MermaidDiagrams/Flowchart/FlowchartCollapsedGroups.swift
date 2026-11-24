/**
 * File: FlowchartCollapsedGroups.swift
 * ------------------------------------
 * Layer: Core
 * Description: A flowchart with its collapsed groups drawn as single nodes, as Pele's flowchart graph builds it.
 *
 * Authors: Bahey Shalash
 * Version: 0.3
 * Date: 24/11/2026
 */

/// Folds each collapsed group (`group@{ view: collapsed }`) into one node, as Pele's `buildFlowGraph` does
/// (`flowchart/graph.ts`): the outermost collapsed group around anything stands for it, a node in the shape of a
/// collapsed group with the group's title and the style its identifier's node sets; the nodes and groups inside are
/// not drawn, each edge to or from them meets that node instead, and an edge that then runs from the node to itself
/// is left out. The collapsed nodes come first, as Pele lists its groups (last ended first) before its nodes.
enum FlowchartCollapsedGroups {
    static func collapsing(_ diagram: FlowchartDiagram) -> FlowchartDiagram {
        guard diagram.hasCollapsedSubgraph else { return diagram }
        let folding = Folding(diagram: diagram)
        return FlowchartDiagram(direction: diagram.direction, nodes: folding.nodes, edges: diagram.edges.compactMap { edge in folding.edge(edge) },
                                subgraphs: folding.subgraphs, title: diagram.title, accessibilityTitle: diagram.accessibilityTitle,
                                accessibilityDescription: diagram.accessibilityDescription, unappliedStatementCount: diagram.unappliedStatementCount)
    }

    /// Where each node and group of the diagram goes once its collapsed groups are folded.
    private struct Folding {
        /// The diagram's nodes and groups, made once.
        let diagramNodes: [FlowchartNode]
        let diagramSubgraphs: [FlowchartSubgraph]
        /// For each group, the outermost collapsed group around it, itself included, or nil.
        let outermostCollapsed: [Int?]
        /// For each node of the diagram, the collapsed group it is folded into, or nil.
        let foldedInto: [Int?]
        /// For each collapsed group drawn as a node, its index among the new nodes.
        private(set) var collapsedNodeIndices: [Int: Int] = [:]
        /// For each node of the diagram still drawn, its index among the new nodes.
        private(set) var nodeIndices: [Int?]
        /// For each group still drawn as a box, its index among the new groups.
        private(set) var subgraphIndices: [Int?]
        private(set) var nodes: [FlowchartNode] = []

        init(diagram: FlowchartDiagram) {
            diagramNodes = diagram.nodes
            diagramSubgraphs = diagram.subgraphs
            let parents = FlowchartClusterNesting(diagram: diagram).subgraphParents
            var outermost = [Int?](repeating: nil, count: diagramSubgraphs.count)
            // Groups are listed before the groups inside them, so a parent's outermost collapsed group is known first.
            for (index, subgraph) in diagramSubgraphs.enumerated() {
                outermost[index] = parents[index].flatMap { parent in outermost[parent] } ?? (subgraph.isCollapsed ? index : nil)
            }
            outermostCollapsed = outermost
            var folded = [Int?](repeating: nil, count: diagramNodes.count)
            for (index, subgraph) in diagramSubgraphs.enumerated() {
                guard let ancestor = outermost[index] else { continue }
                for node in subgraph.nodeIndices { folded[node] = ancestor }
                if let node = subgraph.representingNodeIndex { folded[node] = ancestor }
            }
            foldedInto = folded
            nodeIndices = Array(repeating: nil, count: diagramNodes.count)
            subgraphIndices = Array(repeating: nil, count: diagramSubgraphs.count)
            placeNodes()
            placeSubgraphs()
        }

        /// The collapsed groups' nodes first, in Pele's order: its groups in the reverse of the order they end, which for
        /// groups not inside each other is the reverse of the order they are written in; then the nodes still drawn.
        private mutating func placeNodes() {
            for (index, subgraph) in diagramSubgraphs.enumerated().reversed() where outermostCollapsed[index] == index {
                let style = subgraph.representingNodeIndex.flatMap { node in diagramNodes[node].style }
                collapsedNodeIndices[index] = nodes.count
                nodes.append(FlowchartNode(identifier: subgraph.identifier, label: subgraph.title, shape: .collapsedGroup, style: style))
            }
            for (index, node) in diagramNodes.enumerated() where foldedInto[index] == nil {
                nodeIndices[index] = nodes.count
                nodes.append(node)
            }
        }

        private mutating func placeSubgraphs() {
            var count = 0
            for index in diagramSubgraphs.indices where outermostCollapsed[index] == nil {
                subgraphIndices[index] = count
                count += 1
            }
        }

        /// The groups still drawn as boxes, holding their nodes, their groups and the collapsed groups directly inside them.
        var subgraphs: [FlowchartSubgraph] {
            diagramSubgraphs.indices.compactMap { index in
                guard subgraphIndices[index] != nil else { return nil }
                var subgraph = diagramSubgraphs[index]
                let children = subgraph.childSubgraphIndices
                subgraph.nodeIndices = subgraph.nodeIndices.compactMap { node in nodeIndices[node] }
                    + children.compactMap { child in collapsedNodeIndices[child] }
                subgraph.childSubgraphIndices = children.compactMap { child in subgraphIndices[child] }
                subgraph.representingNodeIndex = subgraph.representingNodeIndex.flatMap { node in nodeIndices[node] }
                return subgraph
            }
        }

        /// The edge between the new nodes, or nil when folding makes it run from a collapsed group's node to itself.
        func edge(_ edge: FlowchartEdge) -> FlowchartEdge? {
            let source = newIndex(of: edge.sourceIndex)
            let target = newIndex(of: edge.targetIndex)
            if source == target, foldedInto[edge.sourceIndex] != nil || foldedInto[edge.targetIndex] != nil {
                let representsBoth = isRepresentingNode(edge.sourceIndex) && isRepresentingNode(edge.targetIndex)
                guard representsBoth else { return nil }
            }
            return FlowchartEdge(sourceIndex: source, targetIndex: target, stroke: edge.stroke, sourceArrowhead: edge.sourceArrowhead,
                                 targetArrowhead: edge.targetArrowhead, minimumRankSpan: edge.minimumRankSpan, label: edge.label, style: edge.style)
        }

        private func newIndex(of node: Int) -> Int {
            if let group = foldedInto[node], let collapsedNode = collapsedNodeIndices[group] { return collapsedNode }
            return nodeIndices[node] ?? 0
        }

        /// Whether `node` stands for the collapsed group it is folded into, rather than sitting inside it.
        private func isRepresentingNode(_ node: Int) -> Bool {
            guard let group = foldedInto[node] else { return false }
            return diagramSubgraphs[group].representingNodeIndex == node
        }
    }
}
