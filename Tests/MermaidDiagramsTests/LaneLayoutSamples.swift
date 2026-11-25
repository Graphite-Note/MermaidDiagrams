/**
 * File: LaneLayoutSamples.swift
 * -----------------------------
 * Layer: Tests
 * Description: Graphs in lanes to compare lane layouts on: random ones of every shape the layout takes (nodes in lanes,
 *              in groups inside lanes and outside every lane, empty groups, edges to groups and lanes, loops, texts,
 *              long spans), and hostile ones (thousands of passing points, deep nesting, many parallel handoffs, groups
 *              inside each other, work past the routing budget).
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 24/11/2026
 */

import CoreGraphics
@testable import MermaidDiagrams

enum LaneLayoutSamples {
    /// A small seeded generator, so that each seed makes the same graph.
    struct SeededNumbers {
        var state: UInt64

        mutating func below(_ bound: Int) -> Int {
            state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            return Int((state >> 33) % UInt64(max(bound, 1)))
        }

        mutating func chance(_ share: Double) -> Bool { Double(below(1_000_000)) / 1_000_000 < share }
    }

    static let directions: [LayeredDirection] = [.topToBottom, .bottomToTop, .leftToRight, .rightToLeft]

    /// Up to 40 nodes, 5 lanes and 4 groups inside lanes or other groups, some empty, up to 60 edges between any boxes.
    static func randomGraph(seed: UInt64) -> LaneLayoutGraph {
        var numbers = SeededNumbers(state: seed &* 2_654_435_761)
        var graph = LaneLayoutGraph(boxes: [], edges: [], direction: directions[numbers.below(4)], lanePadding: numbers.chance(0.5) ? 24 : 12)
        let laneCount = numbers.below(6)
        var lanes: [Int] = []
        for _ in 0..<laneCount {
            lanes.append(graph.boxes.count)
            graph.boxes.append(group(&numbers, in: nil))
        }
        var groups = lanes
        for _ in 0..<numbers.below(5) where !groups.isEmpty {
            let parent = groups[numbers.below(groups.count)]
            groups.append(graph.boxes.count)
            graph.boxes.append(group(&numbers, in: parent))
        }
        for _ in 0..<(1 + numbers.below(40)) {
            let parent: Int? = groups.isEmpty || numbers.chance(0.08) ? nil : groups[numbers.below(groups.count)]
            graph.boxes.append(LaneLayoutBox(size: CGSize(width: CGFloat(20 + numbers.below(140)), height: CGFloat(20 + numbers.below(70))),
                                             parent: parent, isGroup: false))
        }
        if numbers.chance(0.5) { graph.boxes.reverse(); renumberParents(&graph, count: graph.boxes.count) }
        for _ in 0..<numbers.below(61) {
            let source = numbers.below(graph.boxes.count)
            let target = numbers.chance(0.05) ? source : numbers.below(graph.boxes.count)
            let label: CGSize? = numbers.chance(0.3) ? CGSize(width: CGFloat(numbers.below(90)), height: CGFloat(12 + numbers.below(30))) : nil
            graph.edges.append(LaneLayoutEdge(source: source, target: target, minimumRankSpan: 1 + (numbers.chance(0.2) ? numbers.below(3) : 0), labelSize: label))
        }
        return graph
    }

    /// The boxes listed in reverse: each parent renumbered to where its box went.
    private static func renumberParents(_ graph: inout LaneLayoutGraph, count: Int) {
        for index in graph.boxes.indices { graph.boxes[index].parent = graph.boxes[index].parent.map { parent in count - 1 - parent } }
    }

    private static func group(_ numbers: inout SeededNumbers, in parent: Int?) -> LaneLayoutBox {
        let side = CGFloat(8 + numbers.below(20))
        return LaneLayoutBox(size: .zero, parent: parent, isGroup: true,
                             padding: LayeredClusterPadding(side: side, top: CGFloat(16 + numbers.below(40)), bottom: side),
                             minimumWidth: CGFloat(numbers.below(200)))
    }

    static func node(_ parent: Int?, width: CGFloat = 80, height: CGFloat = 40) -> LaneLayoutBox {
        LaneLayoutBox(size: CGSize(width: width, height: height), parent: parent, isGroup: false)
    }

    static func lane() -> LaneLayoutBox {
        LaneLayoutBox(size: .zero, parent: nil, isGroup: true, padding: LayeredClusterPadding(side: 20, top: 36, bottom: 20), minimumWidth: 60)
    }

    static func hostileGraphs() -> [LaneLayoutGraph] {
        [manyPassingPoints(), deepNesting(), parallelHandoffs(), groupsInsideEachOther(), wideRank(), pastTheRoutingBudget()]
    }

