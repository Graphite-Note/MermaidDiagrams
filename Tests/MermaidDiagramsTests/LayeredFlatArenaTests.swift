/**
 * File: LayeredFlatArenaTests.swift
 * ---------------------------------
 * Layer: Tests
 * Description: The layered layout's link lists keep each key's links in order, and a layout run in a scratch arena
 *              that other layouts used, or within another use of it, gives what it gives in a fresh one.
 *
 * Authors: Bahey Shalash
 * Version: 0.2
 * Date: 24/11/2026
 */

import CoreGraphics
import XCTest
@testable import MermaidDiagrams

final class LayeredFlatArenaTests: XCTestCase {
    /// Each key's list holds its values in the order the links were added, as appending to an array per key would.
    func testLinkListsKeepTheOrderOfTheLinksOfEachKey() {
        var generator = LayeredWorkspaceGenerator(seed: 0xC0FF_EE11)
        let arena = DiagramScratchArena()
        for count in [1, 2, 7, 30] {
            let linkCount = Int.random(in: 0..<(4 * count), using: &generator)
            let keys = (0..<linkCount).map { _ in Int.random(in: 0..<count, using: &generator) }
            let values = (0..<linkCount).map { _ in Int.random(in: 0..<100, using: &generator) }
            var expected = [[Int]](repeating: [], count: count)
            for index in keys.indices { expected[keys[index]].append(values[index]) }
            let keySpan = arena.span(count: linkCount, repeating: 0)
            let valueSpan = arena.span(count: linkCount, repeating: 0)
            for index in keys.indices {
                keySpan[index] = keys[index]
                valueSpan[index] = values[index]
            }
            let lists = LayeredLinkLists(count: count, keys: keySpan, values: valueSpan, arena: arena)
            for key in 0..<count { XCTAssertEqual(Array(lists[key]), expected[key], "key \(key) of \(count)") }
        }
    }

    /// Flat layouts of many kinds of graph (labels, twin edges, offsets, ends spread along sides, held ends, groups,
    /// orders only, edges on tracks or straight), each run in the thread's arena after every layout before it, in two
    /// orders, or within another use of the arena that holds spans of its own, give exactly the places, routes, sizes and
    /// crossings each gives in an arena just released.
    func testLayoutInAUsedArenaMatchesALayoutInAFreshOne() {
        var generator = LayeredWorkspaceGenerator(seed: 0x1A7E_5EED)
        let graphs = (0..<60).map { index in Self.randomGraph(index, using: &generator) }
        let fresh = graphs.map { graph in
            DiagramScratchArena.releaseCurrentThreadArena()
            return Self.laidOut(graph)
        }
        for order in [Array(graphs.indices), graphs.indices.reversed()] {
            for index in order { XCTAssertEqual(Self.laidOut(graphs[index]), fresh[index], "graph \(index)") }
        }
        DiagramScratchArena.withCurrentThread { arena in
            let held = arena.span(count: 5_000, repeating: 7)
            for index in graphs.indices { XCTAssertEqual(Self.laidOut(graphs[index]), fresh[index], "nested graph \(index)") }
            XCTAssertTrue(held.allSatisfy { value in value == 7 })
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

    private static func laidOut(_ graph: Graph) -> Outcome {
        var nodes = graph.nodes
        var edges = graph.edges
        let result = LayeredFlatLayout.layout(nodes: &nodes, edges: &edges, options: graph.options)
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
