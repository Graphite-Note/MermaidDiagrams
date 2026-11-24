/**
 * File: LayeredClusterFlatPlacementTests.swift
 * --------------------------------------------
 * Layer: Tests
 * Description: A cluster graph without clusters, placed straight on the flat layout, gets to the bit the placement the
 *              compound layout gives it: every such graph the corpora place, and random ones in every direction.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 24/11/2026
 */

import CoreGraphics
import XCTest
@testable import MermaidDiagrams

final class LayeredClusterFlatPlacementTests: XCTestCase {
    /// Every cluster graph the corpora place (use case diagrams without boundaries among them), placed by
    /// `LayeredClusterLayout.place` and by the compound layout, alike to the bit; the graphs with clusters take the
    /// compound layout either way.
    func testEveryClusterPlacementOfTheCorporaMatchesTheCompoundLayout() throws {
        let recording = try LayeredCorpusRecording.shared()
        let withoutClusters = recording.clusterPlacements.filter { input in input.graph.clusters.isEmpty }
        XCTAssertGreaterThan(withoutClusters.count, 20)
        for (index, input) in recording.clusterPlacements.enumerated() {
            XCTAssertEqual(LayeredClusterPlacementBits(input, isCompound: false), LayeredClusterPlacementBits(input, isCompound: true), "cluster placement \(index)")
        }
    }

    /// Random graphs without clusters (loops, labels, lengths, side spans, every direction, budgets too small) placed
    /// both ways, alike to the bit.
    func testRandomGraphsWithoutClustersMatchTheCompoundLayout() {
        var generator = LayeredEquivalenceGenerator(seed: 0xC1_057E)
        let directions: [LayeredDirection] = [.topToBottom, .bottomToTop, .leftToRight, .rightToLeft]
        for index in 0..<300 {
            let nodeCount = Int.random(in: 0...12, using: &generator)
            let sizes = (0..<nodeCount).map { _ in
                CGSize(width: Int.random(in: 0...90, using: &generator), height: Int.random(in: 0...50, using: &generator))
            }
            var edges: [LayeredClusterEdge] = []
            for _ in 0..<Int.random(in: 0...(2 * nodeCount), using: &generator) where nodeCount > 0 {
                let label = Bool.random(using: &generator)
                    ? CGSize(width: Int.random(in: 0...40, using: &generator), height: Int.random(in: 0...20, using: &generator)) : nil
                edges.append(LayeredClusterEdge(source: .node(Int.random(in: 0..<nodeCount, using: &generator)),
                                                target: .node(Int.random(in: 0..<nodeCount, using: &generator)),
                                                minimumRankSpan: Int.random(in: 1...2, using: &generator), labelSize: label))
            }
            let spans = index % 2 == 0 ? sizes.map { size in size.width * 0.6 } : []
            let graph = LayeredClusterGraph(nodeSizes: sizes, nodeSideSpans: spans, nodeClusters: [Int?](repeating: nil, count: nodeCount),
                                            clusters: [], edges: edges, direction: directions[index % 4])
            var spacing = LayeredSpacing(nodeSeparation: 40, edgeSeparation: 16, rankSeparation: 48)
            spacing.routing.runsOnTracks = index % 5 == 1
            spacing.routing.isStraight = index % 7 == 3
            let input = LayeredLayoutRecording.ClusterPlacement(graph: graph, spacing: spacing, maximumPointCount: index % 13 == 4 ? nodeCount : 50_000)
            XCTAssertEqual(LayeredClusterPlacementBits(input, isCompound: false), LayeredClusterPlacementBits(input, isCompound: true), "random graph \(index)")
        }
    }
}

/// Every number of a cluster placement as bit patterns, or the error it threw.
struct LayeredClusterPlacementBits: Equatable {
    var bits: [UInt64] = []
    var error: LayeredClusterLayoutError?

    init(_ input: LayeredLayoutRecording.ClusterPlacement, isCompound: Bool) {
        self.init { () throws(LayeredClusterLayoutError) in
            isCompound
                ? try LayeredClusterLayout.placeInCompoundLayout(input.graph, spacing: input.spacing, maximumPointCount: input.maximumPointCount)
                : try LayeredClusterLayout.place(input.graph, spacing: input.spacing, maximumPointCount: input.maximumPointCount)
        }
    }

    /// The bits of what `placing` gives.
    init(placing: () throws(LayeredClusterLayoutError) -> LayeredClusterPlacement) {
        let placement: LayeredClusterPlacement
        do {
            placement = try placing()
        } catch {
            self.error = error
            return
        }
        func add(_ point: CGPoint) { bits += [Double(point.x).bitPattern, Double(point.y).bitPattern] }
        placement.nodeCenters.forEach(add)
        for frame in placement.clusterFrames { bits += [frame.minX, frame.minY, frame.width, frame.height].map { value in Double(value).bitPattern } }
        for route in placement.edgeRoutes {
            bits.append(UInt64(route.points.count))
            route.points.forEach(add)
            bits += route.segmentsRunVertically.map { runsVertically in runsVertically ? 1 : 0 }
        }
        for center in placement.edgeLabelCenters {
            if let center { add(center) } else { bits.append(UInt64.max) }
        }
        bits += [Double(placement.size.width).bitPattern, Double(placement.size.height).bitPattern]
        bits += placement.strayEdgeIndices.sorted().map { index in UInt64(index) }
    }
}
