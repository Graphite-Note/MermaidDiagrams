/**
 * File: LayeredCompoundLayoutTests.swift
 * --------------------------------------
 * Layer: Tests
 * Description: Pele's tests of its compound layout (tests/layout/compound.test.ts) on the port: forms, order and ends.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 23/11/2026
 */

import XCTest
@testable import MermaidDiagrams

final class LayeredCompoundLayoutTests: XCTestCase {
    private typealias Testing = LayeredCompoundTesting

    func testRandomGraphsStayWellFormed() {
        for seed in 1...300 {
            var (nodes, edges, direction) = Testing.randomGraph(seed: seed)
            let size = Testing.lay(&nodes, &edges, direction)
            XCTAssertTrue(size.width.isFinite && size.height.isFinite, "seed \(seed)")
            for (index, node) in nodes.enumerated() {
                XCTAssertGreaterThanOrEqual(node.x - node.width / 2, -0.5, "seed \(seed) node \(index) left")
                XCTAssertGreaterThanOrEqual(node.y - node.height / 2, -0.5, "seed \(seed) node \(index) top")
                XCTAssertLessThanOrEqual(node.x + node.width / 2, size.width + 0.5, "seed \(seed) node \(index) right")
                XCTAssertLessThanOrEqual(node.y + node.height / 2, size.height + 0.5, "seed \(seed) node \(index) bottom")
                guard node.parent >= 0 else { continue }
                let parent = nodes[node.parent]
                XCTAssertLessThanOrEqual(abs(node.x - parent.x) + node.width / 2, parent.width / 2 + 0.5, "seed \(seed) node \(index) in parent")
                XCTAssertLessThanOrEqual(abs(node.y - parent.y) + node.height / 2, parent.height / 2 + 0.5, "seed \(seed) node \(index) in parent")
            }
            for first in nodes.indices {
                for second in nodes.indices where second > first && nodes[first].parent == nodes[second].parent {
                    let overlapX = (nodes[first].width + nodes[second].width) / 2 - abs(nodes[first].x - nodes[second].x)
                    let overlapY = (nodes[first].height + nodes[second].height) / 2 - abs(nodes[first].y - nodes[second].y)
                    XCTAssertFalse(overlapX > 0.5 && overlapY > 0.5, "seed \(seed) nodes \(first) and \(second) overlap")
                }
            }
            for (index, edge) in edges.enumerated() where edge.source != edge.target {
                let route = Testing.flat(edge)
                XCTAssertGreaterThanOrEqual(route.count, 6, "seed \(seed) edge \(index) has a route")
                XCTAssertTrue(route.allSatisfy(\.isFinite), "seed \(seed) edge \(index)")
                if Testing.isAncestor(nodes, edge.source, of: edge.target) || Testing.isAncestor(nodes, edge.target, of: edge.source) { continue }
                let last = route.count - 3
                XCTAssertTrue(Testing.isOnBorder(nodes[edge.source], route[0], route[1]), "seed \(seed) edge \(index) starts on its source")
                XCTAssertTrue(Testing.isOnBorder(nodes[edge.target], route[last], route[last + 1]), "seed \(seed) edge \(index) ends on its target")
            }
        }
    }

    func testTheLayoutIsDeterministic() {
        for seed in 1...40 {
            var first = Testing.randomGraph(seed: seed)
            var second = Testing.randomGraph(seed: seed)
            Testing.lay(&first.nodes, &first.edges, first.direction)
            Testing.lay(&second.nodes, &second.edges, second.direction)
            XCTAssertEqual(second.nodes, first.nodes)
            XCTAssertEqual(second.edges.map(\.route), first.edges.map(\.route))
        }
    }

    func testRanksRunAlongTheRequestedDirection() {
        for direction in Testing.directions {
            var nodes = (0..<3).map { index in Testing.node(60, 40, sequence: index) }
            var edges = [Testing.edge(0, 1), Testing.edge(1, 2)]
            Testing.lay(&nodes, &edges, direction)
            let sign: Double = direction == .topToBottom || direction == .leftToRight ? 1 : -1
            func along(_ node: Int) -> Double { direction.runsVertically ? nodes[node].y : nodes[node].x }
            XCTAssertGreaterThan(sign * (along(1) - along(0)), 40)
            XCTAssertGreaterThan(sign * (along(2) - along(1)), 40)
        }
    }

    func testALongEdgeRunsStraightThroughTheRanksItSkips() {
        var nodes = (0..<3).map { index in Testing.node(60, 40, sequence: index) }
        var edges = [Testing.edge(0, 1), Testing.edge(1, 2), Testing.edge(0, 2)]
        Testing.lay(&nodes, &edges)
        let route = Testing.flat(edges[2])
        let inner = stride(from: 3, to: route.count - 3, by: 3).map { index in route[index].rounded() }
        XCTAssertEqual(Set(inner).count, 1)
    }

    func testAnEdgeThatSkipsRanksRunsInLineWithAnEndAndTurnsOnceAtTheOther() {
        var nodes = (0..<8).map { index in Testing.node(80, 40, sequence: index, span: 56) }
        let pairs = [(0, 1), (1, 2), (2, 3), (3, 4), (4, 5), (5, 6), (6, 7), (0, 3), (0, 7), (1, 5), (2, 6), (6, 1), (7, 0)]
        var edges = pairs.map { source, target in Testing.edge(source, target) }
        Testing.lay(&nodes, &edges)
        func turns(_ route: [Double]) -> Int {
            stride(from: 3, to: route.count, by: 3).filter { index in abs(route[index] - route[index - 3]) > 0.01 }.count
        }
        for edge in edges.dropFirst(7) { XCTAssertEqual(turns(Testing.flat(edge)), 1, "\(edge.source) to \(edge.target)") }
        let down = Testing.flat(edges[9])
        let up = Testing.flat(edges[11])
        XCTAssertEqual(down[3], down[0], accuracy: 1e-5)
        XCTAssertEqual(up[up.count - 6], up[up.count - 3], accuracy: 1e-5)
    }

