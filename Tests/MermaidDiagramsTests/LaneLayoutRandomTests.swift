/**
 * File: LaneLayoutRandomTests.swift
 * ---------------------------------
 * Layer: Tests
 * Description: Random graphs in lanes, as Pele's lane layout test makes them: every box in its lane, every group in its
 *              lane around its members, no two boxes overlapping, every route on the page, and the same result every time.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 19/11/2026
 */

import XCTest
@testable import MermaidDiagrams

final class LaneLayoutRandomTests: XCTestCase {
    /// A small seeded generator, so that each seed makes the same graph.
    private struct SeededNumbers {
        var state: UInt64

        mutating func below(_ bound: Int) -> Int {
            state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            return Int((state >> 33) % UInt64(bound))
        }

        mutating func chance(_ share: Double) -> Bool { Double(below(1_000_000)) / 1_000_000 < share }
    }

    private struct Sample {
        var graph: LaneLayoutGraph
        var lanes: [Int] = []
        var leaves: [Int] = []
        var laneOfLeaf: [Int: Int] = [:]
        var inner: [(group: Int, lane: Int)] = []
    }

    /// Up to 30 nodes and 5 lanes and 3 groups inside lanes, the nodes first, as the flowchart's graph lists them.
    private static func randomSample(seed: UInt64) -> Sample {
        var numbers = SeededNumbers(state: seed)
        var sample = Sample(graph: LaneLayoutGraph(boxes: [], edges: [], direction: LaneLayoutTests.directions[numbers.below(4)]))
        let leafCount = 1 + numbers.below(30)
        let laneCount = 1 + numbers.below(5)
        for _ in 0..<leafCount {
            sample.leaves.append(sample.graph.boxes.count)
            sample.graph.boxes.append(LaneLayoutTests.node(CGFloat(30 + numbers.below(120)), CGFloat(24 + numbers.below(60))))
        }
        for _ in 0..<laneCount {
            sample.lanes.append(sample.graph.boxes.count)
            sample.graph.boxes.append(LaneLayoutTests.group())
        }
        for _ in 0..<numbers.below(4) {
            let lane = sample.lanes[numbers.below(laneCount)]
            sample.inner.append((sample.graph.boxes.count, lane))
            sample.graph.boxes.append(LaneLayoutTests.group(in: lane))
        }
        for leaf in sample.leaves {
            if !sample.inner.isEmpty, numbers.chance(0.25) {
                let group = sample.inner[numbers.below(sample.inner.count)]
                sample.graph.boxes[leaf].parent = group.group
                sample.laneOfLeaf[leaf] = group.lane
            } else {
                let lane = sample.lanes[numbers.below(laneCount)]
                sample.graph.boxes[leaf].parent = lane
                sample.laneOfLeaf[leaf] = lane
            }
        }
        for _ in 0..<numbers.below(leafCount * 2) {
            let label = numbers.chance(0.3) ? CGSize(width: CGFloat(20 + numbers.below(80)), height: 18) : nil
            sample.graph.edges.append(LaneLayoutTests.edge(numbers.below(leafCount), numbers.below(leafCount), label: label))
        }
        if numbers.chance(0.3) { sample.graph.edges.append(LaneLayoutTests.edge(sample.lanes[0], sample.leaves[0])) }
        return sample
    }

    func testRandomGraphsAreWellFormedWithEitherLanePadding() {
        for lanePadding in [CGFloat(24), 12] {
            for seed in UInt64(1)...300 {
                var sample = Self.randomSample(seed: seed)
                sample.graph.lanePadding = lanePadding
                let placement = LaneLayout.place(sample.graph, spacing: LaneLayoutTests.spacing)
                Self.assertWellFormed(sample, placement, seed: seed)
            }
        }
    }

    func testTheSameGraphIsLaidOutAlikeEveryTime() {
        let sample = Self.randomSample(seed: 42)
        let first = LaneLayout.place(sample.graph, spacing: LaneLayoutTests.spacing)
        let second = LaneLayout.place(sample.graph, spacing: LaneLayoutTests.spacing)
        XCTAssertEqual(first.frames, second.frames)
        XCTAssertEqual(first.routes, second.routes)
    }

    private static func assertWellFormed(_ sample: Sample, _ placement: LaneLayoutPlacement, seed: UInt64) {
        let page = CGRect(origin: .zero, size: placement.size).insetBy(dx: -0.01, dy: -0.01)
        func contains(_ outer: CGRect, _ inner: CGRect) -> Bool { outer.insetBy(dx: -0.01, dy: -0.01).contains(inner) }
        XCTAssertTrue(placement.size.width.isFinite && placement.size.height.isFinite, "seed \(seed)")
        for leaf in sample.leaves {
            XCTAssertTrue(contains(placement.frames[sample.laneOfLeaf[leaf] ?? 0], placement.frames[leaf]), "seed \(seed): node \(leaf) in its lane")
        }
        for (group, lane) in sample.inner where sample.leaves.contains(where: { leaf in sample.graph.boxes[leaf].parent == group }) {
            XCTAssertTrue(contains(placement.frames[lane], placement.frames[group]), "seed \(seed): group \(group) in its lane")
        }
        for (index, leaf) in sample.leaves.enumerated() {
            for other in sample.leaves[(index + 1)...] {
                XCTAssertFalse(placement.frames[leaf].insetBy(dx: 0.01, dy: 0.01).intersects(placement.frames[other]), "seed \(seed): \(leaf) and \(other)")
            }
        }
        for lane in sample.lanes { XCTAssertTrue(page.contains(placement.frames[lane]), "seed \(seed): lane inside") }
        for (edgeIndex, edge) in sample.graph.edges.enumerated() where edge.source != edge.target {
            let route = placement.routes[edgeIndex]?.points ?? []
            XCTAssertGreaterThanOrEqual(route.count, 2, "seed \(seed): route")
            for point in route { XCTAssertTrue(page.contains(point), "seed \(seed): route inside the lanes") }
            XCTAssertTrue(placement.labelCenters[edgeIndex].x.isFinite && placement.labelCenters[edgeIndex].y.isFinite, "seed \(seed): label")
        }
    }
}
