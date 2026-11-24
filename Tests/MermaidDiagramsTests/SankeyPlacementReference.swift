/**
 * File: SankeyPlacementReference.swift
 * ------------------------------------
 * Layer: Tests
 * Description: SankeyPlacement as it was at 0.6.1, before its bands were sorted in flat lists, kept as the reference
 *              the faster placement must match number for number (TypeLayoutEquivalenceTests).
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 23/11/2026
 */

import Foundation
@testable import MermaidDiagrams

/// The placement of 0.6.1 unchanged but for its comments, which `SankeyPlacement` describes: every node's band lists
/// sorted as arrays of arrays, copied out and in, by keys found during the sort.
struct SankeyPlacementReference {
    typealias Node = SankeyPlacement.Node

    typealias Link = SankeyPlacement.Link

    typealias Options = SankeyPlacement.Options

    private(set) var nodes: [Node] = []
    private(set) var links: [Link]
    private(set) var columns: [[Int]] = []
    private var outgoing: [[Int]]
    private var incoming: [[Int]]
    private var margins: [Double] = []
    private var sourceOffsets: [Double]
    private var targetOffsets: [Double]
    private let options: Options

    static let settlingPassCount = 6
    static let pullDecay = 0.99
    static let scaleSearchSteps = 40
    static let heightTolerance = 1e-6

    init(diagram: SankeyDiagram, options: Options) throws(SankeyLayoutError) {
        self.options = options
        links = diagram.links.map { link in
            let value = link.value.flatMap { value in value.isFinite && value > 0 ? value : nil } ?? 0
            return Link(source: link.sourceIndex, target: link.targetIndex, value: value, thickness: 0, sourceY: 0, targetY: 0)
        }
        outgoing = Array(repeating: [], count: diagram.nodes.count)
        incoming = Array(repeating: [], count: diagram.nodes.count)
        for (linkIndex, link) in links.enumerated() {
            outgoing[link.source].append(linkIndex)
            incoming[link.target].append(linkIndex)
        }
        sourceOffsets = Array(repeating: 0, count: links.count)
        targetOffsets = Array(repeating: 0, count: links.count)
        let (depths, order) = try Self.depths(nodeCount: diagram.nodes.count, links: links, outgoing: outgoing, incoming: incoming)
        let flows = makeNodes(depths: depths, order: order)
        let scale = sizedScale(flows: flows)
        stackColumns(flows: flows, scale: scale)
        settle()
        for linkIndex in links.indices {
            links[linkIndex].sourceY = nodes[links[linkIndex].source].y + sourceOffsets[linkIndex]
            links[linkIndex].targetY = nodes[links[linkIndex].target].y + targetOffsets[linkIndex]
        }
    }

    private static func depths(nodeCount: Int, links: [Link], outgoing: [[Int]],
                               incoming: [[Int]]) throws(SankeyLayoutError) -> (depths: [Int], order: [Int]) {
        var depths = Array(repeating: 0, count: nodeCount)
        var pending = incoming.map(\.count)
        var order = (0..<nodeCount).filter { node in pending[node] == 0 }
        var head = 0
        while head < order.count {
            let node = order[head]
            head += 1
            for linkIndex in outgoing[node] {
                let target = links[linkIndex].target
                depths[target] = max(depths[target], depths[node] + 1)
                pending[target] -= 1
                if pending[target] == 0 { order.append(target) }
            }
        }
        guard order.count == nodeCount else { throw .circularLinks }
        return (depths, order)
    }

    private func reaches(order: [Int]) -> [Int] {
        var reaches = Array(repeating: 0, count: order.count)
        for node in order.reversed() {
            for linkIndex in outgoing[node] { reaches[node] = max(reaches[node], reaches[links[linkIndex].target] + 1) }
        }
        return reaches
    }

    private func layer(of node: Int, depths: [Int], reaches: [Int], layerCount: Int) -> Int {
        switch options.alignment {
        case .justify: return outgoing[node].isEmpty ? layerCount - 1 : depths[node]
        case .left: return depths[node]
        case .right: return layerCount - 1 - reaches[node]
        case .center:
            guard incoming[node].isEmpty, !outgoing[node].isEmpty else { return depths[node] }
            return outgoing[node].reduce(layerCount) { nearest, linkIndex in min(nearest, depths[links[linkIndex].target] - 1) }
        }
    }

    private mutating func makeNodes(depths: [Int], order: [Int]) -> [Double] {
        let layerCount = (depths.max() ?? 0) + 1
        let reaches = options.alignment == .right ? reaches(order: order) : []
        let step = layerCount > 1 ? (options.width - options.nodeWidth) / Double(layerCount - 1) : 0
        let largest = links.map(\.value).max() ?? 0
        let unit = largest > 0 ? 1 / largest : 0
        columns = Array(repeating: [], count: layerCount)
        var flows: [Double] = []
        for node in depths.indices {
            let layer = layer(of: node, depths: depths, reaches: reaches, layerCount: layerCount)
            let entering = incoming[node].reduce(0.0) { sum, linkIndex in sum + links[linkIndex].value }
            let leaving = outgoing[node].reduce(0.0) { sum, linkIndex in sum + links[linkIndex].value }
            let enteringFlow = incoming[node].reduce(0.0) { sum, linkIndex in sum + links[linkIndex].value * unit }
            let leavingFlow = outgoing[node].reduce(0.0) { sum, linkIndex in sum + links[linkIndex].value * unit }
            flows.append(max(enteringFlow, leavingFlow))
            nodes.append(Node(layer: layer, value: max(entering, leaving), x: Double(layer) * step, y: 0, height: 0))
            columns[layer].append(node)
        }
        for linkIndex in links.indices { links[linkIndex].thickness = links[linkIndex].value * unit }
        return flows
    }

