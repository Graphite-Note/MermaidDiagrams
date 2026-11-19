/**
 * File: LaneLayoutItems.swift
 * ---------------------------
 * Layer: Core
 * Description: What the lane layout works out once, before it places anything: the lanes, the boxes it ranks and the
 *              lane each is in, the room each lane keeps, the edges between ranked boxes and the ranks themselves.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 19/11/2026
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
/// drawn around the boxes stay inside it.
struct LaneLayoutItems {
    /// Pele's: the deepest a box may be inside groups when its lane is looked for.
    static let maximumHops = 10_000

    let graph: LaneLayoutGraph
    let runsAcross: Bool
    let isFlipped: Bool
    /// The lanes, by box, in the order they are written: the graph lists groups last written first.
    let lanes: [Int]
    let laneSlots: [Int?]
    var laneCount: Int { max(1, lanes.count) }
    private(set) var lanePaddings: [CGFloat]
    /// The room before the first rank and after the last: the most any lane keeps.
    private(set) var endPadding: CGFloat
    let items: [Int]
    let itemOfBox: [Int?]
    /// Each item's extent across the flow and along it.
    let itemAcross: [CGFloat]
    let itemAlong: [CGFloat]
    private(set) var itemLanes: [Int] = []
    let edges: [LaneRankedEdge]
    /// 2 when an edge has text or two edges join the same items, so that a text or the second edge has a rank between.
    let step: Int
    let ranks: [Int]

    init(graph: LaneLayoutGraph) {
        self.graph = graph
        runsAcross = !graph.direction.runsVertically
        isFlipped = graph.direction == .bottomToTop || graph.direction == .rightToLeft
        let boxes = graph.boxes
        lanes = boxes.indices.reversed().filter { box in boxes[box].parent == nil && boxes[box].isGroup }
        var slots = [Int?](repeating: nil, count: boxes.count)
        for (slot, box) in lanes.enumerated() { slots[box] = slot }
        laneSlots = slots
        lanePaddings = Array(repeating: graph.lanePadding, count: max(1, lanes.count))
        endPadding = graph.lanePadding
        var holdsBoxes = [Bool](repeating: false, count: boxes.count)
        for box in boxes { if let parent = box.parent { holdsBoxes[parent] = true } }
        let items = boxes.indices.filter { box in slots[box] == nil && (!boxes[box].isGroup || !holdsBoxes[box]) }
        self.items = items
        var itemOfBox = [Int?](repeating: nil, count: boxes.count)
        for (item, box) in items.enumerated() { itemOfBox[box] = item }
        self.itemOfBox = itemOfBox
        let across = runsAcross
        itemAcross = items.map { box in across ? boxes[box].size.height : boxes[box].size.width }
        itemAlong = items.map { box in across ? boxes[box].size.width : boxes[box].size.height }
        let ranked = Self.rankedEdges(graph: graph, itemOfBox: itemOfBox, itemCount: items.count, runsAcross: across)
        edges = ranked.edges
        step = ranked.step
        ranks = LayeredRanking.balancedRanks(nodeCount: items.count, orientedEdges: ranked.edges.map { edge in
            (edge.upper, edge.lower, max(1, edge.minimumRankSpan) * ranked.step)
        })
        for box in items { itemLanes.append(lane(of: box)) }
    }

    /// The edges between two different items, turned around where they close a cycle (`declarationOrderCycleClosingEdges`),
    /// and the step their ranks take.
    private static func rankedEdges(graph: LaneLayoutGraph, itemOfBox: [Int?], itemCount: Int,
                                    runsAcross: Bool) -> (edges: [LaneRankedEdge], step: Int) {
        var written: [(tail: Int, head: Int, edgeIndex: Int)] = []
        var joined = Set<Int>()
        var step = 1
        for (edgeIndex, edge) in graph.edges.enumerated() {
            guard let tail = itemOfBox[edge.source], let head = itemOfBox[edge.target], tail != head else { continue }
            let key = min(tail, head) * itemCount + max(tail, head)
            if edge.labelSize.map({ size in size.width > 0 }) ?? false || joined.contains(key) { step = 2 }
            joined.insert(key)
            written.append((tail, head, edgeIndex))
        }
        let reversed = LayeredRanking.declarationOrderCycleClosingEdges(nodeCount: itemCount, edges: written.map { edge in (edge.tail, edge.head) })
        let edges = written.enumerated().map { position, edge in
            let label = graph.edges[edge.edgeIndex].labelSize ?? .zero
            return LaneRankedEdge(tail: edge.tail, head: edge.head, minimumRankSpan: graph.edges[edge.edgeIndex].minimumRankSpan,
                                  labelAcross: runsAcross ? label.height : label.width, labelAlong: runsAcross ? label.width : label.height,
                                  isReversed: reversed[position], edgeIndex: edge.edgeIndex)
        }
        return (edges, step)
    }

    /// The lane `box` is in, keeping in its lane and at the ends the room its groups need.
    private mutating func lane(of box: Int) -> Int {
        var current = box
        var room = graph.lanePadding
        var hops = 0
        while let parent = graph.boxes[current].parent, hops < Self.maximumHops {
            current = parent
            if laneSlots[current] == nil {
                let padding = graph.boxes[current].padding
                room += max(padding.side, padding.top, padding.bottom)
            }
            hops += 1
        }
        let lane = laneSlots[current] ?? 0
        lanePaddings[lane] = max(lanePaddings[lane], room)
        endPadding = max(endPadding, room)
        return lane
    }
}
