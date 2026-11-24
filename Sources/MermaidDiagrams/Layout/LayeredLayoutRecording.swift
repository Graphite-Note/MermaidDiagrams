/**
 * File: LayeredLayoutRecording.swift
 * ----------------------------------
 * Layer: Core
 * Description: In debug builds only, the inputs of the layered layouts a test runs, kept so that it can lay each out
 *              again with the 0.7.0 layout and compare the two bit for bit.
 *
 * Authors: Bahey Shalash
 * Version: 0.2
 * Date: 24/11/2026
 */

#if DEBUG
/// What the layered layouts were given while a test set `current`: every flat graph placed through `LayeredLayout`,
/// every cluster graph placed through `LayeredClusterLayout`, every flat layout run (those of compound layouts too) and every ranking a compound layout asked for, in the order they
/// ran. Release builds have none of this.
final class LayeredLayoutRecording: @unchecked Sendable {
    // Only the thread that bound `current` (through `$current.withValue`) reaches the recording, and only while the
    // binding lasts: the lists are never read or written from two threads at once.
    @TaskLocal static var current: LayeredLayoutRecording?

    /// A flat layout's input, as `LayeredFlatLayout.layout` was called.
    struct FlatLayout {
        var nodes: [LayeredFlatNode]
        var edges: [LayeredFlatEdge]
        var options: LayeredFlatOptions
        var maximumVertexCount: Int
    }

    /// A graph placed through `LayeredLayout.place`.
    struct Placement {
        var graph: LayeredGraph
        var spacing: LayeredSpacing
        var maximumPointCount: Int
    }

    /// A cluster graph placed through `LayeredClusterLayout.place`.
    struct ClusterPlacement {
        var graph: LayeredClusterGraph
        var spacing: LayeredSpacing
        var maximumPointCount: Int
    }

    var placements: [Placement] = []
    var clusterPlacements: [ClusterPlacement] = []
    /// The routes a compound layout counted the crossings of with `LayeredRouteCrossings.count`.
    var routeCrossings: [(nodes: [LayeredCompoundNode], edges: [LayeredCompoundEdge], style: LayeredRouteStyle)] = []
    var flatLayouts: [FlatLayout] = []
    /// The nodes and edges a compound layout ranked with `LayeredFlatRanking.orient` and `rank`.
    var rankings: [(nodes: [LayeredFlatNode], edges: [LayeredFlatEdge])] = []

    init() {}
}
#endif