    func testEdgesStayAtTheMiddleOfASideUnlessTheNodeHasASpan() {
        var nodes = [Testing.node(120, 40, sequence: 0), Testing.node(60, 40, sequence: 1), Testing.node(60, 40, sequence: 2), Testing.node(60, 40, sequence: 3)]
        var edges = [Testing.edge(0, 1), Testing.edge(0, 2), Testing.edge(0, 3)]
        Testing.lay(&nodes, &edges)
        for edge in edges { XCTAssertEqual(Testing.flat(edge)[0], nodes[0].x, accuracy: 1e-5) }
    }

    func testEdgesSpreadAlongASideInTheOrderOfTheNodesTheyLeadTo() {
        for direction in Testing.directions {
            var nodes = [Testing.node(120, 120, sequence: 0, span: 96), Testing.node(60, 60, sequence: 1), Testing.node(60, 60, sequence: 2),
                         Testing.node(60, 60, sequence: 3)]
            var edges = [Testing.edge(0, 1), Testing.edge(0, 2), Testing.edge(0, 3)]
            Testing.lay(&nodes, &edges, direction)
            let across = direction.runsVertically ? 0 : 1
            let starts = edges.map { edge in Testing.flat(edge)[across] - (across == 0 ? nodes[0].x : nodes[0].y) }
            let targets = edges.map { edge in across == 0 ? nodes[edge.target].x : nodes[edge.target].y }
            let byStart = [0, 1, 2].sorted { first, second in starts[first] < starts[second] }
            XCTAssertEqual(byStart, [0, 1, 2].sorted { first, second in targets[first] < targets[second] }, "\(direction)")
            // None of the three can run straight, so they stay around the middle, a pitch apart.
            XCTAssertEqual(starts[byStart[0]], -16, accuracy: 1e-5)
            XCTAssertEqual(starts[byStart[1]], 0, accuracy: 1e-5)
            XCTAssertEqual(starts[byStart[2]], 16, accuracy: 1e-5)
            for edge in edges { XCTAssertTrue(Testing.isOnBorder(nodes[0], Testing.flat(edge)[0], Testing.flat(edge)[1]), "\(direction)") }
        }
    }

    func testAnEdgeThatArrivesKeepsApartFromOneThatLeavesOnTheSameSide() {
        var nodes = [Testing.node(60, 40, sequence: 0, span: 36), Testing.node(60, 40, sequence: 1, span: 36)]
        var edges = [Testing.edge(0, 1), Testing.edge(1, 0)]
        Testing.lay(&nodes, &edges)
        let down = Testing.flat(edges[0])
        let up = Testing.flat(edges[1])
        XCTAssertEqual(abs(down[down.count - 3] - up[0]), 16, accuracy: 1e-5)
        XCTAssertEqual(abs(down[0] - up[up.count - 3]), 16, accuracy: 1e-5)
    }

    func testEdgesRunningTheSameWayShareAPlaceWhenThereIsNoRoomForOneEach() {
        var nodes = (0...12).map { index in Testing.node(60, 40, sequence: index, span: 36) }
        var edges = (0..<12).map { index in Testing.edge(index, 12) }
        // One edge the other way on the same side, which keeps a place of its own.
        edges.append(Testing.edge(12, 0))
        Testing.lay(&nodes, &edges)
        let into = edges.prefix(12).map { edge in Testing.flat(edge)[Testing.flat(edge).count - 3] }
        XCTAssertLessThanOrEqual(Set(into.map { place in (place * 100).rounded() }).count, 2)
        let back = Testing.flat(edges[12])
        XCTAssertEqual(back[1], nodes[12].y - 20, accuracy: 1e-5)
        for place in into { XCTAssertGreaterThanOrEqual(abs(place - back[0]), 8) }
    }

    func testARankThatOnlySendsStandsOnALineAndOneThatOnlyReceivesHangsFromOne() {
        func lay(span: Double) -> [LayeredCompoundNode] {
            var nodes = [(60, 40), (60, 120), (60, 30), (60, 90)].enumerated().map { index, size in
                Testing.node(Double(size.0), Double(size.1), sequence: index, span: span)
            }
            var edges = [Testing.edge(0, 2), Testing.edge(1, 2), Testing.edge(0, 3), Testing.edge(1, 3)]
            Testing.lay(&nodes, &edges)
            return nodes
        }
        let spread = lay(span: 36)
        XCTAssertEqual(spread[0].y + 20, spread[1].y + 60, accuracy: 1e-5)
        XCTAssertEqual(spread[2].y - 15, spread[3].y - 45, accuracy: 1e-5)
        // Without spreading each rank is centred.
        let plain = lay(span: 0)
        XCTAssertEqual(plain[0].y, plain[1].y, accuracy: 1e-5)
        XCTAssertEqual(plain[2].y, plain[3].y, accuracy: 1e-5)
    }

    func testGroupsThatContainEachOtherAreLaidOut() {
        var first = LayeredCompoundNode(width: 0, height: 0, parent: 1)
        var second = LayeredCompoundNode(width: 0, height: 0, parent: 0)
        first.isGroup = true
        second.isGroup = true
        var nodes = [first, second, Testing.node(40, 40, parent: 0), Testing.node(40, 40)]
        var edges = [Testing.edge(2, 3)]
        let size = Testing.lay(&nodes, &edges)
        XCTAssertTrue(size.width.isFinite)
        XCTAssertGreaterThanOrEqual(Testing.flat(edges[0]).count, 6)
    }
}
