/**
 * File: SwimlaneGraph.swift
 * -------------------------
 * Layer: Core
 * Description: A swimlane diagram's flowchart as the graph its lane layout lays out, in the order of Pele's flowchart
 *              graph: the groups, the nodes, and a lane for the nodes outside every group, written as spans of the
 *              thread's scratch arena straight from the flowchart's records.
 *
 * Authors: Bahey Shalash
 * Version: 0.5
 * Date: 26/11/2026
 */

import CoreGraphics

/// A flowchart as the boxes and edges of its lanes (`LaneLayoutSpanGraph`), as Pele's swimlane variant prepares its graph:
/// the groups first, listed as Pele's flowchart graph lists them (the group that ends last first), each with Pele's
/// padding, its title's band and least width; then the nodes drawn, each its size with the room of its loops, a node that
/// stands for a group being the group's box; then, when some node is outside every group, one unnamed lane that holds them.
/// Every lane runs as the diagram does: a `direction` inside a group has no effect.
///
/// Everything but the titles is a span of the arena it was made in, read from the flowchart's group, member and edge
/// records: no list of subgraphs or edges is made, and where each node and group sits among the groups is worked out here
/// (`SwimlaneGroupNesting`) with only what a swimlane reads of it.
struct SwimlaneGraph {
    /// Pele's room inside a group's box, and above it when it has no title.
    static let groupPadding: CGFloat = 20
    static let tightGroupPadding: CGFloat = 12
    /// Between a title and its box's top, and its content, together.
    static let titleRoom: CGFloat = 16
    /// How much narrower than its title and two paddings a group may be.
    static let titleWidthAllowance: CGFloat = 12

    let graph: LaneLayoutSpanGraph
    /// For each group of the diagram, its box.
    let subgraphBoxes: ScratchSpan<Int>
    /// For each node of the diagram, its box: its own, or its group's for a node that stands for a group.
    let nodeBoxes: ScratchSpan<Int>
    /// The lane of the nodes outside every group, or nil when there is none.
    let looseLaneBox: Int?
    /// Each group's title, measured, or nil for a group without one.
    let titles: [DiagramTextBlock?]
    let nesting: SwimlaneGroupNesting

    init<Measurer: DiagramTextMeasuring>(diagram: FlowchartDiagram, measured: FlowchartMeasurement, titleText: Measurer, titleWidth: CGFloat,
                                         isTight: Bool, edgeTextRoom: CGSize, arena: DiagramScratchArena) {
        let model = diagram.model
        let groups = model.extras?.groups ?? []
        let members = model.extras?.groupMembers ?? []
        let nesting = SwimlaneGroupNesting(groups: groups, members: members, nodeCount: model.nodes.count, arena: arena)
        self.nesting = nesting
        let padding = isTight ? Self.tightGroupPadding : Self.groupPadding
        let titles = groups.map { group in
            let title = DiagramTextBlock(label: model.label(group.title) ?? DiagramLabel(lines: []), measurer: titleText, maximumWidth: titleWidth)
            return title.lineCount == 0 ? nil : title
        }
        self.titles = titles
        let nodeCount = model.nodes.count
        var boxes = arena.list(capacity: groups.count + nodeCount + 1, of: LaneLayoutBox.self)
        let subgraphBoxes = arena.span(count: groups.count, repeating: 0)
        for subgraph in Self.peleGroupOrder(groups, members: members, parents: nesting.subgraphParents, arena: arena) {
            subgraphBoxes[subgraph] = boxes.count
            boxes.append(Self.group(title: titles[subgraph], padding: padding))
        }
        let nodeBoxes = arena.span(count: nodeCount, repeating: 0)
        let looseLaneBox = Self.addNodes(to: &boxes, nodeBoxes: nodeBoxes, subgraphBoxes: subgraphBoxes, nesting: nesting, measured: measured,
                                         flowRunsAcross: diagram.direction.runsAcross, padding: padding)
        self.looseLaneBox = looseLaneBox
        for subgraph in 0..<groups.count {
            let parent = nesting.subgraphParents[subgraph]
            boxes[subgraphBoxes[subgraph]].parent = parent >= 0 ? subgraphBoxes[parent] : nil
        }
        for node in 0..<nodeCount where nesting.representedSubgraphs[node] < 0 {
            let subgraph = nesting.nodeSubgraphs[node]
            boxes[nodeBoxes[node]].parent = subgraph >= 0 ? subgraphBoxes[subgraph] : looseLaneBox
        }
        self.subgraphBoxes = subgraphBoxes
        self.nodeBoxes = nodeBoxes
        graph = LaneLayoutSpanGraph(boxes: boxes.elements,
                                    edges: Self.edges(of: model.edges, measured: measured, nodeBoxes: nodeBoxes, edgeTextRoom: edgeTextRoom, arena: arena),
                                    direction: diagram.direction.layeredDirection, lanePadding: isTight ? 12 : 24)
    }

