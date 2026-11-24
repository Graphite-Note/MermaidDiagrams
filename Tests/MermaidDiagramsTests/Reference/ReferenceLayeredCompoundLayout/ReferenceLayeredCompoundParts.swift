/**
 * File: ReferenceLayeredCompoundParts.swift
 * -----------------------------------------
 * Layer: Tests
 * Description: The 0.7.0 compound layout's levels, ports and level edges kept as the reference the arena compound
 *              layout is checked against: arrays and dictionaries per level, as 0.7.0 kept them.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 24/11/2026
 */

import CoreGraphics
@testable import MermaidDiagrams

/// The edge an edge crossing a group's border passes through on that border (Pele's `PortEdge`).
struct ReferenceLayeredCompoundPort: Sendable {
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
struct ReferenceLayeredCompoundLevelEdge: Sendable {
    var edgeIndex: Int
    var first: Int
    var second: Int
}

/// One group's inside, or the top level, laid out as a graph of its own (Pele's `Level`).
struct ReferenceLayeredCompoundLevel: Sendable {
    /// The group, -1 for the top level.
    var identifier: Int
    var direction: LayeredDirection
    var items: [Int] = []
    var edges: [ReferenceLayeredCompoundLevelEdge] = []
    var ports: [ReferenceLayeredCompoundPort] = []
    /// The port of each edge that crosses the border, by `edge * 2` leaving and `edge * 2 + 1` arriving.
    var portIndex: [Int: Int] = [:]
    var routes: [Int: [LayeredRoutePoint]] = [:]
    var origin: CGPoint = .zero

    init(identifier: Int, direction: LayeredDirection) {
        self.identifier = identifier
        self.direction = direction
    }

    func port(edge: Int, isOutgoing: Bool) -> ReferenceLayeredCompoundPort? {
        portIndex[edge * 2 + (isOutgoing ? 0 : 1)].map { index in ports[index] }
    }
}
