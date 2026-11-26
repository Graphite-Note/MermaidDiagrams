/**
 * File: ReferenceSwimlaneGraph.swift
 * ----------------------------------
 * Layer: Tests
 * Description: The 0.7.0 SwimlaneGraph kept as the reference the swimlane graph written into the scratch arena is checked
 *              against: a swimlane diagram's flowchart as the lists of boxes and edges its lane layout lays out.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 26/11/2026
 */

import CoreGraphics
@testable import MermaidDiagrams

/// A flowchart as the boxes and edges of its lanes (`LaneLayoutGraph`), as Pele's swimlane variant prepares its graph: the
/// groups first, listed as Pele's flowchart graph lists them (the group that ends last first), each with Pele's padding,
/// its title's band and least width; then the nodes drawn, each its size with the room of its loops, a node that stands for
/// a group being the group's box; then, when some node is outside every group, one unnamed lane that holds them. Every
/// lane runs as the diagram does: a `direction` inside a group has no effect.
struct ReferenceSwimlaneGraph {
    /// Pele's room inside a group's box, and above it when it has no title.
    static let groupPadding: CGFloat = 20
    static let tightGroupPadding: CGFloat = 12
    /// Between a title and its box's top, and its content, together.
    static let titleRoom: CGFloat = 16
    /// How much narrower than its title and two paddings a group may be.
    static let titleWidthAllowance: CGFloat = 12

    let graph: LaneLayoutGraph
    /// For each group of the diagram, its box.
    let subgraphBoxes: [Int]
    /// For each node of the diagram, its box: its own, or its group's for a node that stands for a group.
    let nodeBoxes: [Int]
    /// The lane of the nodes outside every group, or nil when there is none.
    let looseLaneBox: Int?
    /// Each group's title, measured, or nil for a group without one.
    let titles: [DiagramTextBlock?]
    let nesting: FlowchartClusterNesting

    init<Measurer: DiagramTextMeasuring>(diagram: FlowchartDiagram, measured: FlowchartMeasurement, titleText: Measurer, titleWidth: CGFloat,
                                         isTight: Bool, edgeTextRoom: CGSize) {
        let nesting = FlowchartClusterNesting(diagram: diagram)
        self.nesting = nesting
        let padding = isTight ? Self.tightGroupPadding : Self.groupPadding
        let titles = diagram.subgraphs.map { subgraph in
            let title = DiagramTextBlock(label: subgraph.title, measurer: titleText, maximumWidth: titleWidth)
            return title.lines.isEmpty ? nil : title
        }
        self.titles = titles
        var boxes: [LaneLayoutBox] = []
        var subgraphBoxes = [Int](repeating: 0, count: diagram.subgraphs.count)
        for subgraph in Self.peleGroupOrder(diagram, parents: nesting.subgraphParents) {
            subgraphBoxes[subgraph] = boxes.count
            boxes.append(Self.group(title: titles[subgraph], padding: padding))
        }
        var nodeBoxes = [Int](repeating: 0, count: diagram.nodes.count)
        var hasLooseNode = false
        for node in diagram.nodes.indices {
            if let subgraph = nesting.representedSubgraphs[node] {
                nodeBoxes[node] = subgraphBoxes[subgraph]
                // A group has no size of its own, but its loops still widen it, which shows when it holds nothing.
                boxes[subgraphBoxes[subgraph]].size = Self.layoutSize(of: node, base: .zero, measured: measured, flowRunsAcross: diagram.direction.runsAcross)
                continue
            }
            nodeBoxes[node] = boxes.count
            boxes.append(LaneLayoutBox(size: Self.layoutSize(of: node, base: measured.shapeSizes[node], measured: measured,
                                                             flowRunsAcross: diagram.direction.runsAcross), parent: nil, isGroup: false))
            if nesting.nodeSubgraphs[node] == nil { hasLooseNode = true }
        }
        looseLaneBox = hasLooseNode ? boxes.count : nil
        if hasLooseNode { boxes.append(Self.group(title: nil, padding: padding)) }
        for subgraph in diagram.subgraphs.indices { boxes[subgraphBoxes[subgraph]].parent = nesting.subgraphParents[subgraph].map { parent in subgraphBoxes[parent] } }
        for node in diagram.nodes.indices where nesting.representedSubgraphs[node] == nil {
            boxes[nodeBoxes[node]].parent = nesting.nodeSubgraphs[node].map { subgraph in subgraphBoxes[subgraph] } ?? looseLaneBox
        }
        self.subgraphBoxes = subgraphBoxes
        self.nodeBoxes = nodeBoxes
        graph = LaneLayoutGraph(boxes: boxes, edges: Self.edges(of: diagram, measured: measured, nodeBoxes: nodeBoxes, edgeTextRoom: edgeTextRoom),
                                direction: diagram.direction.layeredDirection, lanePadding: isTight ? 12 : 24)
    }