    private mutating func sizedScale(flows: [Double]) -> Double {
        let tallest = max(1, columns.map(\.count).max() ?? 1)
        gap = tallest > 1 ? min(options.nodePadding, options.height / Double(tallest - 1)) : options.nodePadding
        var scale = Double.infinity
        for column in columns {
            let sum = column.reduce(0.0) { sum, node in sum + flows[node] }
            if sum > 0 { scale = min(scale, (options.height - Double(column.count - 1) * gap) / sum) }
        }
        if !scale.isFinite || scale < 0 { scale = 0 }
        claim = max(0, options.labelHeight - gap)
        if claim > 0, !fits(scale: scale, flows: flows) {
            if fits(scale: 0, flows: flows) {
                var low = 0.0
                for _ in 0..<Self.scaleSearchSteps {
                    let middle = (low + scale) / 2
                    if fits(scale: middle, flows: flows) { low = middle } else { scale = middle }
                }
                scale = low
            } else {
                claim = 0
            }
        }
        for linkIndex in links.indices { links[linkIndex].thickness *= scale }
        return scale
    }

    private var gap = 0.0
    private var claim = 0.0

    private func fits(scale: Double, flows: [Double]) -> Bool {
        columns.allSatisfy { column in
            let extent = Double(column.count - 1) * gap + column.reduce(0.0) { sum, node in sum + max(flows[node] * scale, claim) }
            return extent <= options.height + Self.heightTolerance
        }
    }

    private mutating func stackColumns(flows: [Double], scale: Double) {
        margins = Array(repeating: 0, count: nodes.count)
        for column in columns {
            var top = 0.0
            for node in column {
                nodes[node].height = flows[node] * scale
                margins[node] = max(0, claim - nodes[node].height) / 2
                nodes[node].y = top + margins[node]
                top += nodes[node].height + 2 * margins[node] + gap
            }
            let spare = (options.height - top + gap) / Double(column.count + 1)
            for (position, node) in column.enumerated() { nodes[node].y += spare * Double(position + 1) }
        }
    }

    private mutating func settle() {
        stackAllBands()
        for pass in 0..<Self.settlingPassCount {
            let pull = pow(Self.pullDecay, Double(pass))
            for layer in stride(from: columns.count - 2, through: 0, by: -1) { settle(layer: layer, pull: pull, towardSources: false) }
            stackAllBands()
            for layer in columns.indices.dropFirst() { settle(layer: layer, pull: pull, towardSources: true) }
            stackAllBands()
        }
    }

    private func center(_ node: Int) -> Double {
        nodes[node].y + nodes[node].height / 2
    }

    private mutating func stackAllBands() {
        for node in nodes.indices {
            stackLeaving(node)
            stackEntering(node)
        }
    }

    private mutating func stackLeaving(_ node: Int) {
        var leaving = outgoing[node]
        outgoing[node] = []
        leaving.sort { first, second in (center(links[first].target), first) < (center(links[second].target), second) }
        outgoing[node] = leaving
        var offset = 0.0
        for linkIndex in outgoing[node] {
            sourceOffsets[linkIndex] = offset + links[linkIndex].thickness / 2
            offset += links[linkIndex].thickness
        }
    }

    private mutating func stackEntering(_ node: Int) {
        var entering = incoming[node]
        incoming[node] = []
        entering.sort { first, second in (center(links[first].source), first) < (center(links[second].source), second) }
        incoming[node] = entering
        var offset = 0.0
        for linkIndex in incoming[node] {
            targetOffsets[linkIndex] = offset + links[linkIndex].thickness / 2
            offset += links[linkIndex].thickness
        }
    }

    private mutating func settle(layer: Int, pull: Double, towardSources: Bool) {
        for node in columns[layer] {
            let bands = towardSources ? incoming[node] : outgoing[node]
            guard !bands.isEmpty else { continue }
            if towardSources { stackEntering(node) } else { stackLeaving(node) }
            var weighted = 0.0
            var weight = 0.0
            var plain = 0.0
            for linkIndex in bands {
                let link = links[linkIndex]
                let level = towardSources ? nodes[link.source].y + sourceOffsets[linkIndex] - targetOffsets[linkIndex]
                    : nodes[link.target].y + targetOffsets[linkIndex] - sourceOffsets[linkIndex]
                weighted += level * link.thickness
                weight += link.thickness
                plain += center(towardSources ? link.source : link.target) - nodes[node].height / 2
            }
            let wanted = weight > 0 ? weighted / weight : plain / Double(bands.count)
            nodes[node].y += (wanted - nodes[node].y) * pull
        }
        var column = columns[layer]
        columns[layer] = []
        column.sort { first, second in (center(first), first) < (center(second), second) }
        columns[layer] = column
        restoreGaps(in: layer)
    }

    private mutating func restoreGaps(in layer: Int) {
        var top = 0.0
        for node in columns[layer] {
            if nodes[node].y - margins[node] < top { nodes[node].y = top + margins[node] }
            top = nodes[node].y + nodes[node].height + margins[node] + gap
        }
        var bottom = options.height
        for node in columns[layer].reversed() {
            if nodes[node].y + nodes[node].height + margins[node] > bottom { nodes[node].y = bottom - nodes[node].height - margins[node] }
            bottom = nodes[node].y - margins[node] - gap
        }
    }
}