    /// A chain of 300 steps in one lane and 100 edges from its start to its end in another: more than 20,000 passing
    /// points, so every edge is laid out direct.
    static func manyPassingPoints() -> LaneLayoutGraph {
        var graph = LaneLayoutGraph(boxes: [lane(), lane()], edges: [], direction: .topToBottom)
        for step in 0..<300 {
            graph.boxes.append(node(0))
            if step > 0 { graph.edges.append(LaneLayoutEdge(source: graph.boxes.count - 2, target: graph.boxes.count - 1, minimumRankSpan: 1, labelSize: nil)) }
        }
        for index in 0..<100 {
            graph.boxes.append(node(1))
            graph.edges.append(LaneLayoutEdge(source: 2 + index % 3, target: graph.boxes.count - 1, minimumRankSpan: 1, labelSize: nil))
            graph.edges.append(LaneLayoutEdge(source: graph.boxes.count - 1, target: 299, minimumRankSpan: 1,
                                              labelSize: index.isMultiple(of: 4) ? CGSize(width: 40, height: 20) : nil))
        }
        return graph
    }

    /// Sixty groups inside each other in a lane, a node in the deepest and one beside the lane.
    static func deepNesting() -> LaneLayoutGraph {
        var graph = LaneLayoutGraph(boxes: [lane(), lane()], edges: [], direction: .leftToRight)
        for _ in 0..<60 { graph.boxes.append(LaneLayoutBox(size: .zero, parent: graph.boxes.count - 1 == 1 ? 0 : graph.boxes.count - 1, isGroup: true,
                                                           padding: LayeredClusterPadding(side: 4, top: 10, bottom: 4), minimumWidth: 30)) }
        graph.boxes.append(node(graph.boxes.count - 1))
        graph.boxes.append(node(1))
        graph.edges = [LaneLayoutEdge(source: graph.boxes.count - 2, target: graph.boxes.count - 1, minimumRankSpan: 1, labelSize: CGSize(width: 30, height: 18)),
                       LaneLayoutEdge(source: graph.boxes.count - 1, target: 30, minimumRankSpan: 1, labelSize: nil)]
        return graph
    }

    /// Two hundred handoffs between the same two steps, some with text, both ways.
    static func parallelHandoffs() -> LaneLayoutGraph {
        var graph = LaneLayoutGraph(boxes: [lane(), lane(), node(0), node(1), node(1)], edges: [], direction: .bottomToTop)
        for index in 0..<200 {
            let forward = index.isMultiple(of: 3)
            graph.edges.append(LaneLayoutEdge(source: forward ? 2 : 3, target: forward ? 3 : 2, minimumRankSpan: 1 + index % 2,
                                              labelSize: index.isMultiple(of: 5) ? CGSize(width: 50, height: 20) : nil))
        }
        graph.edges.append(LaneLayoutEdge(source: 3, target: 4, minimumRankSpan: 1, labelSize: nil))
        return graph
    }

    /// Two groups, each inside the other, holding nodes linked across lanes.
    static func groupsInsideEachOther() -> LaneLayoutGraph {
        var graph = LaneLayoutGraph(boxes: [lane(), lane(), LaneLayoutBox(size: .zero, parent: 3, isGroup: true), LaneLayoutBox(size: .zero, parent: 2, isGroup: true),
                                            node(2), node(3), node(1)], edges: [], direction: .rightToLeft)
        graph.edges = [LaneLayoutEdge(source: 4, target: 5, minimumRankSpan: 1, labelSize: nil), LaneLayoutEdge(source: 5, target: 6, minimumRankSpan: 2, labelSize: nil),
                       LaneLayoutEdge(source: 6, target: 2, minimumRankSpan: 1, labelSize: nil)]
        return graph
    }

    /// Five hundred steps in three lanes with no edges: one wide rank.
    static func wideRank() -> LaneLayoutGraph {
        var graph = LaneLayoutGraph(boxes: [lane(), lane(), lane()], edges: [], direction: .topToBottom)
        for index in 0..<500 { graph.boxes.append(node(index % 3, width: CGFloat(20 + index % 50))) }
        return graph
    }

    /// Eight hundred steps and as many handoffs: more work than routing is allowed, so nothing takes a route of its own.
    static func pastTheRoutingBudget() -> LaneLayoutGraph {
        var graph = LaneLayoutGraph(boxes: [lane(), lane(), lane(), lane()], edges: [], direction: .topToBottom)
        for index in 0..<800 { graph.boxes.append(node(index % 4)) }
        for index in 0..<800 { graph.edges.append(LaneLayoutEdge(source: 4 + index, target: 4 + (index * 7 + 3) % 800, minimumRankSpan: 1, labelSize: nil)) }
        return graph
    }
}
