/**
 * File: LayeredCompoundTrackTests.swift
 * -------------------------------------
 * Layer: Tests
 * Description: Pele's tests of edges on tracks at right angles and of edges into groups, on the compound layout's port.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 23/11/2026
 */

import XCTest
@testable import MermaidDiagrams

final class LayeredCompoundTrackTests: XCTestCase {
    private typealias Testing = LayeredCompoundTesting

    /// A run across a gap, with where the edge comes down to it and goes down from it.
    private struct Run {
        var along: Double
        var low: Double
        var high: Double
        var from: Double
        var to: Double
    }

    private func randomGraph(seed: Int) -> (nodes: [LayeredCompoundNode], edges: [LayeredCompoundEdge]) {
        var random = Testing.Random(seed: seed * 7919)
        let count = 3 + random.below(14)
        let nodes = (0..<count).map { index in
            let width = Double(40 + random.below(120))
            let height = Double(30 + random.below(60))
            return Testing.node(width, height, sequence: index, span: width - 24)
        }
        var edges: [LayeredCompoundEdge] = []
        let wanted = random.below(Double(count) * 2.5)
        for _ in 0..<wanted {
            let source = random.below(count)
            let target = random.below(count)
            guard source != target else { continue }
            let isLabelled = random.next() < 0.2
            edges.append(Testing.edge(source, target, labelWidth: isLabelled ? Double(30 + random.below(40)) : 0, labelHeight: 20))
        }
        return (nodes, edges)
    }

    private func runs(of route: [Double]) -> [Run] {
        var found: [Run] = []
        for index in stride(from: 3, to: route.count, by: 3) {
            let isAcross = abs(route[index + 1] - route[index - 2]) < 0.01
            let isDown = abs(route[index] - route[index - 3]) < 0.5
            XCTAssertTrue(isAcross || isDown, "turns at right angles")
            if !isAcross || isDown { continue }
            // The route runs upwards when the edge does, so the higher end is the one it comes down to.
            let before = index >= 6 ? route[index - 5] : route[index - 2]
            let fromFirst = before < route[index - 2] - 0.01 || (index + 4 < route.count && route[index + 4] > route[index + 1] + 0.01)
            found.append(Run(along: route[index + 1], low: min(route[index], route[index - 3]), high: max(route[index], route[index - 3]),
                             from: fromFirst ? route[index - 3] : route[index], to: fromFirst ? route[index] : route[index - 3]))
        }
        return found
    }

    func testEdgesOnTracksRunAtRightAnglesWhereNoTwoCanBeTakenForEachOther() {
        var options = Testing.options
        options.runsOnTracks = true
        for seed in 1...120 {
            var (nodes, edges) = randomGraph(seed: seed)
            Testing.lay(&nodes, &edges, options: options)
            var all: [Run] = []
            for (index, edge) in edges.enumerated() {
                let route = Testing.flat(edge)
                XCTAssertTrue(Testing.isOnBorder(nodes[edge.source], route[0], route[1]), "seed \(seed) edge \(index) starts on its source")
                XCTAssertTrue(Testing.isOnBorder(nodes[edge.target], route[route.count - 3], route[route.count - 2]), "seed \(seed) edge \(index) ends on its target")
                all += runs(of: route)
            }
            for first in all.indices {
                for second in all.indices where second > first && abs(all[first].along - all[second].along) <= 0.01 {
                    let overlap = all[first].low < all[second].high - 0.5 && all[second].low < all[first].high - 0.5
                    let mates = abs(all[first].from - all[second].from) < 0.5 || abs(all[first].to - all[second].to) < 0.5
                    XCTAssertFalse(overlap && !mates, "seed \(seed) runs \(first) and \(second) lie on one track")
                }
            }
            for run in all {
                for node in nodes {
                    let isInside = abs(run.along - node.y) < node.height / 2 - 0.5 && run.low < node.x + node.width / 2 - 0.5 && run.high > node.x - node.width / 2 + 0.5
                    XCTAssertFalse(isInside, "seed \(seed) a run crosses a node")
                }
            }
        }
    }

    func testAnEdgeIntoAGroupRunsStraightWhenOnlyItsBendsNeedToMove() {
        var nodes = [Testing.group(sequence: 100), Testing.group(sequence: 101)]
        func leaf(_ parent: Int) -> Int {
            nodes.append(Testing.node(54, 48, parent: parent, sequence: nodes.count, span: 24))
            return nodes.count - 1
        }
        let first = leaf(0), second = leaf(0), third = leaf(0), fourth = leaf(1), fifth = leaf(1), outside = leaf(-1), last = leaf(-1)
        var edges = [(first, second), (first, third), (fourth, fifth), (second, fourth), (third, fourth), (fifth, first), (outside, 0), (outside, 1), (0, last), (1, last)]
            .map { source, target in Testing.edge(source, target) }
        Testing.lay(&nodes, &edges)
        let route = Testing.flat(edges[7])
        let end = route[route.count - 3]
        for index in stride(from: 0, to: route.count, by: 3) where route[index + 1] > nodes[outside].y + nodes[outside].height / 2 + 24 {
            XCTAssertEqual(route[index], end, accuracy: 1e-5)
        }
    }
}
