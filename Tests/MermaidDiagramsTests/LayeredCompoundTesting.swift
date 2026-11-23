/**
 * File: LayeredCompoundTesting.swift
 * ----------------------------------
 * Layer: Tests
 * Description: What the ports of Pele's layout tests share: its graphs, options, random numbers and routes as numbers.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 23/11/2026
 */

import CoreGraphics
@testable import MermaidDiagrams

/// Pele's helpers of tests/layout/compound.test.ts, its random numbers of tests/support/corpus.ts, and its routes as
/// it writes them: x, y and axis (0 where the edge runs into the point vertically, 1 horizontally) one after the other,
/// so that the tests read the indices Pele's do.
enum LayeredCompoundTesting {
    static let options = LayeredFlatOptions(nodeSeparation: 40, edgeSeparation: 16, rankSeparation: 48, portSeparation: 20)
    static let directions: [LayeredDirection] = [.topToBottom, .bottomToTop, .leftToRight, .rightToLeft]

    /// Pele's `random`: a linear congruential generator over 32 bits.
    struct Random {
        private var state: UInt32

        init(seed: Int) { state = UInt32(truncatingIfNeeded: seed) }

        mutating func next() -> Double {
            state = state &* 1_664_525 &+ 1_013_904_223
            return Double(state) / 4_294_967_296
        }

        mutating func below(_ count: Int) -> Int { below(Double(count)) }

        /// Pele's `int`: `Math.floor(rnd() * limit)`.
        mutating func below(_ limit: Double) -> Int { Int((next() * limit).rounded(.down)) }
    }

    static func node(_ width: Double, _ height: Double, parent: Int = -1, sequence: Int = 0, span: Double = 0) -> LayeredCompoundNode {
        var node = LayeredCompoundNode(width: width, height: height, parent: parent)
        node.sequence = Double(sequence)
        node.sideSpan = span
        return node
    }

    static func group(sequence: Int, parent: Int = -1) -> LayeredCompoundNode {
        var group = LayeredCompoundNode(width: 0, height: 0, parent: parent)
        group.isGroup = true
        group.paddingSide = 20
        group.paddingTop = 40
        group.paddingBottom = 20
        group.sideSpan = .infinity
        group.sequence = Double(sequence)
        return group
    }

    static func edge(_ source: Int, _ target: Int, labelWidth: Double = 0, labelHeight: Double = 0) -> LayeredCompoundEdge {
        LayeredCompoundEdge(source: source, target: target, labelWidth: labelWidth, labelHeight: labelHeight)
    }

    @discardableResult
    static func lay(_ nodes: inout [LayeredCompoundNode], _ edges: inout [LayeredCompoundEdge], _ direction: LayeredDirection = .topToBottom,
                    options: LayeredFlatOptions = options) -> (width: Double, height: Double) {
        LayeredCompoundLayout.layout(nodes: &nodes, edges: &edges, rootDirection: direction, options: options) ?? (0, 0)
    }

    /// The route as Pele writes it.
    static func flat(_ edge: LayeredCompoundEdge) -> [Double] {
        edge.route.flatMap { point in [point.point.x, point.point.y, point.runsHorizontally ? 1 : 0] }
    }

    /// A route written as Pele writes it.
    static func route(_ numbers: [Double]) -> [LayeredRoutePoint] {
        stride(from: 0, to: numbers.count, by: 3).map { index in
            LayeredRoutePoint(point: CGPoint(x: numbers[index], y: numbers[index + 1]), runsHorizontally: numbers[index + 2] == 1)
        }
    }

    static func isOnBorder(_ node: LayeredCompoundNode, _ x: Double, _ y: Double) -> Bool {
        let distanceX = abs(x - node.x)
        let distanceY = abs(y - node.y)
        let isInside = distanceX <= node.width / 2 + 0.5 && distanceY <= node.height / 2 + 0.5
        return isInside && (abs(distanceX - node.width / 2) <= 0.5 || abs(distanceY - node.height / 2) <= 0.5)
    }

    static func isAncestor(_ nodes: [LayeredCompoundNode], _ ancestor: Int, of node: Int) -> Bool {
        var parent = nodes[node].parent
        while parent >= 0 {
            if parent == ancestor { return true }
            parent = nodes[parent].parent
        }
        return false
    }

    /// Pele's `randomGraph`: up to four groups, 3 to 32 nodes, edges between any two (some labelled); every other
    /// graph lets edges spread along its nodes' sides.
    static func randomGraph(seed: Int) -> (nodes: [LayeredCompoundNode], edges: [LayeredCompoundEdge], direction: LayeredDirection) {
        var random = Random(seed: seed)
        var nodes: [LayeredCompoundNode] = []
        var groups: [Int] = []
        let groupCount = random.below(5)
        for group in 0..<groupCount {
            var parent = -1
            if !groups.isEmpty && random.next() < 0.4 { parent = groups[random.below(groups.count)] }
            var node = self.group(sequence: 1000 + group, parent: parent)
            node.sideSpan = 0
            node.minimumWidth = 60
            node.direction = random.next() < 0.3 ? directions[random.below(4)] : nil
            if seed % 2 == 0 { node.sideSpan = .infinity }
            groups.append(nodes.count)
            nodes.append(node)
        }
        let leaves = 3 + random.below(30)
        for leaf in 0..<leaves {
            var parent = -1
            if !groups.isEmpty && random.next() < 0.5 { parent = groups[random.below(groups.count)] }
            let width = Double(30 + random.below(120))
            let height = Double(30 + random.below(50))
            nodes.append(node(width, height, parent: parent, sequence: leaf, span: seed % 2 == 0 ? min(width, height) - 24 : 0))
        }
        var edges: [LayeredCompoundEdge] = []
        let count = random.below(leaves * 2)
        for _ in 0..<count {
            let isLabelled = random.next() < 0.3
            let source = random.below(nodes.count)
            let target = random.below(nodes.count)
            edges.append(edge(source, target, labelWidth: isLabelled ? Double(20 + random.below(60)) : 0, labelHeight: isLabelled ? 24 : 0))
        }
        return (nodes, edges, directions[random.below(4)])
    }
}
