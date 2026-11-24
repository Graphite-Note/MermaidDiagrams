/**
 * File: LayeredClusterLayoutEquivalenceTests.swift
 * ------------------------------------------------
 * Layer: Tests
 * Description: Every cluster graph the corpora place, and random cluster graphs with nested clusters in every direction,
 *              get to the bit the placement the 0.7.0 compound layout gives them.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 24/11/2026
 */

import CoreGraphics
import XCTest
@testable import MermaidDiagrams

final class LayeredClusterLayoutEquivalenceTests: XCTestCase {
    /// Every cluster graph of every corpus (flowcharts with subgraphs, state, class, ER and use case diagrams, regular
    /// and narrow), placed by the layout and by the 0.7.0 reference, alike to the bit.
    func testEveryClusterPlacementOfTheCorporaMatchesTheReferenceBitForBit() throws {
        let recording = try LayeredCorpusRecording.shared()
        XCTAssertGreaterThan(recording.clusterPlacements.filter { input in !input.graph.clusters.isEmpty }.count, 100)
        var mismatches = 0
        for (index, input) in recording.clusterPlacements.enumerated() where Self.placed(input) != Self.referencePlaced(input) {
            mismatches += 1
            if mismatches <= 5 { XCTFail("cluster placement \(index) (\(input.graph.nodeSizes.count) nodes, \(input.graph.clusters.count) clusters) differs") }
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

    private static func placed(_ input: LayeredLayoutRecording.ClusterPlacement) -> LayeredClusterPlacementBits {
        LayeredClusterPlacementBits { () throws(LayeredClusterLayoutError) in
            try LayeredClusterLayout.place(input.graph, spacing: input.spacing, maximumPointCount: input.maximumPointCount)
        }
    }

    private static func referencePlaced(_ input: LayeredLayoutRecording.ClusterPlacement) -> LayeredClusterPlacementBits {
        LayeredClusterPlacementBits { () throws(LayeredClusterLayoutError) in
            try ReferenceLayeredClusterLayout.place(input.graph, spacing: input.spacing, maximumPointCount: input.maximumPointCount)
        }
    }

    private static func randomInput(_ index: Int, using generator: inout LayeredEquivalenceGenerator) -> LayeredLayoutRecording.ClusterPlacement {
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
        return LayeredLayoutRecording.ClusterPlacement(graph: graph, spacing: spacing, maximumPointCount: index % 17 == 4 ? nodeCount + 2 : 50_000)
    }
}
