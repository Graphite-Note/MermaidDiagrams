/**
 * File: FlowchartClusterGraph.swift
 * ---------------------------------
 * Layer: Core
 * Description: A flowchart with subgraphs as a graph of nested boxes to lay out.
 *
 * Authors: Félix Chevalier, Bahey Shalash
 * Version: 0.6
 * Date: 24/11/2026
 */

import CoreGraphics

/// A flowchart with subgraphs as a graph of nested boxes to lay out (`LayeredClusterLayout`), as Pele lays it out:
/// each group a box with 20 points of room on its sides and below, its title in a band along its top, at least as
/// wide as its title, running in its own direction or in that of the box around it; each node in the box of the group
/// that holds it; and each edge between two different nodes or boxes, a node that stands for a group (`A --> group`)
/// being the group's box.
struct FlowchartClusterGraph {
    /// Pele's room inside a box, on its sides and below it, and above it when the group has no title.
    static let clusterPadding: CGFloat = 20
    /// The room on a box's sides and below it in a tight layout (Pele's `groupPad` with `tight`); above it stays.
    static let tightClusterPadding: CGFloat = 12
    /// Between the box's top and its title, and between the title and the box's content.
    static let titleMargin: CGFloat = 8
    /// How much narrower than its title and two paddings a box may be: Pele's.
    static let titleWidthAllowance: CGFloat = 12

    let graph: LayeredClusterGraph
    /// For each node of the diagram, its node in `graph`, or nil for a node that stands for a group.
    let layoutNodeIndices: [Int?]
    /// For each node of the diagram, the group it stands for, or nil.
    let representedSubgraphs: [Int?]
    /// The diagram's edges laid out, in the order of `graph.edges`; an edge from a node to itself loops beside it.
    let layoutEdgeIndices: [Int]
    /// Each group's title, measured, or nil for a group without one.
    let titles: [DiagramTextBlock?]
    /// How many boxes each group's box is inside.
    let depths: [Int]
    /// The side each node's loops go out of, by the direction of the box it is in.
    let loopSides: [DiagramSide]

    /// Collapsed groups are folded into nodes before (`FlowchartCollapsedGroups`).
    /// `groupPadding`: the room inside a box on its sides and below.
    init<Measurer: DiagramTextMeasuring>(diagram: FlowchartDiagram, measured: FlowchartMeasurement, titleText: Measurer,
                                         edgeTextRoom: CGSize, groupPadding: CGFloat = clusterPadding) {
        let nesting = FlowchartClusterNesting(diagram: diagram)
        let subgraphCount = diagram.subgraphCount
        let measuredTitles = diagram.subgraphs.map { subgraph in
            let title = DiagramTextBlock(label: subgraph.title, measurer: titleText, maximumWidth: .greatestFiniteMagnitude)
            return title.lines.isEmpty ? nil : title
        }
        titles = measuredTitles
        depths = nesting.subgraphDepths
        representedSubgraphs = nesting.representedSubgraphs
        let nodeLoopSides: [DiagramSide] = nesting.nodeDirections.map { direction in direction.runsAcross ? .bottom : .right }
        loopSides = nodeLoopSides
        var layoutNodeIndices: [Int?] = []
        var nodeSizes: [CGSize] = []
        var nodeClusters: [Int?] = []
        var nodeSideSpans: [CGFloat] = []
        for node in 0..<diagram.nodeCount {
            guard nesting.representedSubgraphs[node] == nil else {
                layoutNodeIndices.append(nil)
                continue
            }
            layoutNodeIndices.append(nodeSizes.count)
            nodeSizes.append(measured.layoutSize(of: node, loopSide: nodeLoopSides[node]))
            nodeClusters.append(nesting.nodeSubgraphs[node])
            // A node whose loops go out below runs across, and spreads its edges along its height.
            nodeSideSpans.append(measured.sideSpan(of: node, shape: diagram.nodeShape(at: node), side: nodeLoopSides[node] == .bottom ? .left : .top))
        }
        self.layoutNodeIndices = layoutNodeIndices
        // Pele lists the groups before the nodes, an outer group before those inside it (flowchart/graph.ts), so an
        // empty group comes before the nodes of its box; a group an edge crosses runs as the box around it.
        let clusters = (0..<subgraphCount).map { subgraph in
            var cluster = Self.cluster(parent: nesting.subgraphParents[subgraph], direction: nesting.subgraphDirections[subgraph],
                                       title: measuredTitles[subgraph], spreadsEdgeEnds: measured.spreadsEdgeEnds, padding: groupPadding)
            cluster.sequence = CGFloat(nesting.subgraphOrder[subgraph] - subgraphCount)
            return cluster
        }
        let edges = Self.edges(of: diagram, measured: measured, edgeTextRoom: edgeTextRoom, layoutNodeIndices: layoutNodeIndices,
                                   representedSubgraphs: nesting.representedSubgraphs)
        layoutEdgeIndices = edges.diagramIndices
        graph = LayeredClusterGraph(nodeSizes: nodeSizes, nodeSideSpans: nodeSideSpans, nodeClusters: nodeClusters, clusters: clusters,
                                    edges: edges.layout, direction: diagram.direction.layeredDirection)
    }

    /// A group's box: Pele's padding, the title's band along the top, at least as wide as the title. A flowchart's group
    /// spreads the edges meeting it along its whole side (flowchart/render.ts gives it an infinite span); an agent flow's
    /// keeps them at its middle, as agentflow/render.ts gives its groups, like its nodes, no span.
    private static func cluster(parent: Int?, direction: FlowchartDirection?, title: DiagramTextBlock?, spreadsEdgeEnds: Bool,
                                padding: CGFloat) -> LayeredCluster {
        let titleSize = title?.size ?? .zero
        let top = title == nil ? clusterPadding : titleSize.height + 2 * titleMargin
        return LayeredCluster(parent: parent, direction: direction?.layeredDirection,
                              padding: LayeredClusterPadding(side: padding, top: top, bottom: padding),
                              minimumWidth: titleSize.width + 2 * padding - titleWidthAllowance, sideSpan: spreadsEdgeEnds ? .infinity : 0)
    }

    /// The edges between two different ends, with their texts' room; an edge from a node or a group to itself loops
    /// beside it and is not laid out.
    private static func edges(of diagram: FlowchartDiagram, measured: FlowchartMeasurement, edgeTextRoom: CGSize, layoutNodeIndices: [Int?],
                              representedSubgraphs: [Int?]) -> (layout: [LayeredClusterEdge], diagramIndices: [Int]) {
        func end(of node: Int) -> LayeredClusterEnd {
            if let subgraph = representedSubgraphs[node] { return .cluster(subgraph) }
            return .node(layoutNodeIndices[node] ?? 0)
        }
        var layout: [LayeredClusterEdge] = []
        var diagramIndices: [Int] = []
        for edgeIndex in 0..<diagram.edgeCount {
            let ends = diagram.edgeEnds(at: edgeIndex)
            let source = end(of: ends.source)
            let target = end(of: ends.target)
            guard source != target else { continue }
            let labelSize = measured.edgeTexts[edgeIndex].map { text in
                CGSize(width: text.size.width + edgeTextRoom.width, height: text.size.height + edgeTextRoom.height)
            }
            layout.append(LayeredClusterEdge(source: source, target: target, minimumRankSpan: diagram.edgeMinimumRankSpan(at: edgeIndex), labelSize: labelSize))
            diagramIndices.append(edgeIndex)
        }
        return (layout, diagramIndices)
    }
}
