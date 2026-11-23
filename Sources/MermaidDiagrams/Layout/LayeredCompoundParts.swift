/**
 * File: LayeredCompoundParts.swift
 * --------------------------------
 * Layer: Core
 * Description: The nodes, edges, levels and ports of Pele's compound layout of graphs in nested groups (compound.ts).
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 23/11/2026
 */

import CoreGraphics

/// A node or a group of Pele's compound layout, on the page (Pele's `CNode`).
struct LayeredCompoundNode: Equatable, Sendable {
    var width: Double
    var height: Double
    /// The group this node sits in, -1 for the top level.
    var parent: Int
    var isGroup = false
    /// A group's own direction, or nil for its parent's.
    var direction: LayeredDirection?
    var paddingSide: Double = 0
    var paddingTop: Double = 0
    var paddingBottom: Double = 0
    var minimumWidth: Double = 0
    /// Declaration order; a group takes the smallest of its members'.
    var sequence: Double = 0
    /// How much of a side its edges may spread along, across the flow; 0 keeps them at its middle.
    var sideSpan: Double = 0
    var x: Double = 0
    var y: Double = 0

    init(width: Double, height: Double, parent: Int = -1) {
        self.width = width
        self.height = height
        self.parent = parent
    }
}

/// A point of a compound edge's route, and whether the edge runs into it across (horizontally) rather than down.
struct LayeredRoutePoint: Equatable, Sendable {
    var point: CGPoint
    var runsHorizontally: Bool
}

/// An edge of Pele's compound layout (Pele's `CEdge`).
struct LayeredCompoundEdge: Equatable, Sendable {
    var source: Int
    var target: Int
    var minimumLength = 1
    var labelWidth: Double = 0
    var labelHeight: Double = 0
    var route: [LayeredRoutePoint] = []
    var labelCenter: CGPoint = .zero

    init(source: Int, target: Int, minimumLength: Int = 1, labelWidth: Double = 0, labelHeight: Double = 0) {
        self.source = source
        self.target = target
        self.minimumLength = minimumLength
        self.labelWidth = labelWidth
        self.labelHeight = labelHeight
    }
}

/// How the routes of a compound layout are drawn, for counting their crossings (Pele's `Style`).
enum LayeredRouteStyle: Sendable {
    case curved, stepped, linear

    init(_ options: LayeredFlatOptions) {
        self = options.runsOnTracks ? .stepped : options.isStraight ? .linear : .curved
    }
}

/// The edge an edge crossing a group's border passes through on that border (Pele's `PortEdge`).
struct LayeredCompoundPort: Sendable {
    var edgeIndex: Int
    /// The item inside the level the edge leaves or reaches.
    var inner: Int
    var isOutgoing: Bool
    var side: DiagramSide = .top
    /// Position across the flow outside the group from a previous layout; NaN if unknown.
    var hint = Double.nan
    var borderPoint: CGPoint = .zero
    var route: [LayeredRoutePoint] = []
}

/// An edge laid out in one level, between two of its items.
struct LayeredCompoundLevelEdge: Sendable {
    var edgeIndex: Int
    var first: Int
    var second: Int
}

/// One group's inside, or the top level, laid out as a graph of its own (Pele's `Level`).
struct LayeredCompoundLevel: Sendable {
    /// The group, -1 for the top level.
    var identifier: Int
    var direction: LayeredDirection
    var items: [Int] = []
    var edges: [LayeredCompoundLevelEdge] = []
    var ports: [LayeredCompoundPort] = []
    /// The port of each edge that crosses the border, by `edge * 2` leaving and `edge * 2 + 1` arriving.
    var portIndex: [Int: Int] = [:]
    var routes: [Int: [LayeredRoutePoint]] = [:]
    var origin: CGPoint = .zero

    init(identifier: Int, direction: LayeredDirection) {
        self.identifier = identifier
        self.direction = direction
    }

    func port(edge: Int, isOutgoing: Bool) -> LayeredCompoundPort? {
        portIndex[edge * 2 + (isOutgoing ? 0 : 1)].map { index in ports[index] }
    }
}

/// Pele's constants of compound.ts, with its names spelled out.
enum LayeredCompoundConstants {
    /// Past this many ports, an edge is drawn between the groups that hold its ends.
    static let maximumPorts = 40_000
    /// Repeated layouts only for small graphs.
    static let maximumOrderedPorts = 400
    static let maximumOrderedEdges = 500
    /// Crossing tolerance before trying independent group ordering.
    static let flatSlack = 1.5
    static let flatSpare: Double = 4
    /// Crossings within this distance of a shared node are not counted.
    static let fanDistance: Double = 24
    static let inLine = 0.5
    static let curvePieces = 3
    static let cornerPieces = 2
    static let stepPieces = 3
    /// The renderer's corner handles.
    static let handle = 0.62
    static let maximumInsertionSort = 128
    /// A self-loop's label sits this far beyond its node's side.
    static let loopLabelGap: Double = 28
}

extension LayeredDirection {
    var flips: Bool { self == .bottomToTop || self == .rightToLeft }
}

extension DiagramSide {
    var opposite: DiagramSide {
        switch self {
        case .top: .bottom
        case .bottom: .top
        case .left: .right
        case .right: .left
        }
    }
}
