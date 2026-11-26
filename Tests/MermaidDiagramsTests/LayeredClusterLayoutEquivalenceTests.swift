/**
 * File: LayeredClusterLayoutEquivalenceTests.swift
 * ------------------------------------------------
 * Layer: Tests
 * Description: Every compound graph the corpora lay out, and random cluster graphs with nested clusters in every
 *              direction, get to the bit the layout and placement the 0.7.0 compound layout gives them.
 *
 * Authors: Bahey Shalash
 * Version: 0.2
 * Date: 25/11/2026
 */

import CoreGraphics
import XCTest
@testable import MermaidDiagrams

final class LayeredClusterLayoutEquivalenceTests: XCTestCase {
    /// Every compound graph of every corpus (flowcharts and agent flows with subgraphs, state diagrams with composites,
    /// class diagrams with namespaces, ER diagrams with groups and use case diagrams with boundaries, regular and narrow),
    /// as each diagram's layout wrote it into the compound layout's spans, laid out by the layout and by the 0.7.0
    /// reference: every node's place and size, every edge's route and text's center, the size, alike to the bit.
    func testEveryCompoundLayoutOfTheCorporaMatchesTheReferenceBitForBit() throws {
        let recording = try LayeredCorpusRecording.shared()
        XCTAssertGreaterThan(recording.compoundLayouts.filter { input in input.nodes.contains { node in node.isGroup } }.count, 100)
        var mismatches = 0
        for (index, input) in recording.compoundLayouts.enumerated()
        where LayeredCompoundOutcome(input, isReference: false) != LayeredCompoundOutcome(input, isReference: true) {
            mismatches += 1
            if mismatches <= 5 { XCTFail("compound layout \(index) (\(input.nodes.count) nodes, \(input.edges.count) edges) differs") }
        }
        XCTAssertEqual(mismatches, 0)
    }

    /// Random cluster graphs: nested clusters with their own directions, paddings, widths, sequences and side spans,
    /// edges between nodes and clusters, inside and across them, loops and labels, each routing, budgets too small.
    func testRandomClusterGraphsMatchTheReferenceBitForBit() {
        var generator = LayeredEquivalenceGenerator(seed: 0xC1A5_7E25)
        for index in 0..<250 {
            let input = Self.randomInput(index, using: &generator)
            XCTAssertEqual(Self.placed(input), Self.referencePlaced(input), "random cluster graph \(index)")
        }
    }

    private static func placed(_ input: LayeredClusterPlacementInput) -> LayeredClusterPlacementBits {
        LayeredClusterPlacementBits { () throws(LayeredClusterLayoutError) in try LayeredSpanPlacement.placeClusters(input) }
    }

    private static func referencePlaced(_ input: LayeredClusterPlacementInput) -> LayeredClusterPlacementBits {
        LayeredClusterPlacementBits { () throws(LayeredClusterLayoutError) in
            try ReferenceLayeredClusterLayout.place(input.graph, spacing: input.spacing, maximumPointCount: input.maximumPointCount)
        }
    }