    /// Each node's box after the groups' (a node standing for a group sized into the group's box), then, when some node is
    /// outside every group, the lane that holds them, whose box it gives; each node's box goes into `nodeBoxes`.
    private static func addNodes(to boxes: inout ScratchList<LaneLayoutBox>, nodeBoxes: ScratchSpan<Int>, subgraphBoxes: ScratchSpan<Int>,
                                 nesting: SwimlaneGroupNesting, measured: FlowchartMeasurement, flowRunsAcross: Bool, padding: CGFloat) -> Int? {
        var hasLooseNode = false
        for node in 0..<nodeBoxes.count {
            let represented = nesting.representedSubgraphs[node]
            if represented >= 0 {
                nodeBoxes[node] = subgraphBoxes[represented]
                // A group has no size of its own, but its loops still widen it, which shows when it holds nothing.
                boxes[subgraphBoxes[represented]].size = layoutSize(of: node, base: .zero, measured: measured, flowRunsAcross: flowRunsAcross)
                continue
            }
            nodeBoxes[node] = boxes.count
            boxes.append(LaneLayoutBox(size: layoutSize(of: node, base: measured.shapeSizes[node], measured: measured, flowRunsAcross: flowRunsAcross),
                                       parent: nil, isGroup: false))
            if nesting.nodeSubgraphs[node] < 0 { hasLooseNode = true }
        }
        guard hasLooseNode else { return nil }
        boxes.append(group(title: nil, padding: padding))
        return boxes.count - 1
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
    private static func edges(of records: [FlowchartEdgeRecord], measured: FlowchartMeasurement, nodeBoxes: ScratchSpan<Int>, edgeTextRoom: CGSize,
                              arena: DiagramScratchArena) -> ScratchSpan<LaneLayoutEdge> {
        let edges: ScratchSpan<LaneLayoutEdge> = arena.uninitializedSpan(count: records.count)
        for (edgeIndex, record) in records.enumerated() {
            edges[edgeIndex] = LaneLayoutEdge(source: nodeBoxes[Int(record.sourceIndex)], target: nodeBoxes[Int(record.targetIndex)],
                                              minimumRankSpan: Int(record.minimumRankSpan), labelSize: measured.edgeTexts[edgeIndex].map { text in
                                                  CGSize(width: text.size.width + edgeTextRoom.width, height: text.size.height + edgeTextRoom.height)
                                              })
        }
        return edges
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
    /// inside it, and Pele's graph lists them from the last to the first. `parents` holds -1 for a group at the top.
    static func peleGroupOrder(_ groups: [FlowchartGroupRecord], members: [Int32], parents: ScratchSpan<Int>,
                               arena: DiagramScratchArena) -> ScratchSpan<Int> {
        var ended = arena.list(capacity: groups.count, of: Int.self)
        var stack = arena.list(capacity: 8, of: SwimlaneGroupVisit.self)
        for root in groups.indices where parents[root] < 0 {
            stack.append(SwimlaneGroupVisit(group: root, nextMember: Int(groups[root].childGroupIndices.lowerBound)))
            while let top = stack.last {
                if top.nextMember < Int(groups[top.group].childGroupIndices.upperBound) {
                    stack[stack.count - 1].nextMember += 1
                    let child = Int(members[top.nextMember])
                    stack.append(SwimlaneGroupVisit(group: child, nextMember: Int(groups[child].childGroupIndices.lowerBound)))
                } else {
                    ended.append(top.group)
                    _ = stack.removeLast()
                }
            }
        }
        let order = ended.elements
        order.reverse(0..<order.count)
        return order
    }
}

/// A group on the way through the groups: the group, and the place among the members of the next of its groups to visit.
struct SwimlaneGroupVisit {
    let group: Int
    var nextMember: Int
}

/// Where each node and group of a flowchart sits among its groups, as `FlowchartClusterNesting` finds it, with only what a
/// swimlane reads: -1 where that names none. Every list is a span of the arena it was made in.
struct SwimlaneGroupNesting {
    /// For each node, the group directly holding it, or -1.
    let nodeSubgraphs: ScratchSpan<Int>
    /// For each node, the group it stands for, or -1.
    let representedSubgraphs: ScratchSpan<Int>
    /// For each group, the group directly holding it, or -1.
    let subgraphParents: ScratchSpan<Int>
    let subgraphDepths: ScratchSpan<Int>
    /// Whether some group sits inside another: inside a lane.
    let hasGroupInsideLane: Bool

    init(groups: [FlowchartGroupRecord], members: [Int32], nodeCount: Int, arena: DiagramScratchArena) {
        let nodeSubgraphs = arena.span(count: nodeCount, repeating: -1)
        let representedSubgraphs = arena.span(count: nodeCount, repeating: -1)
        let subgraphParents = arena.span(count: groups.count, repeating: -1)
        for (index, group) in groups.enumerated() {
            for member in group.nodeIndices { nodeSubgraphs[Int(members[Int(member)])] = index }
            for member in group.childGroupIndices { subgraphParents[Int(members[Int(member)])] = index }
            if group.representingNodeIndex >= 0 { representedSubgraphs[Int(group.representingNodeIndex)] = index }
        }
        // The model lists each group before the groups inside it.
        let depths = arena.span(count: groups.count, repeating: 0)
        var hasGroupInsideLane = false
        for index in 0..<groups.count {
            let parent = subgraphParents[index]
            depths[index] = parent >= 0 ? depths[parent] + 1 : 0
            if parent >= 0 { hasGroupInsideLane = true }
        }
        self.nodeSubgraphs = nodeSubgraphs
        self.representedSubgraphs = representedSubgraphs
        self.subgraphParents = subgraphParents
        subgraphDepths = depths
        self.hasGroupInsideLane = hasGroupInsideLane
    }
}
