/**
 * File: LayeredCompoundGroupTests.swift
 * -------------------------------------
 * Layer: Tests
 * Description: Pele's tests of groups, tracks and route crossings in its compound layout, and of its flat layout's order.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 23/11/2026
 */

import XCTest
@testable import MermaidDiagrams

final class LayeredCompoundGroupTests: XCTestCase {
    private typealias Testing = LayeredCompoundTesting

    private func placed(_ x: Double, _ y: Double) -> LayeredCompoundNode {
        var node = Testing.node(40, 40)
        node.x = x
        node.y = y
        return node
    }

    private func routed(_ source: Int, _ target: Int, _ route: [Double]) -> LayeredCompoundEdge {
        var edge = Testing.edge(source, target)
        edge.route = Testing.route(route)
        return edge
    }

    func testRouteCrossingsCountWhereRoutesCrossButNotAFanOutOfOneNode() {
        let nodes = (0..<4).map { index in placed(Double(100 * (index % 2)), Double(200 * (index / 2))) }
        let crossed = [routed(0, 3, [0, 20, 0, 100, 180, 0]), routed(1, 2, [100, 20, 0, 0, 180, 0])]
        XCTAssertEqual(LayeredRouteCrossings.count(nodes: nodes, edges: crossed, style: .curved), 1)
        let fan = [routed(0, 2, [10, 20, 0, 0, 180, 0]), routed(0, 3, [-10, 20, 0, 100, 180, 0])]
        XCTAssertEqual(LayeredRouteCrossings.count(nodes: nodes, edges: fan, style: .curved), 0)
    }

    /// Pele's issue 3: two chains in groups of their own feed a store in a third group.
    private func fanIn() -> (nodes: [LayeredCompoundNode], edges: [LayeredCompoundEdge]) {
        var nodes = [Testing.group(sequence: 100), Testing.group(sequence: 101), Testing.group(sequence: 102), Testing.node(80, 60, parent: 2)]
        var edges: [LayeredCompoundEdge] = []
        for group in [0, 1] {
            for index in 0..<5 {
                let vertex = nodes.count
                nodes.append(Testing.node(40, 40, parent: group, sequence: vertex))
                if index > 0 { edges.append(Testing.edge(vertex - 1, vertex)) }
                edges.append(Testing.edge(vertex, 3))
            }
        }
        return (nodes, edges)
    }

    func testEdgesJoiningOneStraightRunIntoTheirNodeAreNotCrossings() {
        let nodes = [placed(0, 0), placed(100, 0), placed(50, 300)]
        let edges = [routed(0, 2, [0, 20, 0, 0, 200, 0, 50, 200, 0, 50, 280, 0]), routed(1, 2, [100, 20, 0, 100, 150, 0, 50, 150, 0, 50, 280, 0])]
        XCTAssertEqual(LayeredRouteCrossings.count(nodes: nodes, edges: edges, style: .curved), 0)
        var (fan, into) = fanIn()
        var options = Testing.options
        options.runsOnTracks = true
        Testing.lay(&fan, &into, options: options)
        XCTAssertEqual(LayeredRouteCrossings.count(nodes: fan, edges: into, style: .curved), 0)
    }

    func testCrossingsAreCountedWhereTheDrawingHasThemRoundItsCornersOrAtItsSteps() {
        let nodes = [placed(0, -20), placed(120, 100), placed(5, 170), placed(5, 40)]
        let corner = [routed(0, 1, [0, 0, 0, 0, 100, 0, 100, 100, 1]), routed(2, 3, [5, 150, 0, 5, 60, 0])]
        XCTAssertEqual(LayeredRouteCrossings.count(nodes: nodes, edges: corner, style: .curved), 0)
        XCTAssertEqual(LayeredRouteCrossings.count(nodes: nodes, edges: corner, style: .stepped), 1)
        XCTAssertEqual(LayeredRouteCrossings.count(nodes: nodes, edges: corner, style: .linear), 1)
        var (fan, into) = fanIn()
        Testing.lay(&fan, &into)
        XCTAssertLessThanOrEqual(LayeredRouteCrossings.count(nodes: fan, edges: into, style: .curved), 4)
    }

    func testThePortsOnTheFarSideOfAGroupGoInTheOrderOfWhereTheirEdgesGo() {
        for direction in [LayeredDirection.topToBottom, .leftToRight] {
            var nodes = [Testing.group(sequence: 100), Testing.group(sequence: 101), Testing.group(sequence: 102), Testing.node(80, 40, parent: 2, sequence: 3, span: 72)]
            var edges: [LayeredCompoundEdge] = []
            for group in [0, 1] {
                for index in 0..<5 {
                    let vertex = nodes.count
                    nodes.append(Testing.node(100, 40, parent: group, sequence: vertex, span: 72))
                    if index > 0 { edges.append(Testing.edge(vertex - 1, vertex)) }
                    edges.append(Testing.edge(vertex, 3))
                }
            }
            Testing.lay(&nodes, &edges, direction)
            let across = direction == .topToBottom ? 0 : 1
            func at(_ edge: LayeredCompoundEdge, _ group: Int) -> Double {
                let route = Testing.flat(edge)
                for index in stride(from: 0, to: route.count, by: 3) where Testing.isOnBorder(nodes[group], route[index], route[index + 1]) {
                    return route[index + across]
                }
                return .nan
            }
            let fan = edges.filter { edge in edge.target == 3 }
            let leave = fan.map { edge in at(edge, nodes[edge.source].parent) }
            let enter = fan.map { edge in at(edge, 2) }
            for first in fan.indices {
                XCTAssertFalse(leave[first].isNaN || enter[first].isNaN, "\(direction) edge \(first)")
                for second in fan.indices where second > first {
                    XCTAssertEqual((leave[first] - leave[second]).sign, (enter[first] - enter[second]).sign, "\(direction) edges \(first) and \(second)")
                }
            }
        }
    }