    private static func randomInput(_ index: Int, using generator: inout LayeredEquivalenceGenerator) -> LayeredClusterPlacementInput {
        let directions: [LayeredDirection] = [.topToBottom, .bottomToTop, .leftToRight, .rightToLeft]
        let nodeCount = Int.random(in: 1...12, using: &generator)
        let clusterCount = Int.random(in: 0...4, using: &generator)
        var clusters: [LayeredCluster] = []
        for cluster in 0..<clusterCount {
            let parent = cluster > 0 && Bool.random(using: &generator) ? Int.random(in: 0..<cluster, using: &generator) : nil
            let direction = Int.random(in: 0..<3, using: &generator) == 0 ? directions.randomElement(using: &generator) : nil
            let padding = LayeredClusterPadding(side: CGFloat(Int.random(in: 0...12, using: &generator)), top: CGFloat(Int.random(in: 0...30, using: &generator)),
                                                bottom: CGFloat(Int.random(in: 0...8, using: &generator)))
            clusters.append(LayeredCluster(parent: parent, direction: direction, padding: padding, minimumWidth: CGFloat(Int.random(in: 0...120, using: &generator)),
                                           sequence: Bool.random(using: &generator) ? CGFloat(Int.random(in: 0...20, using: &generator)) : nil,
                                           sideSpan: CGFloat(Int.random(in: 0...40, using: &generator))))
        }
        let sizes = (0..<nodeCount).map { _ in CGSize(width: Int.random(in: 10...90, using: &generator), height: Int.random(in: 10...40, using: &generator)) }
        let nodeClusters: [Int?] = (0..<nodeCount).map { _ in clusterCount > 0 && Bool.random(using: &generator) ? Int.random(in: 0..<clusterCount, using: &generator) : nil }
        func end() -> LayeredClusterEnd {
            clusterCount > 0 && Int.random(in: 0..<5, using: &generator) == 0 ? .cluster(Int.random(in: 0..<clusterCount, using: &generator))
                : .node(Int.random(in: 0..<nodeCount, using: &generator))
        }
        var edges: [LayeredClusterEdge] = []
        for _ in 0..<Int.random(in: 0...(2 * nodeCount), using: &generator) {
            let label = Int.random(in: 0..<3, using: &generator) == 0 ? CGSize(width: Int.random(in: 10...40, using: &generator), height: 14) : nil
            edges.append(LayeredClusterEdge(source: end(), target: end(), minimumRankSpan: Int.random(in: 1...2, using: &generator), labelSize: label))
        }
        let spans = index % 2 == 0 ? sizes.map { size in size.width * 0.6 } : []
        let graph = LayeredClusterGraph(nodeSizes: sizes, nodeSideSpans: spans, nodeClusters: nodeClusters, clusters: clusters, edges: edges,
                                        direction: directions[index % 4])
        var spacing = LayeredSpacing(nodeSeparation: 40, edgeSeparation: 16, rankSeparation: 48, borderSeparation: index % 3 == 0 ? 20 : nil)
        spacing.routing.runsOnTracks = index % 5 == 1
        spacing.routing.isStraight = index % 7 == 3
        spacing.routing.keepsTwinsApart = index % 6 == 2
        return LayeredClusterPlacementInput(graph: graph, spacing: spacing, maximumPointCount: index % 17 == 4 ? nodeCount + 2 : 50_000)
    }
}

/// Every number a compound layout gives back, as bit patterns, so that -0 and 0 differ and NaN equals NaN: each node's
/// place and size, each edge's text's center and route, the size, or nothing for a refused layout.
struct LayeredCompoundOutcome: Equatable {
    var bits: [UInt64]?

    init(_ input: LayeredLayoutRecording.CompoundLayout, isReference: Bool) {
        var nodes = input.nodes
        var edges = input.edges
        let size = isReference
            ? ReferenceLayeredCompoundLayout.layout(nodes: &nodes, edges: &edges, rootDirection: input.rootDirection, options: input.options,
                                                    maximumVertexCount: input.maximumVertexCount)
            : LayeredCompoundLayout.layout(nodes: &nodes, edges: &edges, rootDirection: input.rootDirection, options: input.options,
                                           maximumVertexCount: input.maximumVertexCount)
        guard let size else { return }
        var bits = [size.width.bitPattern, size.height.bitPattern]
        for node in nodes { bits += [node.x.bitPattern, node.y.bitPattern, node.width.bitPattern, node.height.bitPattern] }
        for edge in edges {
            bits += [Double(edge.labelCenter.x).bitPattern, Double(edge.labelCenter.y).bitPattern, UInt64(edge.route.count)]
            for point in edge.route { bits += [Double(point.point.x).bitPattern, Double(point.point.y).bitPattern, point.runsHorizontally ? 1 : 0] }
        }
        self.bits = bits
    }
}
