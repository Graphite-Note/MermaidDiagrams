/**
 * File: LayeredCompoundRoutingTests.swift
 * ---------------------------------------
 * Layer: Tests
 * Description: Pele's tests of how its layout routes edges across gaps (tests/layout/compound.test.ts), on the port.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 23/11/2026
 */

import XCTest
@testable import MermaidDiagrams

final class LayeredCompoundRoutingTests: XCTestCase {
    private typealias Testing = LayeredCompoundTesting

    /// A node above a row of `children`, with an edge to each; with a `span`, the edges spread along the nodes' sides.
    private func fan(_ children: Int, span: Double = 0, options: LayeredFlatOptions = Testing.options)
        -> (nodes: [LayeredCompoundNode], edges: [LayeredCompoundEdge], gap: Double) {
        var nodes = (0...children).map { index in Testing.node(100, 40, sequence: index, span: span) }
        var edges = (1...children).map { child in Testing.edge(0, child) }
        Testing.lay(&nodes, &edges, options: options)
        return (nodes, edges, nodes[1].y - nodes[0].y - 40)
    }

    func testAGapGrowsWhereEdgesMeetingTheMiddleOfTheirNodesRunFarAcross() {
        XCTAssertEqual(fan(3).gap, 48, accuracy: 1e-5)
        // Seven children reach 420 across from the middle, and the gap is an eighth of that.
        XCTAssertEqual(fan(7).gap, 420 / 8, accuracy: 1e-5)
        XCTAssertEqual(fan(40).gap, 3 * 48, accuracy: 1e-5)
    }

    func testEdgesRunningFarAcrossSideBySideTurnAtLevelsOfTheirOwn() {
        let few = fan(3, span: 76)
        XCTAssertEqual(few.gap, 48, accuracy: 1e-5)
        for edge in few.edges { XCTAssertEqual(Testing.flat(edge).count, 6) }
        let (nodes, edges, gap) = fan(7, span: 76)
        func level(_ edge: LayeredCompoundEdge) -> Double {
            let route = Testing.flat(edge)
            XCTAssertEqual(route.count, 12)
            guard route.count == 12 else { return .nan }
            XCTAssertEqual(route[3], route[0], accuracy: 1e-5)
            XCTAssertEqual(route[7], route[4], accuracy: 1e-5)
            XCTAssertEqual(route[9], route[6], accuracy: 1e-5)
            return route[4]
        }
        // The edge that runs furthest turns first, and each of the others 12 further down.
        XCTAssertEqual(level(edges[1]) - level(edges[0]), 12, accuracy: 1e-5)
        XCTAssertEqual(level(edges[2]) - level(edges[1]), 12, accuracy: 1e-5)
        for index in 0..<3 { XCTAssertEqual(level(edges[6 - index]), level(edges[index]), accuracy: 1e-5) }
        let middle = Testing.flat(edges[3])
        XCTAssertEqual(middle.count, 6)
        XCTAssertEqual(middle[3], middle[0], accuracy: 1e-5)
        // The levels keep 28 from the ranks above and below.
        XCTAssertEqual(level(edges[0]) - nodes[0].y - 20, 28, accuracy: 1e-5)
        XCTAssertEqual(gap, 2 * 28 + 2 * 12, accuracy: 1e-5)
    }

    func testAGapWhoseCurvesMostlyCrossIsTallerAndHasNoLevels() {
        var nodes = (0..<8).map { index in Testing.node(80, 40, sequence: index, span: 56) }
        var edges: [LayeredCompoundEdge] = []
        for upper in 0..<4 { for lower in 4..<8 { edges.append(Testing.edge(upper, lower)) } }
        Testing.lay(&nodes, &edges)
        for edge in edges { XCTAssertEqual(Testing.flat(edge).count, 6) }
        let widest = edges.map { edge in abs(Testing.flat(edge)[0] - Testing.flat(edge)[3]) }.max() ?? 0
        XCTAssertGreaterThan(widest, 6 * 48)
        XCTAssertEqual(nodes[4].y - nodes[0].y - 40, 3 * 48, accuracy: 1e-5)
    }

    func testARankOfLabelsSitsHalfAnArrowheadNearerTheTailsAndABendBesideThemHoldsHalfTheirHeight() {
        func lay(headRoom: Double) -> [LayeredCompoundEdge] {
            var nodes = [Testing.node(60, 40, sequence: 0, span: 36), Testing.node(60, 40, sequence: 1, span: 36)]
            var edges = [Testing.edge(0, 1, labelWidth: 40, labelHeight: 20), Testing.edge(0, 1, labelWidth: 50, labelHeight: 20), Testing.edge(0, 1)]
            var options = Testing.options
            options.headRoom = headRoom
            Testing.lay(&nodes, &edges, options: options)
            return edges
        }
        XCTAssertEqual(lay(headRoom: 0)[0].labelCenter.y, (40 + 108) / 2, accuracy: 1e-5)
        let edges = lay(headRoom: 8)
        XCTAssertEqual(edges[0].labelCenter.y, (40 + 108 - 8) / 2, accuracy: 1e-5)
        XCTAssertEqual(edges[1].labelCenter.y, edges[0].labelCenter.y, accuracy: 1e-5)
        let first = Testing.flat(edges[0])
        let bare = Testing.flat(edges[2])
        XCTAssertEqual(first[7] - first[4], 20, accuracy: 1e-5)
        XCTAssertEqual(bare[7] - bare[4], 10, accuracy: 1e-5)
        XCTAssertEqual((bare[4] + bare[7]) / 2, edges[0].labelCenter.y, accuracy: 1e-5)
    }

