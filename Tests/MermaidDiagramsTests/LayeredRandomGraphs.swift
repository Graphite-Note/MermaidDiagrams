/**
 * File: LayeredRandomGraphs.swift
 * -------------------------------
 * Layer: Tests
 * Description: Random flat graphs of every kind the layered layout knows, and random graphs to place, for the tests
 *              that compare the layout with the 0.7.0 reference.
 *
 * Authors: Bahey Shalash
 * Version: 0.2
 * Date: 25/11/2026
 */

import CoreGraphics
@testable import MermaidDiagrams

enum LayeredRandomGraphs {
    /// A flat graph: up to 40 nodes (a few ports with hints, pinned nodes, order keys, side spans), edges with labels,
    /// lengths, offsets and held ends, twins and edges from a node to itself, and options that turn on tracks, straight
    /// edges, twins kept apart, head room, nested groups, orders only and budgets too small to lay out.
    static func flatLayout(_ index: Int, using generator: inout LayeredEquivalenceGenerator) -> LayeredLayoutRecording.FlatLayout {
        let nodeCount = Int.random(in: 1...(index % 10 == 9 ? 40 : 14), using: &generator)
        var nodes = (0..<nodeCount).map { _ in
            LayeredFlatNode(width: Double(Int.random(in: 0...90, using: &generator)), height: Double(Int.random(in: 0...50, using: &generator)))
        }
        for node in nodes.indices {
            let draw = Int.random(in: 0..<20, using: &generator)
            if index % 4 == 2 && draw == 0 { nodes[node].kind = .startPort }
            if index % 4 == 2 && draw == 1 { nodes[node].kind = .endPort }
            if nodes[node].kind.isPort && Bool.random(using: &generator) { nodes[node].portHint = Double(Int.random(in: -50...50, using: &generator)) }
            if index % 5 == 1 && draw == 2 { nodes[node].pin = Bool.random(using: &generator) ? -1 : 1 }
            if index % 6 == 3 && draw < 16 { nodes[node].orderKey = Double(Int.random(in: 0...30, using: &generator)) }
            if index % 3 == 0 { nodes[node].sideSpan = nodes[node].width * Double(Int.random(in: 0...10, using: &generator)) / 10 }
        }
        let edges = randomEdges(index, nodeCount: nodeCount, spreads: index % 3 == 0, using: &generator)
        return LayeredLayoutRecording.FlatLayout(nodes: nodes, edges: edges, options: randomOptions(index, nodeCount: nodeCount, using: &generator),
                                                 maximumVertexCount: index % 23 == 7 ? nodeCount + Int.random(in: 0...3, using: &generator) : .max)
    }

    private static func randomEdges(_ index: Int, nodeCount: Int, spreads: Bool, using generator: inout LayeredEquivalenceGenerator) -> [LayeredFlatEdge] {
        var edges: [LayeredFlatEdge] = []
        for _ in 0..<Int.random(in: 0...(2 * nodeCount + 2), using: &generator) where nodeCount > 1 {
            let tail = Int.random(in: 0..<nodeCount, using: &generator)
            var head = Int.random(in: 0..<nodeCount, using: &generator)
            if head == tail && Int.random(in: 0..<8, using: &generator) != 0 { head = (tail + 1) % nodeCount }
            let isLabelled = index % 4 == 1 && Bool.random(using: &generator)
            var edge = LayeredFlatEdge(tail: tail, head: head, minimumLength: Int.random(in: 0...3, using: &generator),
                                       labelWidth: isLabelled ? Double(Int.random(in: 10...40, using: &generator)) : 0,
                                       labelHeight: isLabelled ? 14 : 0)
            if index % 5 == 2 {
                edge.tailOffset = Double(Int.random(in: -8...8, using: &generator))
                edge.headOffset = Double(Int.random(in: -8...8, using: &generator))
            }
            if spreads {
                edge.isHeadHeld = Int.random(in: 0..<3, using: &generator) == 0
                edge.isTailHeld = Int.random(in: 0..<4, using: &generator) == 0
            }
            edges.append(edge)
            if Int.random(in: 0..<6, using: &generator) == 0 { edges.append(LayeredFlatEdge(tail: tail, head: head)) }
        }
        return edges
    }

    private static func randomOptions(_ index: Int, nodeCount: Int, using generator: inout LayeredEquivalenceGenerator) -> LayeredFlatOptions {
        var options = LayeredCompoundTesting.options
        options.runsOnTracks = index % 6 == 4
        options.isStraight = index % 7 == 5
        options.keepsTwinsApart = index % 9 == 2
        options.headRoom = index % 2 == 0 ? 8 : 0
        if index % 8 == 3 {
            options.parentOfGroup = [-1, 0, 1, -1]
            options.groupOfNode = (0..<nodeCount).map { _ in Int.random(in: -1...3, using: &generator) }
            options.ordersOnly = index % 16 == 3
        }
        return options
    }

    /// A graph to place on the flat layout, with side spans, offsets and labels, and each routing.
    static func placement(_ index: Int, using generator: inout LayeredEquivalenceGenerator) -> LayeredPlacementInput {
        let nodeCount = Int.random(in: 1...16, using: &generator)
        let sizes = (0..<nodeCount).map { _ in
            LayeredSize(across: CGFloat(Int.random(in: 10...90, using: &generator)), along: CGFloat(Int.random(in: 10...40, using: &generator)))
        }
        var edges: [LayeredEdge] = []
        for _ in 0..<Int.random(in: 0...(2 * nodeCount), using: &generator) where nodeCount > 1 {
            let source = Int.random(in: 0..<nodeCount, using: &generator)
            let target = (source + Int.random(in: 1..<nodeCount, using: &generator)) % nodeCount
            let label = index % 3 == 1 && Bool.random(using: &generator) ? LayeredSize(across: 30, along: 14) : nil
            edges.append(LayeredEdge(source: source, target: target, minimumRankSpan: Int.random(in: 1...2, using: &generator), labelSize: label,
                                     sourceOffset: index % 4 == 2 ? CGFloat(Int.random(in: -6...6, using: &generator)) : 0,
                                     targetOffset: index % 4 == 2 ? CGFloat(Int.random(in: -6...6, using: &generator)) : 0))
        }
        let spans = index % 2 == 0 ? sizes.map { size in size.across * 0.7 } : []
        var spacing = LayeredSpacing(nodeSeparation: 50, edgeSeparation: 20, rankSeparation: 50, borderSeparation: index % 5 == 0 ? 30 : nil)
        spacing.routing.runsOnTracks = index % 6 == 1
        spacing.routing.isStraight = index % 7 == 3
        spacing.routing.keepsTwinsApart = index % 5 == 4
        spacing.routing.headRoom = 8
        return LayeredPlacementInput(graph: LayeredGraph(nodeSizes: sizes, edges: edges, nodeSideSpans: spans), spacing: spacing,
                                     maximumPointCount: index % 17 == 5 ? nodeCount + 1 : 50_000)
    }
}