    /// A node's size in its rank: `base`, its shape's or none for a group's, grown on both sides across the flow by the room
    /// each of its loops takes, as Pele's flowchart renderer grows the node it lays out (`FlowchartSelfLoops.room`).
    static func layoutSize(of node: Int, base: CGSize, measured: FlowchartMeasurement, flowRunsAcross: Bool) -> CGSize {
        var size = base
        for edgeIndex in measured.selfLoopEdgeIndices[node] {
            let room = FlowchartSelfLoops.room(textSize: measured.edgeTexts[edgeIndex]?.size, flowRunsAcross: flowRunsAcross)
            if flowRunsAcross { size.height += 2 * room } else { size.width += 2 * room }
        }
        return size
    }

    /// Every edge between the boxes of its nodes, with its text's room.
    private static func edges(of diagram: FlowchartDiagram, measured: FlowchartMeasurement, nodeBoxes: [Int], edgeTextRoom: CGSize) -> [LaneLayoutEdge] {
        diagram.edges.enumerated().map { edgeIndex, edge in
            LaneLayoutEdge(source: nodeBoxes[edge.sourceIndex], target: nodeBoxes[edge.targetIndex], minimumRankSpan: edge.minimumRankSpan,
                           labelSize: measured.edgeTexts[edgeIndex].map { text in
                               CGSize(width: text.size.width + edgeTextRoom.width, height: text.size.height + edgeTextRoom.height)
                           })
        }
    }

    /// A group's box: no size of its own, Pele's padding, its title's band (20 points without a title), at least as wide as
    /// its title and two paddings, less 12.
    private static func group(title: DiagramTextBlock?, padding: CGFloat) -> LaneLayoutBox {
        let titleSize = title?.size ?? .zero
        return LaneLayoutBox(size: .zero, parent: nil, isGroup: true,
                             padding: LayeredClusterPadding(side: padding, top: title == nil ? groupPadding : titleSize.height + titleRoom, bottom: padding),
                             minimumWidth: titleSize.width + 2 * padding - titleWidthAllowance)
    }

    /// The groups in the order of Pele's flowchart graph: Mermaid lists a group when it ends, so a group after the groups
    /// inside it, and Pele's graph lists them from the last to the first.
    static func peleGroupOrder(_ diagram: FlowchartDiagram, parents: [Int?]) -> [Int] {
        var ended: [Int] = []
        var stack: [(subgraph: Int, nextChild: Int)] = []
        for root in diagram.subgraphs.indices where parents[root] == nil {
            stack.append((root, 0))
            while let top = stack.last {
                let children = diagram.subgraphs[top.subgraph].childSubgraphIndices
                if top.nextChild < children.count {
                    stack[stack.count - 1].nextChild += 1
                    stack.append((children[top.nextChild], 0))
                } else {
                    ended.append(top.subgraph)
                    stack.removeLast()
                }
            }
        }
        return ended.reversed()
    }
}
