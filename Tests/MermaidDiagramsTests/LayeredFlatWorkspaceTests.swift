/**
 * File: LayeredFlatWorkspaceTests.swift
 * -------------------------------------
 * Layer: Tests
 * Description: The layered layout's workspace hands out lists that hold exactly what was asked, never changes a list
 *              still held elsewhere, and a layout run in a workspace other layouts used gives what a fresh one gives.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 23/11/2026
 */

import CoreGraphics
import XCTest
@testable import MermaidDiagrams

final class LayeredFlatWorkspaceTests: XCTestCase {
    /// Lists given back longer, shorter and full of other values come out again as long as asked, every element the
    /// value asked for; an empty list asked for is empty, with the room asked for.
    func testTakenListsHoldExactlyWhatWasAskedWhateverWasGivenBack() {
        let workspace = LayeredFlatWorkspace()
        for length in [0, 1, 5, 40, 3, 200, 17] {
            workspace.recycle(Array(repeating: 7, count: length) + [-3, 9])
            workspace.recycle([Double](repeating: .nan, count: length + 1))
            workspace.recycle([Bool](repeating: true, count: length + 2))
        }
        for count in [0, 1, 2, 4, 39, 41, 199, 300, 16] {
            XCTAssertEqual(workspace.integers(count: count, repeating: -1), [Int](repeating: -1, count: count))
            XCTAssertEqual(workspace.numbers(count: count, repeating: 0.5), [Double](repeating: 0.5, count: count))
            XCTAssertEqual(workspace.flags(count: count, repeating: false), [Bool](repeating: false, count: count))
            XCTAssertEqual(workspace.kinds(count: count, repeating: .label), [LayeredVertexKind](repeating: .label, count: count))
            let empty = workspace.emptyIntegers(capacity: count)
            XCTAssertTrue(empty.isEmpty)
            XCTAssertGreaterThanOrEqual(empty.capacity, count)
            XCTAssertTrue(workspace.emptyNumbers(capacity: count).isEmpty)
            XCTAssertTrue(workspace.emptyEnds(capacity: count).isEmpty)
        }
    }

    /// A list given back while another holder still has it is copied by the next taker's first change, so the other
    /// holder's elements stay as they were.
    func testListStillHeldElsewhereIsNeverChanged() {
        let workspace = LayeredFlatWorkspace()
        let held = Array(0..<50)
        workspace.recycle(held)
        var taken = workspace.integers(count: 50, repeating: 9)
        taken[0] = -1
        XCTAssertEqual(held, Array(0..<50))
        XCTAssertEqual(taken.dropFirst(), ArraySlice(repeating: 9, count: 49))
    }

    /// Each key's list holds its values in the order the links were added, as appending to an array per key would.
    func testLinkListsKeepTheOrderOfTheLinksOfEachKey() {
        var generator = LayeredWorkspaceGenerator(seed: 0xC0FF_EE11)
        let workspace = LayeredFlatWorkspace()
        for count in [1, 2, 7, 30] {
            let linkCount = Int.random(in: 0..<(4 * count), using: &generator)
            let keys = (0..<linkCount).map { _ in Int.random(in: 0..<count, using: &generator) }
            let values = (0..<linkCount).map { _ in Int.random(in: 0..<100, using: &generator) }
            var expected = [[Int]](repeating: [], count: count)
            for index in keys.indices { expected[keys[index]].append(values[index]) }
            let lists = LayeredLinkLists(count: count, keys: keys, values: values, workspace: workspace)
            for key in 0..<count { XCTAssertEqual(Array(lists[key]), expected[key], "key \(key) of \(count)") }
            lists.recycle(into: workspace)
        }
    }

