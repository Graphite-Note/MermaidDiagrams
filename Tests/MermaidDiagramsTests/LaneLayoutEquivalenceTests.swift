/**
 * File: LaneLayoutEquivalenceTests.swift
 * --------------------------------------
 * Layer: Tests
 * Description: The lane layout on the scratch arena against the 0.7.0 lane layout kept as the reference: every
 *              swimlane diagram of the corpora, as it runs and turned, roomy and tight, thousands of random graphs in
 *              lanes and hostile ones, every frame, route point, segment, text center and size alike to the bit.
 *
 * Authors: Bahey Shalash
 * Version: 0.2
 * Date: 26/11/2026
 */

import CoreGraphics
import XCTest
@testable import MermaidDiagrams
@testable import MermaidDiagramsBenchmark

final class LaneLayoutEquivalenceTests: XCTestCase {
    static let tightSpacing = SwimlaneLayoutEngine.tightSpacing

    func testEverySwimlaneOfTheCorporaIsPlacedAsTheReferencePlacesIt() throws {
        let typography = DiagramSceneSamples.typography
        var graphCount = 0
        var mismatches = 0
        for source in try OutputDigest.corpora().flatMap(\.sources) {
            guard case .swimlane(let written)? = try? MermaidDiagramReader.read(source, limits: .standard) else { continue }
            for diagram in [written, written.swimlaneTurnedToRunDown].compactMap({ diagram in diagram }) {
                for isTight in [false, true] {
                    let graph = Self.laneGraph(of: diagram, typography: typography, isTight: isTight)
                    graphCount += 1
                    if !Self.placesAlike(graph, spacing: isTight ? Self.tightSpacing : LaneLayoutTests.spacing) {
                        mismatches += 1
                        if mismatches <= 5 { XCTFail("the lanes differ for\(isTight ? " tight" : ""):\n\(source.prefix(400))") }
                    }
                }
            }
        }
        XCTAssertGreaterThan(graphCount, 40)
        XCTAssertEqual(mismatches, 0)
    }

    func testRandomGraphsInLanesArePlacedAsTheReferencePlacesThem() {
        var mismatches = 0
        var routedAroundCount = 0
        for seed in 1...2_000 {
            let graph = LaneLayoutSamples.randomGraph(seed: UInt64(seed))
            let spacing = seed.isMultiple(of: 3) ? Self.tightSpacing : LaneLayoutTests.spacing
            let reference = ReferenceLaneLayout.place(graph, spacing: spacing)
            if Self.bits(of: LaneLayout.place(graph, spacing: spacing)) != Self.bits(of: reference) {
                mismatches += 1
                if mismatches <= 5 { XCTFail("seed \(seed) is placed otherwise") }
            }
            if reference.routes.contains(where: { route in (route?.points.count ?? 0) > 4 }) { routedAroundCount += 1 }
        }
        XCTAssertEqual(mismatches, 0)
        // Some handoffs go around a margin, so that every way a route is tried is compared.
        XCTAssertGreaterThan(routedAroundCount, 100)
    }

    func testHostileGraphsArePlacedAsTheReferencePlacesThem() {
        for graph in LaneLayoutSamples.hostileGraphs() {
            XCTAssertTrue(Self.placesAlike(graph, spacing: LaneLayoutTests.spacing), "\(graph.boxes.count) boxes, \(graph.edges.count) edges")
        }
    }

    func testTheLayoutGivesTheSamePlacementOnManyThreadsAtOnce() {
        let graphs = (1...40).map { seed in LaneLayoutSamples.randomGraph(seed: UInt64(seed)) }
        let expected = graphs.map { graph in Self.bits(of: ReferenceLaneLayout.place(graph, spacing: LaneLayoutTests.spacing)) }
        let mismatches = LaneLockedCount()
        DispatchQueue.concurrentPerform(iterations: 12) { thread in
            for round in 0..<20 {
                let index = (thread * 7 + round) % graphs.count
                if Self.bits(of: LaneLayout.place(graphs[index], spacing: LaneLayoutTests.spacing)) != expected[index] { mismatches.add() }
            }
        }
        XCTAssertEqual(mismatches.value, 0)
    }

    /// The lane graph the swimlane engine lays out for `diagram`, made as the 0.7.0 `SwimlaneLayoutEngine.layout` made it, as
    /// lists (`ReferenceSwimlaneGraph`, which `SwimlaneLayoutEquivalenceTests` checks the graph in the arena against).
    static func laneGraph(of written: FlowchartDiagram, typography: DiagramTypography, isTight: Bool) -> LaneLayoutGraph {
        let diagram = FlowchartCollapsedGroups.collapsing(written)
        let measured = FlowchartMeasurement(diagram: diagram, nodeText: typography.nodeText, edgeText: typography.edgeText,
                                            wrappingWidth: isTight ? SwimlaneLayoutEngine.tightWrappingWidth : SwimlaneLayoutEngine.wrappingWidth)
        let titleRoom = isTight ? max(80, PreparedMermaidDiagram.standardNarrowestColumnWidth - 2 * SwimlaneLayoutEngine.padding) : SwimlaneLayoutEngine.unwrapped
        return ReferenceSwimlaneGraph(diagram: diagram, measured: measured, titleText: typography.nodeText,
                                      titleWidth: isTight ? max(80, titleRoom / 2) : SwimlaneLayoutEngine.unwrapped, isTight: isTight,
                                      edgeTextRoom: FlowchartLayoutEngine.edgeTextRoom).graph
    }

    static func placesAlike(_ graph: LaneLayoutGraph, spacing: LayeredSpacing) -> Bool {
        bits(of: LaneLayout.place(graph, spacing: spacing)) == bits(of: ReferenceLaneLayout.place(graph, spacing: spacing))
    }

    /// Every number and choice of a placement as bit patterns.
    static func bits(of placement: LaneLayoutPlacement) -> [UInt64] {
        var bits: [UInt64] = []
        func add(_ value: CGFloat) { bits.append(UInt64(value.bitPattern)) }
        func add(_ point: CGPoint) { add(point.x); add(point.y) }
        add(placement.size.width)
        add(placement.size.height)
        add(placement.laneTitleDepth)
        for frame in placement.frames { add(frame.origin); add(frame.size.width); add(frame.size.height) }
        bits.append(UInt64(placement.lanes.count))
        for lane in placement.lanes { bits.append(UInt64(bitPattern: Int64(lane))) }
        for route in placement.routes {
            guard let route else {
                bits.append(.max)
                continue
            }
            bits.append(UInt64(route.points.count))
            for point in route.points { add(point) }
            for isVertical in route.segmentsRunVertically { bits.append(isVertical ? 1 : 0) }
        }
        for center in placement.labelCenters { add(center) }
        return bits
    }
}

/// A count several threads add to.
private final class LaneLockedCount: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0

    func add() {
        lock.lock()
        count += 1
        lock.unlock()
    }

    var value: Int {
        lock.lock()
        defer { lock.unlock() }
        return count
    }
}
