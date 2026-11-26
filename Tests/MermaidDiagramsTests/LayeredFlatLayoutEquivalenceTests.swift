/**
 * File: LayeredFlatLayoutEquivalenceTests.swift
 * ---------------------------------------------
 * Layer: Tests
 * Description: Every flat layered layout, placement and compound ranking that the corpora's diagrams run, regular and
 *              narrow, and hundreds of random graphs give exactly, bit for bit, what the 0.7.0 layout gives them.
 *
 * Authors: Bahey Shalash
 * Version: 0.2
 * Date: 25/11/2026
 */

import CoreGraphics
import XCTest
@testable import MermaidDiagrams
@testable import MermaidDiagramsBenchmark

final class LayeredFlatLayoutEquivalenceTests: XCTestCase {
    /// Each flat layout the corpora ran (every flowchart, state, class, ER, requirement, use case and agent flow layout,
    /// and those within compound layouts), laid out again by the layout and by the reference, ranks, places, offsets,
    /// routes, label centers, sizes and crossings alike to the bit.
    func testEveryFlatLayoutOfTheCorporaMatchesTheReferenceBitForBit() throws {
        let recording = try LayeredCorpusRecording.shared()
        XCTAssertGreaterThan(recording.flatLayouts.count, 1_000)
        var mismatches = 0
        for (index, input) in recording.flatLayouts.enumerated() {
            let laidOut = LayeredFlatOutcome(input, isReference: false)
            let reference = LayeredFlatOutcome(input, isReference: true)
            if laidOut != reference {
                mismatches += 1
                if mismatches <= 5 { XCTFail("flat layout \(index) (\(input.nodes.count) nodes, \(input.edges.count) edges) differs") }
            }
        }
        XCTAssertEqual(mismatches, 0)
    }

    /// Each flat graph the corpora's ranked layouts (flowchart, state, class, ER and requirement diagrams without groups)
    /// wrote into the flat layout's spans, placed again on the spans and by the 0.7.0 reference as 0.7.0 was handed it:
    /// centers, routes, label centers, paths and extents alike to the bit.
    func testEveryPlacementOfTheCorporaMatchesTheReferenceBitForBit() throws {
        let recording = try LayeredCorpusRecording.shared()
        XCTAssertGreaterThan(recording.placements.count, 500)
        var mismatches = 0
        for (index, recorded) in recording.placements.enumerated() {
            let input = LayeredPlacementInput(recorded)
            let placed = LayeredSpanPlacement.place(input)
            let reference = ReferenceLayeredLayout.place(input.graph, spacing: input.spacing, maximumPointCount: input.maximumPointCount)
            if LayeredPlacementBits(placed) != LayeredPlacementBits(reference) {
                mismatches += 1
                if mismatches <= 5 { XCTFail("placement \(index) (\(input.graph.nodeSizes.count) nodes) differs") }
            }
        }
        XCTAssertEqual(mismatches, 0)
    }

    /// Each ranking a compound layout of the corpora asked for gives the same ranks and turned edges.
    func testEveryCompoundRankingOfTheCorporaMatchesTheReference() throws {
        let recording = try LayeredCorpusRecording.shared()
        XCTAssertGreaterThan(recording.rankings.count, 10)
        for (index, input) in recording.rankings.enumerated() {
            XCTAssertEqual(LayeredRankingOutcome(nodes: input.nodes, edges: input.edges, isReference: false),
                           LayeredRankingOutcome(nodes: input.nodes, edges: input.edges, isReference: true), "ranking \(index)")
        }
    }

    /// Random flat graphs of every kind the layout knows (ports with hints, pinned nodes, order keys, labels, twins,
    /// offsets, spread and held ends, nested groups, orders only, tracks, straight edges, budgets too small), laid out by
    /// the layout and by the reference, alike to the bit.
    func testRandomFlatGraphsMatchTheReferenceBitForBit() {
        var generator = LayeredEquivalenceGenerator(seed: 0x5BA_C0DE)
        for index in 0..<400 {
            let input = LayeredRandomGraphs.flatLayout(index, using: &generator)
            XCTAssertEqual(LayeredFlatOutcome(input, isReference: false), LayeredFlatOutcome(input, isReference: true), "random graph \(index)")
            XCTAssertEqual(LayeredRankingOutcome(nodes: input.nodes, edges: input.edges, isReference: false),
                           LayeredRankingOutcome(nodes: input.nodes, edges: input.edges, isReference: true), "random ranking \(index)")
        }
    }

    /// Random graphs placed on the flat layout's spans, with side spans, offsets, labels and every routing, alike to the
    /// bit; some budgets are too small, which both refuse.
    func testRandomPlacementsMatchTheReferenceBitForBit() {
        var generator = LayeredEquivalenceGenerator(seed: 0x9_1ACE)
        for index in 0..<200 {
            let input = LayeredRandomGraphs.placement(index, using: &generator)
            let placed = LayeredSpanPlacement.place(input)
            let reference = ReferenceLayeredLayout.place(input.graph, spacing: input.spacing, maximumPointCount: input.maximumPointCount)
            XCTAssertEqual(LayeredPlacementBits(placed), LayeredPlacementBits(reference), "random placement \(index)")
        }
    }
}