    /// Flat layouts of many kinds of graph (labels, twin edges, offsets, ends spread along sides, held ends, groups,
    /// orders only, edges on tracks or straight), each in a workspace that every layout before it used, in two orders,
    /// give exactly the places, routes, sizes and crossings each gives in a workspace of its own.
    func testLayoutInAUsedWorkspaceMatchesALayoutInAFreshOne() {
        var generator = LayeredWorkspaceGenerator(seed: 0x1A7E_5EED)
        let graphs = (0..<60).map { index in Self.randomGraph(index, using: &generator) }
        let fresh = graphs.map { graph in Self.laidOut(graph, workspace: nil) }
        for order in [Array(graphs.indices), graphs.indices.reversed()] {
            let shared = LayeredFlatWorkspace()
            for index in order {
                XCTAssertEqual(Self.laidOut(graphs[index], workspace: shared), fresh[index], "graph \(index)")
            }
        }
    }

    private struct Graph {
        var nodes: [LayeredFlatNode]
        var edges: [LayeredFlatEdge]
        var options: LayeredFlatOptions
    }

    /// What a layout gives that callers read.
    private struct Outcome: Equatable {
        var result: LayeredFlatResult?
        var places: [CGPoint]
        var ranks: [Int]
        var routes: [[CGPoint]]
        var labelCenters: [CGPoint]
        var offsets: [Double]
    }

    private static func laidOut(_ graph: Graph, workspace: LayeredFlatWorkspace?) -> Outcome {
        var nodes = graph.nodes
        var edges = graph.edges
        let result = LayeredFlatLayout.layout(nodes: &nodes, edges: &edges, options: graph.options, workspace: workspace)
        return Outcome(result: result, places: nodes.map { node in CGPoint(x: node.x, y: node.y) }, ranks: nodes.map(\.rank),
                       routes: edges.map(\.points), labelCenters: edges.map(\.labelCenter),
                       offsets: edges.flatMap { edge in [edge.tailOffset, edge.headOffset] })
    }

    private static func randomGraph(_ index: Int, using generator: inout LayeredWorkspaceGenerator) -> Graph {
        let nodeCount = Int.random(in: 1...18, using: &generator)
        var nodes = (0..<nodeCount).map { _ in
            LayeredFlatNode(width: Double(Int.random(in: 10...90, using: &generator)), height: Double(Int.random(in: 10...50, using: &generator)))
        }
        let spreads = index % 3 == 0
        if spreads { for node in nodes.indices { nodes[node].sideSpan = nodes[node].width * 0.8 } }
        var edges: [LayeredFlatEdge] = []
        for _ in 0..<Int.random(in: 0...(2 * nodeCount), using: &generator) where nodeCount > 1 {
            let tail = Int.random(in: 0..<nodeCount, using: &generator)
            var head = Int.random(in: 0..<nodeCount, using: &generator)
            if head == tail { head = (tail + 1) % nodeCount }
            let isLabelled = index % 4 == 1 && Bool.random(using: &generator)
            var edge = LayeredFlatEdge(tail: tail, head: head, minimumLength: Int.random(in: 1...2, using: &generator),
                                       labelWidth: isLabelled ? 30 : 0, labelHeight: isLabelled ? 14 : 0)
            if index % 5 == 2 { edge.tailOffset = Double(Int.random(in: -8...8, using: &generator)) }
            if spreads { edge.isHeadHeld = Bool.random(using: &generator) }
            edges.append(edge)
        }
        var options = LayeredCompoundTesting.options
        options.runsOnTracks = index % 6 == 4
        options.isStraight = index % 7 == 5
        if index % 8 == 3 {
            options.groupOfNode = (0..<nodeCount).map { node in node % 3 == 0 ? -1 : node % 2 }
            options.parentOfGroup = [-1, 0]
            options.ordersOnly = index % 16 == 3
        }
        return Graph(nodes: nodes, edges: edges, options: options)
    }
}

/// SplitMix64, so that the graphs are the same on every run.
private struct LayeredWorkspaceGenerator: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var mixed = state
        mixed = (mixed ^ (mixed >> 30)) &* 0xBF58_476D_1CE4_E5B9
        mixed = (mixed ^ (mixed >> 27)) &* 0x94D0_49BB_1331_11EB
        return mixed ^ (mixed >> 31)
    }
}
