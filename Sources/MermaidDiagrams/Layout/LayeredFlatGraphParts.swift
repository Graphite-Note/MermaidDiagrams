/**
 * File: LayeredFlatGraphParts.swift
 * ---------------------------------
 * Layer: Core
 * Description: The nodes, edges, options and result of Pele's layered layout of one flat graph (layout/layered.ts).
 *
 * Authors: Bahey Shalash
 * Version: 0.2
 * Date: 24/11/2026
 */

import CoreGraphics

/// What a vertex of the layered layout is: a node of the graph, a bend of an edge in a rank it passes, the place of an
/// edge's label, or a point of the border of a box an edge crosses (Pele's `Kind`).
enum LayeredVertexKind: UInt8, Equatable, Sendable {
    case node, bend, label, startPort, endPort

    /// A bend or a label: a point an edge passes through.
    var isPassingPoint: Bool { self == .bend || self == .label }
    var isPort: Bool { self == .startPort || self == .endPort }
}

/// A node of a flat layered graph, in flow space: `width` across the flow, `height` along it (Pele's `LNode`).
struct LayeredFlatNode: Equatable, Sendable {
    var width: Double
    var height: Double
    var kind: LayeredVertexKind = .node
    /// -1 first in its rank, 1 last, 0 free.
    var pin = 0
    /// A port's position across the flow outside its box, or NaN: a rank of ports that all have one keeps their order.
    var portHint = Double.nan
    /// The position across the flow to start from, or NaN: used where every vertex of a rank has one.
    var orderKey = Double.nan
    /// How much of the sides edges meet may be shared out between them; 0 keeps every end at the middle.
    var sideSpan: Double = 0
    var x: Double = 0
    var y: Double = 0
    var rank = 0

    init(width: Double, height: Double, kind: LayeredVertexKind = .node) {
        self.width = width
        self.height = height
        self.kind = kind
    }
}

/// An edge of a flat layered graph between two different nodes (Pele's `LEdge`).
struct LayeredFlatEdge: Equatable, Sendable {
    var tail: Int
    var head: Int
    var minimumLength = 1
    var labelWidth: Double = 0
    var labelHeight: Double = 0
    /// How far across from the middle of its node each end meets it.
    var tailOffset: Double = 0
    var headOffset: Double = 0
    /// An end held where its offset puts it, which takes no part in sharing out its node's side.
    var isTailHeld = false
    var isHeadHeld = false
    var isReversed = false
    /// The route from the tail's side to the head's, in flow space; with `ordersOnly`, (rank, position across) pairs.
    var points: [CGPoint] = []
    var labelCenter: CGPoint = .zero

    init(tail: Int, head: Int, minimumLength: Int = 1, labelWidth: Double = 0, labelHeight: Double = 0) {
        self.tail = tail
        self.head = head
        self.minimumLength = minimumLength
        self.labelWidth = labelWidth
        self.labelHeight = labelHeight
    }
}

/// An edge as the flat layout works on it, in a scratch span: `LayeredFlatEdge` with its route a run of the layout's one
/// list of points instead of a list of its own, so that it is a plain value.
struct LayeredSpanEdge {
    var tail: Int
    var head: Int
    var minimumLength: Int
    var labelWidth: Double
    var labelHeight: Double
    var tailOffset: Double
    var headOffset: Double
    var isTailHeld: Bool
    var isHeadHeld: Bool
    var isReversed: Bool
    var labelCenter: CGPoint
    /// Where the edge's route starts in the layout's points, and how many points it has; -1 until it is written.
    var pointStart = -1
    var pointCount = 0

    /// `edge` without its points.
    init(_ edge: LayeredFlatEdge) {
        tail = edge.tail
        head = edge.head
        minimumLength = edge.minimumLength
        labelWidth = edge.labelWidth
        labelHeight = edge.labelHeight
        tailOffset = edge.tailOffset
        headOffset = edge.headOffset
        isTailHeld = edge.isTailHeld
        isHeadHeld = edge.isHeadHeld
        isReversed = edge.isReversed
        labelCenter = edge.labelCenter
    }

    /// An edge of a graph to place, its ends held nowhere.
    init(tail: Int, head: Int, minimumLength: Int, labelWidth: Double, labelHeight: Double, tailOffset: Double, headOffset: Double) {
        self.tail = tail
        self.head = head
        self.minimumLength = minimumLength
        self.labelWidth = labelWidth
        self.labelHeight = labelHeight
        self.tailOffset = tailOffset
        self.headOffset = headOffset
        isTailHeld = false
        isHeadHeld = false
        isReversed = false
        labelCenter = .zero
    }
}

/// How a layered layout spaces and routes its graph (Pele's `LayeredOptions`).
struct LayeredFlatOptions: Equatable, Sendable {
    var nodeSeparation: Double
    var edgeSeparation: Double
    var rankSeparation: Double
    /// Between a rank of border ports and the rank next to it.
    var portSeparation: Double
    /// Edges run at right angles, each on a track of its own across a gap.
    var runsOnTracks = false
    /// Every edge drawn straight from point to point.
    var isStraight = false
    /// The caller sets the ends on one side of a node apart itself, so twin edges need no bend.
    var keepsTwinsApart = false
    /// The room the marker at an edge's head takes.
    var headRoom: Double = 0
    /// Each group kept contiguous within ranks: the group of each node and the parent of each group, -1 for none.
    var groupOfNode: [Int]?
    var parentOfGroup: [Int] = []
    /// Only the positions across the flow are computed (`x`), with the crossings in the result.
    var ordersOnly = false
}

/// The size of a laid-out graph, and with `ordersOnly` its crossings after and before ordering.
struct LayeredFlatResult: Equatable, Sendable {
    var width: Double
    var height: Double
    var crossings = 0
    var declaredCrossings = 0
}

/// Pele's constants of layered.ts, with its names spelled out.
enum LayeredFlatConstants {
    static let maximumSweeps = 24
    /// Past this many bends, the longest edges are drawn as one direct curve instead.
    static let maximumBends = 20_000
    static let portPitch: Double = 16
    static let minimumPitch: Double = 8
    static let minimumSlope = 0.125
    static let maximumGapFactor: Double = 3
    static let trackMargin: Double = 18
    static let trackPitch: Double = 10
    static let trackSpread: Double = 14
    static let levelWideFactor: Double = 2
    static let levelMargin: Double = 28
    static let levelPitch: Double = 12
    static let levelLead: Double = 12
    static let levelClear: Double = 8
    static let levelTouch: Double = 4
    static let crossedSlope = 0.5
    static let inLine = 0.5
    static let twinDistance: Double = 1
    static let nodeSnap: Double = 12
    static let bendSnap: Double = 24
    static let leanClear: Double = 40
    static let maximumWeighedPieces = 400
    static let curveSamples = 16
    /// Graphs of at most this many vertices are ordered twice and tried mirrored.
    static let smallGraphVertexCount = 600
}

/// What an end of a segment is to the node it meets, for the ends that may move along its side (Pele's `End`).
enum LayeredSegmentEnd: UInt8, Sendable {
    case held, leaves, arrives
}