    func testAnEdgeRunsStraightAcrossTheGapBetweenAGroupBorderAndTheNodeItMeetsInside() {
        for direction in [LayeredDirection.topToBottom, .leftToRight] {
            var nodes = [Testing.group(sequence: 100), Testing.group(sequence: 101)]
            let from = (0..<3).map { _ in nodes.append(Testing.node(60, 30, parent: 0)); return nodes.count - 1 }
            let to = (0..<5).map { _ in nodes.append(Testing.node(60, 30, parent: 1)); return nodes.count - 1 }
            for index in 2..<nodes.count {
                nodes[index].sequence = Double(index)
                nodes[index].sideSpan = min(nodes[index].width, nodes[index].height) - 8
            }
            var edges = to.flatMap { target in from.map { source in Testing.edge(source, target, labelWidth: 40, labelHeight: 16) } }
            Testing.lay(&nodes, &edges, direction)
            let across = direction == .topToBottom ? 0 : 1
            for (index, edge) in edges.enumerated() {
                let route = Testing.flat(edge)
                let last = route.count - 3
                var position = 0
                while position < last && !Testing.isOnBorder(nodes[1], route[position], route[position + 1]) { position += 3 }
                XCTAssertLessThan(position, last, "\(direction) edge \(index) enters its group")
                XCTAssertEqual(route[position + across], route[last + across], accuracy: 1e-5, "\(direction) edge \(index) enters")
                position = last
                while position > 0 && !Testing.isOnBorder(nodes[0], route[position], route[position + 1]) { position -= 3 }
                XCTAssertGreaterThan(position, 0, "\(direction) edge \(index) leaves its group")
                XCTAssertEqual(route[position + across], route[across], accuracy: 1e-5, "\(direction) edge \(index) leaves")
            }
        }
    }

    func testEdgesStayStraightWhenTheirEndsOnANodeAreLessThanATwinApart() {
        var nodes = [Testing.group(sequence: 100), Testing.node(48, 48, parent: 0, sequence: 1, span: 24), Testing.node(70, 66, parent: 0, sequence: 2, span: 0.995),
                     Testing.node(48, 48, sequence: 3, span: 24)]
        var edges = [Testing.edge(1, 2, labelWidth: 40, labelHeight: 16), Testing.edge(2, 3), Testing.edge(3, 2)]
        Testing.lay(&nodes, &edges)
        for edge in edges.dropFirst() {
            let across = stride(from: 0, to: Testing.flat(edge).count, by: 3).map { index in Testing.flat(edge)[index] }
            let low = min(across[0], across[across.count - 1])
            let high = max(across[0], across[across.count - 1])
            for place in across {
                XCTAssertGreaterThanOrEqual(place, low - 1)
                XCTAssertLessThanOrEqual(place, high + 1)
            }
        }
    }

    func testTheNodesOfARowOfGroupsAreOrderedAsOneDrawingSoThatTheirEdgesDoNotCross() {
        var nodes = [Testing.group(sequence: 100), Testing.group(sequence: 101), Testing.group(sequence: 102)]
        func stage(_ group: Int) -> [Int] {
            (0..<5).map { _ in
                nodes.append(Testing.node(80, 40, parent: group, sequence: nodes.count + 1))
                return nodes.count - 1
            }
        }
        let first = stage(0), second = stage(1), third = stage(2)
        var edges = [4, 2, 0, 3, 1].enumerated().map { index, target in Testing.edge(first[index], second[target]) }
        edges += [1, 3, 0, 4, 2].enumerated().map { index, target in Testing.edge(second[index], third[target]) }
        Testing.lay(&nodes, &edges, .leftToRight)
        XCTAssertEqual(LayeredRouteCrossings.count(nodes: nodes, edges: edges, style: .curved), 0)
    }

    func testAFlatLayoutKeepsItsGroupsContiguousAndCountsTheCrossingsOfItsOrder() {
        var nodes = (0..<6).map { _ in LayeredFlatNode(width: 40, height: 40) }
        let groupOfNode = [0, 1, 0, -1, 0, -1]
        var edges = [(0, 4), (1, 4), (2, 5), (3, 4), (3, 5)].map { tail, head in LayeredFlatEdge(tail: tail, head: head) }
        var options = Testing.options
        options.groupOfNode = groupOfNode
        options.parentOfGroup = [-1, -1]
        options.ordersOnly = true
        let result = LayeredFlatLayout.layout(nodes: &nodes, edges: &edges, options: options)
        // Points are (rank, position across) pairs.
        var pieces: [(rank: Double, from: Double, to: Double)] = []
        for edge in edges { for index in edge.points.indices.dropFirst() { pieces.append((edge.points[index - 1].x, edge.points[index - 1].y, edge.points[index].y)) } }
        var crossed = 0
        for first in pieces.indices {
            for second in pieces.indices where second > first && pieces[first].rank == pieces[second].rank {
                if (pieces[first].from - pieces[second].from) * (pieces[first].to - pieces[second].to) < 0 { crossed += 1 }
            }
        }
        XCTAssertEqual(result?.crossings, crossed)
        for first in nodes.indices where groupOfNode[first] >= 0 {
            for second in nodes.indices where groupOfNode[second] == groupOfNode[first] && nodes[first].rank == nodes[second].rank && nodes[first].x < nodes[second].x {
                for between in nodes.indices where nodes[between].rank == nodes[first].rank && nodes[between].x > nodes[first].x && nodes[between].x < nodes[second].x {
                    XCTAssertEqual(groupOfNode[between], groupOfNode[first], "node \(between) between \(first) and \(second)")
                }
            }
        }
    }
}
