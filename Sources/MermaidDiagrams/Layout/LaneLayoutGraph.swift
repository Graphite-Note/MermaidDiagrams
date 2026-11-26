/**
 * File: LaneLayoutGraph.swift
 * ---------------------------
 * Layer: Core
 * Description: What the lane layout lays out (boxes, some of them groups, and edges between them), as lists or as spans
 *              of the thread's scratch arena, and where it puts them.
 *
 * Authors: Bahey Shalash
 * Version: 0.2
 * Date: 26/11/2026
 */

import CoreGraphics

/// A graph to lay out in lanes (`LaneLayout`), on the page: boxes of a size, each inside the group its `parent` names;
/// the groups at the top level are the lanes. The boxes come in the order of Pele's graph, which the layout's ties follow:
/// a lane is placed in the order of its index from the last box to the first, and the boxes that are ranked in the order of
/// their indexes.
struct LaneLayoutGraph {
    var boxes: [LaneLayoutBox]
    var edges: [LaneLayoutEdge]
    var direction: LayeredDirection
    /// The room a lane keeps around its boxes: Pele's 24 points, 12 in a tight layout.
    var lanePadding: CGFloat = 24

    /// The graph's boxes and edges copied into spans of `arena`, as the lane layout reads them.
    func spans(in arena: DiagramScratchArena) -> LaneLayoutSpanGraph {
        LaneLayoutSpanGraph(boxes: LaneLayoutItems.copied(boxes, arena: arena), edges: LaneLayoutItems.copied(edges, arena: arena), direction: direction,
                            lanePadding: lanePadding)
    }
}

/// A graph to lay out in lanes whose boxes and edges are spans of the calling thread's scratch arena: what a host that
/// builds its graph in the arena (`SwimlaneGraph`) hands the layout, with no list of its own.
struct LaneLayoutSpanGraph {
    let boxes: ScratchSpan<LaneLayoutBox>
    let edges: ScratchSpan<LaneLayoutEdge>
    let direction: LayeredDirection
    let lanePadding: CGFloat
}

/// A box: a node of its size, or a group whose size the layout gives it around what it holds. A group that holds nothing
/// is laid out as a node of its size, which is none.
struct LaneLayoutBox {
    var size: CGSize
    var parent: Int?
    var isGroup: Bool
    /// A group's room inside its box, on its sides, above (the band of its title) and below; zero for a node.
    var padding = LayeredClusterPadding(side: 0, top: 0, bottom: 0)
    /// The least width of a group's box, for its title.
    var minimumWidth: CGFloat = 0
}

/// An edge from one box to another, or to itself; an edge to or from a group that holds boxes runs straight to its border.
struct LaneLayoutEdge {
    var source: Int
    var target: Int
    var minimumRankSpan: Int
    /// The room the edge's text takes, on the page, or nil for an edge without text.
    var labelSize: CGSize?
}

/// Where the lane layout put everything, on the page, from the origin.
struct LaneLayoutPlacement {
    var size: CGSize
    /// Each box's frame: a node's at its place, a group's around what it holds, a lane's the length of the diagram.
    var frames: [CGRect]
    /// How deep the band of the lanes' titles is, at their start along the flow.
    var laneTitleDepth: CGFloat
    /// The lanes, by box, in the order they are placed across the flow.
    var lanes: [Int]
    /// For each edge, the points it passes from where it leaves its source's box to where it reaches its target's, and for
    /// each segment between two of them whether it runs along a vertical flow; nil for an edge from a box to itself.
    var routes: [LaneLayoutRoute?]
    /// For each edge, the center of its text.
    var labelCenters: [CGPoint]
}

struct LaneLayoutRoute: Equatable {
    var points: [CGPoint]
    /// One per segment: whether its S leaves and arrives up or down the page.
    var segmentsRunVertically: [Bool]
}