    func testAnEdgeRunningFarAcrossTurnsAtALevelWhereAShorterOneWouldRunBesideIt() {
        var nodes = (0..<5).map { index in Testing.node(80, 40, sequence: index, span: 56) }
        var edges = [(0, 1), (0, 2), (0, 3), (1, 4), (2, 4), (3, 4), (4, 0)].map { source, target in Testing.edge(source, target) }
        Testing.lay(&nodes, &edges)
        let back = Testing.flat(edges[6])
        let count = back.count
        let level = back[count - 5]
        XCTAssertEqual(back[count - 8], level, accuracy: 1e-5)
        XCTAssertEqual(back[count - 6], back[count - 3], accuracy: 1e-5)
        XCTAssertGreaterThan(abs(back[count - 9] - back[count - 6]), 2 * 48)
        let down = Testing.flat(edges[2])
        XCTAssertLessThan(abs(down[0] - back[count - 3]), 20)
        XCTAssertEqual(down.count, 9)
        XCTAssertEqual(down[3], down[0], accuracy: 1e-5)
        XCTAssertGreaterThan(down[4], level - 0.01)
    }

    func testAnEndMovesAlongItsSideToLetItsEdgeRunStraightButNoNearerItsNeighbourThanAPitch() {
        var nodes = [Testing.node(400, 40, sequence: 0, span: 376)] + (1...4).map { index in Testing.node(40, 40, sequence: index, span: 16) }
        var edges = (1...4).map { child in Testing.edge(0, child) }
        Testing.lay(&nodes, &edges)
        for edge in edges { XCTAssertEqual(Testing.flat(edge)[0], Testing.flat(edge)[Testing.flat(edge).count - 3], accuracy: 1e-5) }
        var pairNodes = [Testing.node(200, 40, sequence: 0, span: 176), Testing.node(40, 40, sequence: 1, span: 16)]
        var pair = [Testing.edge(0, 1), Testing.edge(1, 0)]
        Testing.lay(&pairNodes, &pair)
        XCTAssertEqual(abs(Testing.flat(pair[0])[0] - Testing.flat(pair[1])[Testing.flat(pair[1]).count - 3]), 16, accuracy: 1e-5)
    }

    func testEdgesLeavingSideBySideMoveCloserBeforeTheyShareAPlace() {
        var nodes = [Testing.node(60, 40, sequence: 0, span: 36)] + (1...7).map { index in Testing.node(60, 40, sequence: index) }
        var edges = (1...7).map { child in Testing.edge(0, child) }
        Testing.lay(&nodes, &edges)
        let starts = edges.map { edge in Testing.flat(edge)[0] }.sorted()
        for index in 1..<starts.count { XCTAssertEqual(starts[index] - starts[index - 1], 6, accuracy: 1e-5) }
    }

    func testAnEdgeCrossesInOneCurveARankOnlyATwinPutThere() {
        func lay(twin: Bool) -> [LayeredCompoundEdge] {
            var nodes = (0..<4).map { index in Testing.node(60, 40, sequence: index, span: 36) }
            var edges = [Testing.edge(0, 1), Testing.edge(0, 2), Testing.edge(0, 3)] + (twin ? [Testing.edge(0, 3)] : [])
            Testing.lay(&nodes, &edges)
            return edges
        }
        let plain = lay(twin: false).map(Testing.flat)
        let twinned = lay(twin: true).map(Testing.flat)
        for route in twinned.prefix(2) { XCTAssertEqual(route.count, 6) }
        XCTAssertEqual(twinned[0][1], plain[0][1], accuracy: 1e-5)
        XCTAssertEqual(twinned[0][4], plain[0][4] + 2 * 28 + 12 - 48, accuracy: 1e-5)
        let one = twinned[2], other = twinned[3]
        XCTAssertGreaterThanOrEqual(abs(one[0] - other[0]), 8)
        XCTAssertGreaterThanOrEqual(abs(one[one.count - 3] - other[other.count - 3]), 8)
        func turnsAt(_ route: [Double]) -> Double { abs(route[3] - route[0]) < 0.01 ? route[4] : route[1] }
        XCTAssertGreaterThanOrEqual(abs(turnsAt(one) - turnsAt(other)), 10)
    }

    func testTwinEdgesKeepApartWhereTheirEndsCannot() {
        var nodes = [Testing.node(60, 40, sequence: 0), Testing.node(60, 40, sequence: 1)]
        var edges = [Testing.edge(0, 1), Testing.edge(0, 1)]
        Testing.lay(&nodes, &edges)
        let first = Testing.flat(edges[0]), second = Testing.flat(edges[1])
        XCTAssertEqual(first.count, 9)
        XCTAssertEqual(second.count, 9)
        XCTAssertEqual(first[0], second[0], accuracy: 1e-5)
        XCTAssertEqual(abs(first[3] - second[3]), 16, accuracy: 1e-5)
    }

    func testTheTracksOfAFanNestSoThatItsEdgesDoNotCross() {
        var nodes = [Testing.node(120, 40, sequence: 0, span: 96)] + (1...4).map { index in Testing.node(60, 40, sequence: index) }
        var edges = (1...4).map { child in Testing.edge(0, child) }
        var options = Testing.options
        options.runsOnTracks = true
        Testing.lay(&nodes, &edges, options: options)
        let center = nodes[0].x
        let left = edges.filter { edge in nodes[edge.target].x < center }.sorted { first, second in nodes[first.target].x < nodes[second.target].x }
        let right = edges.filter { edge in nodes[edge.target].x > center }.sorted { first, second in nodes[first.target].x > nodes[second.target].x }
        for side in [left, right] {
            for index in side.indices.dropFirst() { XCTAssertLessThan(Testing.flat(side[index - 1])[4], Testing.flat(side[index])[4]) }
        }
    }
}
