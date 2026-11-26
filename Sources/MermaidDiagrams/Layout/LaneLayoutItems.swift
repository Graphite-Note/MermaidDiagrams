/**
 * File: LaneLayoutItems.swift
 * ---------------------------
 * Layer: Core
 * Description: What the lane layout works out once, before it places anything, on spans of the thread's scratch arena:
 *              the lanes, the boxes it ranks and the lane each is in, the room each lane keeps, the edges between
 *              ranked boxes and the ranks themselves.
 *
 * Authors: Bahey Shalash
 * Version: 0.3
 * Date: 26/11/2026
 */

import CoreGraphics

/// An edge between two ranked boxes, in flow space: its text's room across and along the flow.
struct LaneRankedEdge {
    /// The ranked boxes it runs from and to, by item, as written.
    let tail: Int
    let head: Int
    let minimumRankSpan: Int
    let labelAcross: CGFloat
    let labelAlong: CGFloat
    /// Whether ranking turned it around to break a cycle: it then runs from `head` down to `tail`.
    let isReversed: Bool
    /// Its edge in the graph.
    let edgeIndex: Int

    var upper: Int { isReversed ? head : tail }
    var lower: Int { isReversed ? tail : head }
    var hasLabel: Bool { labelAcross > 0 }
}

/// What Pele's `laneLayout` works out before its passes. The ranked boxes (items) are the nodes and the groups that hold
/// nothing, in the order of the boxes; each is in the lane of the top-level group around it. A lane keeps the room of its
/// padding and, around a box inside groups, the room of the widest padding of each group between, so that the groups
/// drawn around the boxes stay inside it. Every list is a span of the arena it was made in, valid until that arena is
/// released past it; the graph's boxes and edges are the spans the graph was given in.
struct LaneLayoutItems {
    /// Pele's: the deepest a box may be inside groups when its lane is looked for.
    static let maximumHops = 10_000

    let boxes: ScratchSpan<LaneLayoutBox>
    let graphEdges: ScratchSpan<LaneLayoutEdge>
    /// Each graph edge's text's room across and along the flow (zero without text), and whether it has text.
    let edgeLabelAcross: ScratchSpan<CGFloat>
    let edgeLabelAlong: ScratchSpan<CGFloat>
    let edgeHasLabel: ScratchSpan<Bool>
    let lanePadding: CGFloat
    let runsAcross: Bool
    let isFlipped: Bool
    /// The lanes, by box, in the order they are written: the graph lists groups last written first.
    let lanes: ScratchSpan<Int>
    /// Each box's lane, -1 for a box that is no lane.
    let laneSlots: ScratchSpan<Int>
    let laneCount: Int
    let lanePaddings: ScratchSpan<CGFloat>
    /// The room before the first rank and after the last: the most any lane keeps.
    let endPadding: CGFloat
    let items: ScratchSpan<Int>
    /// Each box's item, -1 for a box that is not ranked.
    let itemOfBox: ScratchSpan<Int>
    /// Each item's extent across the flow and along it, and its lane.
    let itemAcross: ScratchSpan<CGFloat>
    let itemAlong: ScratchSpan<CGFloat>
    let itemLanes: ScratchSpan<Int>
    let edges: ScratchSpan<LaneRankedEdge>
    /// 2 when an edge has text or two edges join the same items, so that a text or the second edge has a rank between.
    let step: Int
    let ranks: ScratchSpan<Int>

