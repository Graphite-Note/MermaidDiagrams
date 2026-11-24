/**
 * File: LayeredRouteCrossingsEquivalenceTests.swift
 * -------------------------------------------------
 * Layer: Tests
 * Description: The route crossing count on the scratch arena counts what the 0.7.0 count counts: every count the
 *              corpora's compound layouts ask for, and random routes of every style with shared ends and straight runs.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 24/11/2026
 */

import CoreGraphics
import XCTest
@testable import MermaidDiagrams

final class LayeredRouteCrossingsEquivalenceTests: XCTestCase {
    /// Every set of routes the corpora's compound layouts counted the crossings of, counted again by both.
    func testEveryCountOfTheCorporaMatchesTheReference() throws {
        let recording = try LayeredCorpusRecording.shared()
        XCTAssertGreaterThan(recording.routeCrossings.count, 20)
        for (index, input) in recording.routeCrossings.enumerated() {
            XCTAssertEqual(LayeredRouteCrossings.count(nodes: input.nodes, edges: input.edges, style: input.style),
                           ReferenceLayeredRouteCrossings.count(nodes: input.nodes, edges: input.edges, style: input.style), "count \(index)")
        }
    }

    /// Random routes in each style, on a small grid so that pieces cross, share ends, run along each other and repeat
    /// points; edges from a node to itself and routes of one point among them.
    func testRandomRoutesCountAsTheReferenceCounts() {
        var generator = LayeredEquivalenceGenerator(seed: 0xC2_055E5)
        let styles: [LayeredRouteStyle] = [.curved, .stepped, .linear]
        for index in 0..<300 {
            let nodeCount = Int.random(in: 1...8, using: &generator)
            var nodes: [LayeredCompoundNode] = []
            for _ in 0..<nodeCount {
                var node = LayeredCompoundNode(width: Double(Int.random(in: 0...40, using: &generator)), height: Double(Int.random(in: 0...30, using: &generator)))
                node.x = Double(Int.random(in: 0...10, using: &generator) * 20)
                node.y = Double(Int.random(in: 0...10, using: &generator) * 20)
                nodes.append(node)
            }
            var edges: [LayeredCompoundEdge] = []
            for _ in 0..<Int.random(in: 0...14, using: &generator) {
                let source = Int.random(in: 0..<nodeCount, using: &generator)
                var edge = LayeredCompoundEdge(source: source, target: Bool.random(using: &generator) ? source : Int.random(in: 0..<nodeCount, using: &generator))
                let pointCount = Int.random(in: 0...6, using: &generator)
                edge.route = (0..<pointCount).map { _ in
                    LayeredRoutePoint(point: CGPoint(x: Int.random(in: 0...8, using: &generator) * 25, y: Int.random(in: 0...8, using: &generator) * 25),
                                      runsHorizontally: Bool.random(using: &generator))
                }
                edges.append(edge)
            }
            let style = styles[index % 3]
            XCTAssertEqual(LayeredRouteCrossings.count(nodes: nodes, edges: edges, style: style),
                           ReferenceLayeredRouteCrossings.count(nodes: nodes, edges: edges, style: style), "random routes \(index)")
        }
    }
}
