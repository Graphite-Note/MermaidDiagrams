/**
 * File: LayeredGraph.swift
 * ------------------------
 * Layer: Core
 * Description: A graph to lay out in ranks, the gaps and routing its layout keeps, and where the layout put everything.
 *
 * Authors: Félix Chevalier, Bahey Shalash
 * Version: 0.2
 * Date: 23/11/2026
 */

import CoreGraphics

/// A graph to lay out in ranks, in flow space: `across` is the axis the nodes of one rank are spread along, `along`
/// the axis ranks follow each other on. A top-to-bottom diagram has `across` horizontal; a left-to-right one vertical.
struct LayeredGraph {
    var nodeSizes: [LayeredSize]
    var edges: [LayeredEdge]
    /// How much of the sides edges meet each node shares out between them, across the flow (Pele's `span`); empty, or
    /// 0 for a node, keeps every end at the middle of its side.
    var nodeSideSpans: [CGFloat] = []
}

/// An extent in flow space.
struct LayeredSize: Equatable {
    var across: CGFloat
    var along: CGFloat
}

/// An edge between two different nodes. Edges from a node to itself are laid out beside the node, not in ranks.
struct LayeredEdge: Equatable {
    var source: Int
    var target: Int
    /// The fewest ranks the edge spans, at least 1.
    var minimumRankSpan: Int
    /// The extent of the edge's text, which takes a place of its own between the ranks, or nil.
    var labelSize: LayeredSize?
    /// How far across from its source's center the edge leaves, where it is held at a point of a box's side: the
    /// layout places the source so that this point, not its center, lines up with the edge. 0 for the center.
    var sourceOffset: CGFloat = 0
    /// How far across from its target's center the edge arrives.
    var targetOffset: CGFloat = 0
}

/// The gaps the layout keeps.
struct LayeredSpacing: Equatable {
    /// Between two nodes of one rank.
    var nodeSeparation: CGFloat
    /// Between an edge passing through a rank and its neighbours there.
    var edgeSeparation: CGFloat
    /// Between two ranks of nodes.
    var rankSeparation: CGFloat
    /// Between a rank of border points and the rank next to it, or nil for the rank separation.
    var borderSeparation: CGFloat?
    var routing = LayeredRouting()
}

/// How the layout routes edges across the gaps between ranks (Pele's `tracks`, `straight`, `apart` and `headRoom`).
struct LayeredRouting: Equatable {
    /// At right angles, each on a track of its own across a gap.
    var runsOnTracks = false
    /// Straight from point to point.
    var isStraight = false
    /// The caller sets the ends of edges on one side of a node apart itself, so twin edges need no bend.
    var keepsTwinsApart = false
    /// The room the marker at an edge's head takes.
    var headRoom: CGFloat = 0
}

/// Where the layout put everything, in flow space, with the smallest `across` and `along` at 0.
struct LayeredPlacement: Equatable {
    var nodeCenters: [CGPoint]
    /// For each edge, the points it passes through from its source's center to its target's center, both included,
    /// in the edge's own direction even where the layout turned it around to break a cycle.
    var edgeRoutes: [[CGPoint]]
    /// For each edge, the center of its text's place, or nil.
    var edgeLabelCenters: [CGPoint?]
    /// For each edge, the route as Pele draws it, from the side of its source, where its end was spread or settled, to
    /// the side of its target, in the edge's own direction.
    var edgePaths: [[CGPoint]] = []
    /// `x` is the extent across, `y` along.
    var extent: CGSize
}