    init(graph: LaneLayoutSpanGraph, arena: DiagramScratchArena) {
        let boxes = graph.boxes
        self.boxes = boxes
        graphEdges = graph.edges
        lanePadding = graph.lanePadding
        runsAcross = !graph.direction.runsVertically
        isFlipped = graph.direction == .bottomToTop || graph.direction == .rightToLeft
        (edgeLabelAcross, edgeLabelAlong, edgeHasLabel) = Self.labelExtents(graphEdges, runsAcross: runsAcross, arena: arena)
        (lanes, laneSlots) = Self.lanes(of: boxes, arena: arena)
        laneCount = max(1, lanes.count)
        (items, itemOfBox) = Self.items(of: boxes, laneSlots: laneSlots, arena: arena)
        let slots = laneSlots
        let items = self.items
        let itemCount = items.count
        let itemAcross: ScratchSpan<CGFloat> = arena.uninitializedSpan(count: itemCount)
        let itemAlong: ScratchSpan<CGFloat> = arena.uninitializedSpan(count: itemCount)
        for item in 0..<itemCount {
            let size = boxes[items[item]].size
            itemAcross[item] = runsAcross ? size.height : size.width
            itemAlong[item] = runsAcross ? size.width : size.height
        }
        self.itemAcross = itemAcross
        self.itemAlong = itemAlong
        (edges, step) = Self.rankedEdges(graphEdges, itemOfBox: itemOfBox, itemCount: itemCount, runsAcross: runsAcross, arena: arena)
        let oriented: ScratchSpan<LaneOrientedEdge> = arena.uninitializedSpan(count: edges.count)
        for (position, edge) in edges.enumerated() {
            oriented[position] = LaneOrientedEdge(source: edge.upper, target: edge.lower, length: max(1, edge.minimumRankSpan) * step)
        }
        ranks = LaneRanking.balancedRanks(nodeCount: itemCount, edges: oriented, arena: arena)
        let paddings = arena.span(count: laneCount, repeating: graph.lanePadding)
        let itemLanes: ScratchSpan<Int> = arena.uninitializedSpan(count: itemCount)
        var endPadding = graph.lanePadding
        for item in 0..<itemCount {
            itemLanes[item] = Self.lane(of: items[item], boxes: boxes, laneSlots: slots, lanePadding: graph.lanePadding, paddings: paddings,
                                        endPadding: &endPadding)
        }
        self.itemLanes = itemLanes
        lanePaddings = paddings
        self.endPadding = endPadding
    }

    /// The lanes, by box, the last written first, and each box's lane (-1 for a box that is no lane).
    private static func lanes(of boxes: ScratchSpan<LaneLayoutBox>, arena: DiagramScratchArena) -> (ScratchSpan<Int>, ScratchSpan<Int>) {
        let slots = arena.span(count: boxes.count, repeating: -1)
        var lanes = arena.list(capacity: 8, of: Int.self)
        for box in stride(from: boxes.count - 1, through: 0, by: -1) where boxes[box].parent == nil && boxes[box].isGroup {
            slots[box] = lanes.count
            lanes.append(box)
        }
        return (lanes.elements, slots)
    }

    /// The boxes ranked, nodes and groups that hold nothing outside the lanes, and each box's item (-1 for none).
    private static func items(of boxes: ScratchSpan<LaneLayoutBox>, laneSlots: ScratchSpan<Int>, arena: DiagramScratchArena) -> (ScratchSpan<Int>, ScratchSpan<Int>) {
        let holdsBoxes = arena.span(count: boxes.count, repeating: false)
        for box in 0..<boxes.count { if let parent = boxes[box].parent { holdsBoxes[parent] = true } }
        let itemOfBox = arena.span(count: boxes.count, repeating: -1)
        var items = arena.list(capacity: boxes.count, of: Int.self)
        for box in 0..<boxes.count where laneSlots[box] == -1 && (!boxes[box].isGroup || !holdsBoxes[box]) {
            itemOfBox[box] = items.count
            items.append(box)
        }
        return (items.elements, itemOfBox)
    }

    static func copied<Element: BitwiseCopyable>(_ array: [Element], arena: DiagramScratchArena) -> ScratchSpan<Element> {
        let span: ScratchSpan<Element> = arena.uninitializedSpan(count: array.count)
        array.withUnsafeBufferPointer { buffer in
            if let base = buffer.baseAddress { span.start.update(from: base, count: buffer.count) }
        }
        return span
    }

