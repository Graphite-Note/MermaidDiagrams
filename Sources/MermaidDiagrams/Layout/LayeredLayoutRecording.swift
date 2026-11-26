/**
 * File: LayeredLayoutRecording.swift
 * ----------------------------------
 * Layer: Core
 * Description: In debug builds only, the inputs of the layered layouts a test runs, kept so that it can lay each out
 *              again with the 0.7.0 layout and compare the two bit for bit.
 *
 * Authors: Bahey Shalash
 * Version: 0.3
 * Date: 25/11/2026
 */

#if DEBUG
/// What the layered layouts were given while a test set `current`: every flat graph a diagram's ranked layout handed the
/// flat layout, every compound layout run, every flat layout run (those of compound layouts too) and every ranking a
/// compound layout asked for, in the order they ran. Release builds have none of this.
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

    /// The flat graph of a diagram without groups, as its ranked layout wrote it into the flat layout's spans.
    struct Placement {
        var nodes: [LayeredFlatNode]
        var edges: [LayeredSpanEdge]
        var spacing: LayeredSpacing
        var maximumPointCount: Int
    }

    /// A compound layout's input, as `LayeredCompoundLayout.layout` was called.
    struct CompoundLayout {
        var nodes: [LayeredCompoundNode]
        var edges: [LayeredCompoundEdge]
        var rootDirection: LayeredDirection
        var options: LayeredFlatOptions
        var maximumVertexCount: Int
    }

    var placements: [Placement] = []
    var compoundLayouts: [CompoundLayout] = []
    /// The routes a compound layout counted the crossings of with `LayeredRouteCrossings.count`.
    var routeCrossings: [(nodes: [LayeredCompoundNode], edges: [LayeredCompoundEdge], style: LayeredRouteStyle)] = []
    var flatLayouts: [FlatLayout] = []
    /// The nodes and edges a compound layout ranked with `LayeredFlatRanking.orient` and `rank`.
    var rankings: [(nodes: [LayeredFlatNode], edges: [LayeredFlatEdge])] = []

    init() {}

    /// Records the flat graph a ranked layout is about to lay out, when a test is recording.
    static func recordPlacement(nodes: ScratchSpan<LayeredFlatNode>, edges: ScratchSpan<LayeredSpanEdge>, spacing: LayeredSpacing,
                                maximumPointCount: Int) {
        current?.placements.append(Placement(nodes: Array(nodes), edges: Array(edges), spacing: spacing, maximumPointCount: maximumPointCount))
    }
}
#endif