/// What the corpora's diagrams handed the layered layouts, recorded once for every test of this file: every input of
/// Pele's corpora prepared as Graphite prepares it, regular and at each of Pele's narrow widths.
enum LayeredCorpusRecording {
    private static let recorded: Result<LayeredLayoutRecording, Error> = Result {
        let recording = LayeredLayoutRecording()
        let typography = DiagramSceneSamples.typography
        try LayeredLayoutRecording.$current.withValue(recording) {
            for (_, sources) in try OutputDigest.corpora() {
                for source in sources {
                    for width in [nil] + OutputDigest.narrowColumnWidths.map(Optional.some) {
                        let prepared = try? MermaidDiagramPreparation.prepare(source: source, typography: typography, narrowestColumnWidth: width,
                                                                              now: GanttChartCorpus.now, timeZone: GanttChartCorpus.timeZone)
                        _ = prepared?.narrowScene
                    }
                }
            }
        }
        return recording
    }

    static func shared() throws -> LayeredLayoutRecording { try recorded.get() }
}

/// Every number a flat layout gives back, as bit patterns, so that -0 and 0 differ and NaN equals NaN.
struct LayeredFlatOutcome: Equatable {
    var result: [UInt64] = []
    var nodes: [UInt64] = []
    var edges: [UInt64] = []

    init(_ input: LayeredLayoutRecording.FlatLayout, isReference: Bool) {
        var nodes = input.nodes
        var edges = input.edges
        let laidOut = isReference
            ? ReferenceLayeredFlatLayout.layout(nodes: &nodes, edges: &edges, options: input.options, maximumVertexCount: input.maximumVertexCount)
            : LayeredFlatLayout.layout(nodes: &nodes, edges: &edges, options: input.options, maximumVertexCount: input.maximumVertexCount)
        if let laidOut {
            result = [laidOut.width.bitPattern, laidOut.height.bitPattern, UInt64(bitPattern: Int64(laidOut.crossings)),
                      UInt64(bitPattern: Int64(laidOut.declaredCrossings))]
        }
        for node in nodes { self.nodes += [node.x.bitPattern, node.y.bitPattern, UInt64(bitPattern: Int64(node.rank))] }
        for edge in edges {
            self.edges += [edge.isReversed ? 1 : 0, edge.tailOffset.bitPattern, edge.headOffset.bitPattern,
                           Double(edge.labelCenter.x).bitPattern, Double(edge.labelCenter.y).bitPattern, UInt64(edge.points.count)]
            for point in edge.points { self.edges += [Double(point.x).bitPattern, Double(point.y).bitPattern] }
        }
    }
}

/// The ranks and turned edges of `LayeredFlatRanking.orient` and `rank` with a step of 1, as a compound layout asks.
struct LayeredRankingOutcome: Equatable {
    var ranks: [Int]
    var reversed: [Bool]

    init(nodes: [LayeredFlatNode], edges: [LayeredFlatEdge], isReference: Bool) {
        var nodes = nodes
        var edges = edges
        if isReference {
            let workspace = ReferenceLayeredFlatWorkspace()
            ReferenceLayeredFlatRanking.orient(nodes: nodes, edges: &edges, workspace: workspace)
            ReferenceLayeredFlatRanking.rank(nodes: &nodes, edges: edges, step: 1, workspace: workspace)
        } else {
            LayeredFlatRanking.orientAndRank(nodes: &nodes, edges: &edges, step: 1)
        }
        ranks = nodes.map(\.rank)
        reversed = edges.map(\.isReversed)
    }
}

/// Every number of a placement as bit patterns, or nothing for a refused one.
struct LayeredPlacementBits: Equatable {
    var bits: [UInt64]?

    init(_ placement: LayeredPlacement?) {
        guard let placement else { return }
        var bits: [UInt64] = []
        func add(_ point: CGPoint) { bits += [Double(point.x).bitPattern, Double(point.y).bitPattern] }
        func add(_ points: [CGPoint]) {
            bits.append(UInt64(points.count))
            points.forEach(add)
        }
        placement.nodeCenters.forEach(add)
        placement.edgeRoutes.forEach(add)
        for center in placement.edgeLabelCenters {
            if let center { add(center) } else { bits.append(UInt64.max) }
        }
        bits.append(UInt64(placement.edgePaths.count))
        placement.edgePaths.forEach(add)
        bits += [Double(placement.extent.width).bitPattern, Double(placement.extent.height).bitPattern]
        self.bits = bits
    }
}

/// SplitMix64, so that the random graphs are the same on every run.
struct LayeredEquivalenceGenerator: RandomNumberGenerator {
    var state: UInt64

    init(seed: UInt64) { state = seed }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var mixed = state
        mixed = (mixed ^ (mixed >> 30)) &* 0xBF58_476D_1CE4_E5B9
        mixed = (mixed ^ (mixed >> 27)) &* 0x94D0_49BB_1331_11EB
        return mixed ^ (mixed >> 31)
    }
}