    /// Each graph edge's text's room in flow space, and whether it has text that is wider than nothing.
    private static func labelExtents(_ edges: ScratchSpan<LaneLayoutEdge>, runsAcross: Bool, arena: DiagramScratchArena)
        -> (ScratchSpan<CGFloat>, ScratchSpan<CGFloat>, ScratchSpan<Bool>) {
        let across: ScratchSpan<CGFloat> = arena.uninitializedSpan(count: edges.count)
        let along: ScratchSpan<CGFloat> = arena.uninitializedSpan(count: edges.count)
        let hasLabel: ScratchSpan<Bool> = arena.uninitializedSpan(count: edges.count)
        for edgeIndex in 0..<edges.count {
            let size = edges[edgeIndex].labelSize ?? .zero
            across[edgeIndex] = runsAcross ? size.height : size.width
            along[edgeIndex] = runsAcross ? size.width : size.height
            hasLabel[edgeIndex] = size.width > 0
        }
        return (across, along, hasLabel)
    }

    /// The edges between two different items, turned around where they close a cycle (`LaneRanking.cycleClosingEdges`),
    /// and the step their ranks take.
    private static func rankedEdges(_ graphEdges: ScratchSpan<LaneLayoutEdge>, itemOfBox: ScratchSpan<Int>, itemCount: Int, runsAcross: Bool,
                                    arena: DiagramScratchArena) -> (edges: ScratchSpan<LaneRankedEdge>, step: Int) {
        var tails = arena.list(capacity: graphEdges.count, of: Int.self)
        var heads = arena.list(capacity: graphEdges.count, of: Int.self)
        var writtenEdges = arena.list(capacity: graphEdges.count, of: Int.self)
        var keys = arena.list(capacity: graphEdges.count, of: Int.self)
        var step = 1
        for edgeIndex in 0..<graphEdges.count {
            let edge = graphEdges[edgeIndex]
            let tail = itemOfBox[edge.source]
            let head = itemOfBox[edge.target]
            guard tail >= 0, head >= 0, tail != head else { continue }
            if edge.labelSize.map({ size in size.width > 0 }) ?? false { step = 2 }
            keys.append(min(tail, head) * itemCount + max(tail, head))
            tails.append(tail)
            heads.append(head)
            writtenEdges.append(edgeIndex)
        }
        // Two edges joining the same items also take the step of 2: found as two equal keys once sorted.
        if step == 1, keys.count > 1 {
            let sorted = arena.copy(of: keys.elements)
            sorted.sortAscending()
            for index in 1..<sorted.count where sorted[index] == sorted[index - 1] {
                step = 2
                break
            }
        }
        let reversed = LaneRanking.cycleClosingEdges(nodeCount: itemCount, sources: tails.elements, targets: heads.elements, arena: arena)
        let edges: ScratchSpan<LaneRankedEdge> = arena.uninitializedSpan(count: writtenEdges.count)
        for position in 0..<writtenEdges.count {
            let edgeIndex = writtenEdges[position]
            let label = graphEdges[edgeIndex].labelSize ?? .zero
            edges[position] = LaneRankedEdge(tail: tails[position], head: heads[position], minimumRankSpan: graphEdges[edgeIndex].minimumRankSpan,
                                             labelAcross: runsAcross ? label.height : label.width,
                                             labelAlong: runsAcross ? label.width : label.height,
                                             isReversed: reversed[position], edgeIndex: edgeIndex)
        }
        return (edges, step)
    }

    /// The lane `box` is in, keeping in its lane and at the ends the room its groups need.
    private static func lane(of box: Int, boxes: ScratchSpan<LaneLayoutBox>, laneSlots: ScratchSpan<Int>, lanePadding: CGFloat,
                             paddings: ScratchSpan<CGFloat>, endPadding: inout CGFloat) -> Int {
        var current = box
        var room = lanePadding
        var hops = 0
        while let parent = boxes[current].parent, hops < maximumHops {
            current = parent
            if laneSlots[current] == -1 {
                let padding = boxes[current].padding
                room += max(padding.side, padding.top, padding.bottom)
            }
            hops += 1
        }
        let lane = max(laneSlots[current], 0)
        paddings[lane] = max(paddings[lane], room)
        endPadding = max(endPadding, room)
        return lane
    }
}
