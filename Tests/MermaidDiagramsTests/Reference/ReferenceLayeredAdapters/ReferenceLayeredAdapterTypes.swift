/**
 * File: ReferenceLayeredAdapterTypes.swift
 * ----------------------------------------
 * Layer: Tests
 * Description: The 0.7.0 inputs and placements of the layered and cluster layouts' adapters, which 0.8.0 no longer has,
 *              kept for the frozen 0.7.0 references that are written with them and the tests that compare them.
 *
 * Authors: Félix Chevalier, Bahey Shalash
 * Version: 0.1
 * Date: 25/11/2026
 */

import CoreGraphics
@testable import MermaidDiagrams

/// A graph to lay out in ranks, in flow space: `across` is the axis the nodes of one rank are spread along, `along`
/// the axis ranks follow each other on. A top-to-bottom diagram has `across` horizontal; a left-to-right one vertical.
struct LayeredGraph {
    var nodeSizes: [LayeredSize]
    var edges: [LayeredEdge]
    /// How much of the sides edges meet each node shares out between them, across the flow (Pele's `span`); empty, or
    /// 0 for a node, keeps every end at the middle of its side.
    var nodeSideSpans: [CGFloat] = []
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

/// A graph whose nodes may sit in nested boxes, clusters, to lay out in ranks on a page whose y runs down: each box is
/// laid out on its own, in its own direction, then placed in the box around it as one node, as Pele lays out a
/// flowchart's subgraphs (`LayeredClusterLayout`).
struct LayeredClusterGraph {
    /// Each node's size on the page.
    var nodeSizes: [CGSize]
    /// How much of the sides edges meet each node shares out between them, across the flow; empty, or 0 for a node,
    /// keeps every end at the middle of its side.
    var nodeSideSpans: [CGFloat] = []
    /// The cluster each node sits directly in, or nil for the top level.
    var nodeClusters: [Int?]
    var clusters: [LayeredCluster]
    /// Edges between two different ends. An edge from a node to itself is drawn beside it and is not laid out here.
    var edges: [LayeredClusterEdge]
    /// The direction of the top level.
    var direction: LayeredDirection
}

/// A box around some nodes and clusters.
struct LayeredCluster: Equatable {
    /// The cluster this one sits directly in, or nil for the top level.
    var parent: Int?
    /// The direction inside the box, or nil for that of the box around it.
    var direction: LayeredDirection?
    var padding: LayeredClusterPadding
    /// The narrowest the box is, so that its title fits.
    var minimumWidth: CGFloat
    /// The cluster's place in the declaration order among the nodes, whose places are their indices; nil for after
    /// every node. A cluster with members takes its first member's.
    var sequence: CGFloat?
    /// How much of the box's sides its edges share out, beyond its padding; 0 keeps them at its middles.
    var sideSpan: CGFloat = 0

    init(parent: Int?, direction: LayeredDirection?, padding: LayeredClusterPadding, minimumWidth: CGFloat,
         sequence: CGFloat? = nil, sideSpan: CGFloat = 0) {
        self.parent = parent
        self.direction = direction
        self.padding = padding
        self.minimumWidth = minimumWidth
        self.sequence = sequence
        self.sideSpan = sideSpan
    }
}

/// What an edge of a cluster graph starts or ends at: a node, or a box itself.
enum LayeredClusterEnd: Equatable {
    case node(Int)
    case cluster(Int)
}

struct LayeredClusterEdge: Equatable {
    var source: LayeredClusterEnd
    var target: LayeredClusterEnd
    /// The fewest ranks the edge spans, at least 1, in the box where its ends meet.
    var minimumRankSpan: Int
    /// The size of the edge's text on the page, which takes a place of its own between the ranks, or nil.
    var labelSize: CGSize?
}

/// Where a cluster layout put everything on the page, the top left corner at 0.
struct LayeredClusterPlacement: Equatable {
    var nodeCenters: [CGPoint]
    var clusterFrames: [CGRect]
    /// By edge.
    var edgeRoutes: [LayeredClusterRoute]
    /// By edge, the center of its text's place, or nil.
    var edgeLabelCenters: [CGPoint?]
    var size: CGSize
    /// The edges between a box and something inside it (or a box and itself), whose routes run straight from one end's
    /// center to the other's, as Pele's compound layout draws them.
    var strayEdgeIndices: Set<Int> = []
}

/// An edge's way across the page, in the edge's own direction, as Pele's compound layout routes it: from the side of
/// its source (a node's, or a box's where the edge starts at the box itself) to the side of its target, through every
/// point it passes, where it crosses a box's border included; between a box and what it holds, from one center to the
/// other.
struct LayeredClusterRoute: Equatable {
    var points: [CGPoint]
    /// For each segment between two points, whether the flow it follows runs vertically: the way its S curve leaves
    /// and arrives.
    var segmentsRunVertically: [Bool]

    static let empty = LayeredClusterRoute(points: [], segmentsRunVertically: [])
}

/// Why a cluster graph was not laid out.
enum LayeredClusterLayoutError: Error, Equatable {
    /// The nodes and passing points of the boxes would be more than the limit.
    case tooManyPoints
}
