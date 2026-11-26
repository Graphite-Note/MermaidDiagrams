/**
 * File: LayeredSpacing.swift
 * --------------------------
 * Layer: Core
 * Description: The gaps and routing a layered layout keeps, extents in flow space, and the flat layout's options they
 *              make.
 *
 * Authors: Félix Chevalier, Bahey Shalash
 * Version: 0.3
 * Date: 25/11/2026
 */

import CoreGraphics

/// An extent in flow space: `across` is the axis the nodes of one rank are spread along, `along` the axis ranks follow
/// each other on. A top-to-bottom diagram has `across` horizontal; a left-to-right one vertical.
struct LayeredSize: Equatable {
    var across: CGFloat
    var along: CGFloat
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

extension LayeredFlatOptions {
    /// Pele's options for `spacing`.
    init(_ spacing: LayeredSpacing) {
        self.init(nodeSeparation: Double(spacing.nodeSeparation), edgeSeparation: Double(spacing.edgeSeparation),
                  rankSeparation: Double(spacing.rankSeparation), portSeparation: Double(spacing.borderSeparation ?? spacing.rankSeparation))
        runsOnTracks = spacing.routing.runsOnTracks
        isStraight = spacing.routing.isStraight
        keepsTwinsApart = spacing.routing.keepsTwinsApart
        headRoom = Double(spacing.routing.headRoom)
    }
}
