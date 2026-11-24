/**
 * File: SankeyPlacement.swift
 * ---------------------------
 * Layer: Core
 * Description: Where a Sankey diagram's nodes and bands go on a chart of a given size, as Pele places them: columns,
 *              heights, the label room thin nodes keep, and the six passes that settle each column.
 *
 * Authors: felixchvl, Bahey Shalash
 * Version: 0.2
 * Date: 23/11/2026
 */

import Foundation

/// Where a Sankey diagram's nodes and bands go on a chart of a given size, as Pele places them: each node in a column
/// by its longest distance from a source (by default a node with no flow out in the last column), as tall as its flow, the flows
/// scaled to fit the fullest column with a gap between nodes, room for a label kept around thin nodes where every
/// column can afford it, then six passes that move each column's nodes toward where their bands run level, so that
/// bands cross less. A band leaves and enters a node in the order of where it goes. Coordinates are the chart's, its
/// origin the top left of the first column.
struct SankeyPlacement {
    struct Node {
        let layer: Int
        /// The flow through the node in the diagram's units: the larger of what enters and what leaves.
        let value: Double
        let x: Double
        var y: Double
        var height: Double
    }

    struct Link {
        let source: Int
        let target: Int
        /// The value drawn: the link's, or zero when it is not a finite number above zero.
        let value: Double
        var thickness: Double
        /// The middle of the band where it leaves its source and where it enters its target.
        var sourceY: Double
        var targetY: Double
    }

    struct Options {
        let width: Double
        let height: Double
        let nodeWidth: Double
        let nodePadding: Double
        /// The height of a label's line: a thin node keeps at least this much room where every column can afford it.
        let labelHeight: Double
        let alignment: SankeyNodeAlignment
    }

    private(set) var nodes: [Node] = []
    private(set) var links: [Link]
    /// The nodes of each column, top to bottom once placed.
    private(set) var columns: [[Int]] = []
    /// Each node's bands leaving it and entering it, top to bottom once stacked.
    private var leaving: SankeyBandLists
    private var entering: SankeyBandLists
    /// The keys of a list being put in order, and the order it had before, kept between sorts for their room.
    private var sortKeys: [(Double, Int)] = []
    private var previousOrder: [Int] = []
    /// The room each node keeps clear above and below itself.
    private var margins: [Double] = []
    /// Each band's middle below the top of its source and of its target.
    private var sourceOffsets: [Double]
    private var targetOffsets: [Double]
    private let options: Options

    /// The passes that let the columns settle, and how much each moves a node of the way, 0.99 to the pass' power.
    static let settlingPassCount = 6
    static let pullDecay = 0.99
    /// The halvings that find the largest scale at which every node keeps a label's room.
    static let scaleSearchSteps = 40
    /// How far past the chart's height a column may reach from rounding and still fit.
    static let heightTolerance = 1e-6

    init(diagram: SankeyDiagram, options: Options) throws(SankeyLayoutError) {
        self.options = options
        links = diagram.links.map { link in
            let value = link.value.flatMap { value in value.isFinite && value > 0 ? value : nil } ?? 0
            return Link(source: link.sourceIndex, target: link.targetIndex, value: value, thickness: 0, sourceY: 0, targetY: 0)
        }
        leaving = SankeyBandLists(nodeCount: diagram.nodes.count, ends: links.lazy.map(\.source))
        entering = SankeyBandLists(nodeCount: diagram.nodes.count, ends: links.lazy.map(\.target))
        sourceOffsets = Array(repeating: 0, count: links.count)
        targetOffsets = Array(repeating: 0, count: links.count)
        let (depths, order) = try Self.depths(nodeCount: diagram.nodes.count, links: links, leaving: leaving, entering: entering)
        let flows = makeNodes(depths: depths, order: order)
        let scale = sizedScale(flows: flows)
        stackColumns(flows: flows, scale: scale)
        settle()
        for linkIndex in links.indices {
            links[linkIndex].sourceY = nodes[links[linkIndex].source].y + sourceOffsets[linkIndex]
            links[linkIndex].targetY = nodes[links[linkIndex].target].y + targetOffsets[linkIndex]
        }
    }

    /// Each node's longest distance from a source, and the topological order it is found in; a node left over lies on
    /// a cycle.
    private static func depths(nodeCount: Int, links: [Link], leaving: SankeyBandLists,
                               entering: SankeyBandLists) throws(SankeyLayoutError) -> (depths: [Int], order: [Int]) {
        var depths = Array(repeating: 0, count: nodeCount)
        var pending = (0..<nodeCount).map { node in entering.count(of: node) }
        var order = (0..<nodeCount).filter { node in pending[node] == 0 }
        order.reserveCapacity(nodeCount)
        var head = 0
        while head < order.count {
            let node = order[head]
            head += 1
            for linkIndex in leaving[node] {
                let target = links[linkIndex].target
                depths[target] = max(depths[target], depths[node] + 1)
                pending[target] -= 1
                if pending[target] == 0 { order.append(target) }
            }
        }
        guard order.count == nodeCount else { throw .circularLinks }
        return (depths, order)
    }

    /// Each node's longest distance to a node with no flow out, found in reverse topological order.
    private func reaches(order: [Int]) -> [Int] {
        var reaches = Array(repeating: 0, count: order.count)
        for node in order.reversed() {
            for linkIndex in leaving[node] { reaches[node] = max(reaches[node], reaches[links[linkIndex].target] + 1) }
        }
        return reaches
    }

    /// The column of `node` by the options' alignment.
    private func layer(of node: Int, depths: [Int], reaches: [Int], layerCount: Int) -> Int {
        switch options.alignment {
        case .justify: return leaving.count(of: node) == 0 ? layerCount - 1 : depths[node]
        case .left: return depths[node]
        case .right: return layerCount - 1 - reaches[node]
        case .center:
            guard entering.count(of: node) == 0, leaving.count(of: node) > 0 else { return depths[node] }
            return leaving[node].reduce(layerCount) { nearest, linkIndex in min(nearest, depths[links[linkIndex].target] - 1) }
        }
    }

    /// The nodes in their columns by the options' alignment. Returns each node's flow as a share of the largest link's
    /// value, so that sums of huge values stay finite.
    private mutating func makeNodes(depths: [Int], order: [Int]) -> [Double] {
        let layerCount = (depths.max() ?? 0) + 1
        let reaches = options.alignment == .right ? reaches(order: order) : []
        let step = layerCount > 1 ? (options.width - options.nodeWidth) / Double(layerCount - 1) : 0
        let largest = links.map(\.value).max() ?? 0
        let unit = largest > 0 ? 1 / largest : 0
        columns = Array(repeating: [], count: layerCount)
        var flows: [Double] = []
        flows.reserveCapacity(depths.count)
        nodes.reserveCapacity(depths.count)
        for node in depths.indices {
            let layer = layer(of: node, depths: depths, reaches: reaches, layerCount: layerCount)
            let enteringValue = entering[node].reduce(0.0) { sum, linkIndex in sum + links[linkIndex].value }
            let leavingValue = leaving[node].reduce(0.0) { sum, linkIndex in sum + links[linkIndex].value }
            // Each value is scaled before the sum, so that two values near the largest double do not overflow it.
            let enteringFlow = entering[node].reduce(0.0) { sum, linkIndex in sum + links[linkIndex].value * unit }
            let leavingFlow = leaving[node].reduce(0.0) { sum, linkIndex in sum + links[linkIndex].value * unit }
            flows.append(max(enteringFlow, leavingFlow))
            nodes.append(Node(layer: layer, value: max(enteringValue, leavingValue), x: Double(layer) * step, y: 0, height: 0))
            columns[layer].append(node)
        }
        for linkIndex in links.indices { links[linkIndex].thickness = links[linkIndex].value * unit }
        return flows
    }

    /// The scale from flow to height that fits the fullest column, lowered so that every node keeps a label's room
    /// when every column can afford it; sets the gap between nodes, the margins and the bands' thicknesses.
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
    /// The least room a node takes in its column, a label's height, or zero.
    private var claim = 0.0

    /// Whether every column fits the chart's height when flows are drawn at `scale` and each node takes `claim`.
    private func fits(scale: Double, flows: [Double]) -> Bool {
        columns.allSatisfy { column in
            let extent = Double(column.count - 1) * gap + column.reduce(0.0) { sum, node in sum + max(flows[node] * scale, claim) }
            return extent <= options.height + Self.heightTolerance
        }
    }

    /// Each column's nodes from the top with the gap between them, the spare room shared out between them.
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

    /// Pele's passes: each column, from the second to last back to the first, moves toward the nodes its bands go to;
    /// then each, from the second on, toward the nodes its bands come from; the pull weakening with each pass.
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

    /// The bands leaving `node`, top to bottom in the order of their targets' middles. Returns whether their order
    /// changed, the order before in `previousOrder` when it did.
    @discardableResult
    private mutating func stackLeaving(_ node: Int) -> Bool {
        let range = leaving.range(of: node)
        sortKeys.removeAll(keepingCapacity: true)
        for position in range {
            let linkIndex = leaving.bands[position]
            sortKeys.append((center(links[linkIndex].target), linkIndex))
        }
        let isReordered = leaving.putInOrder(range, keys: &sortKeys, previousOrder: &previousOrder)
        var offset = 0.0
        for position in range {
            let linkIndex = leaving.bands[position]
            sourceOffsets[linkIndex] = offset + links[linkIndex].thickness / 2
            offset += links[linkIndex].thickness
        }
        return isReordered
    }

    /// The bands entering `node`, top to bottom in the order of their sources' middles. Returns whether their order
    /// changed, the order before in `previousOrder` when it did.
    @discardableResult
    private mutating func stackEntering(_ node: Int) -> Bool {
        let range = entering.range(of: node)
        sortKeys.removeAll(keepingCapacity: true)
        for position in range {
            let linkIndex = entering.bands[position]
            sortKeys.append((center(links[linkIndex].source), linkIndex))
        }
        let isReordered = entering.putInOrder(range, keys: &sortKeys, previousOrder: &previousOrder)
        var offset = 0.0
        for position in range {
            let linkIndex = entering.bands[position]
            targetOffsets[linkIndex] = offset + links[linkIndex].thickness / 2
            offset += links[linkIndex].thickness
        }
        return isReordered
    }

    /// Moves each node of a column `pull` of the way toward where its bands would run level (weighted by their
    /// thickness), then restores the column's order and gaps within the chart's height. The bands are weighed in the
    /// order they had before this pass stacked them.
    private mutating func settle(layer: Int, pull: Double, towardSources: Bool) {
        for node in columns[layer] {
            let range = towardSources ? entering.range(of: node) : leaving.range(of: node)
            guard !range.isEmpty else { continue }
            let isReordered = towardSources ? stackEntering(node) : stackLeaving(node)
            var weighted = 0.0
            var weight = 0.0
            var plain = 0.0
            for position in range {
                let linkIndex = isReordered ? previousOrder[position - range.lowerBound]
                    : towardSources ? entering.bands[position] : leaving.bands[position]
                let link = links[linkIndex]
                let level = towardSources ? nodes[link.source].y + sourceOffsets[linkIndex] - targetOffsets[linkIndex]
                    : nodes[link.target].y + targetOffsets[linkIndex] - sourceOffsets[linkIndex]
                weighted += level * link.thickness
                weight += link.thickness
                plain += center(towardSources ? link.source : link.target) - nodes[node].height / 2
            }
            let wanted = weight > 0 ? weighted / weight : plain / Double(range.count)
            nodes[node].y += (wanted - nodes[node].y) * pull
        }
        sortKeys.removeAll(keepingCapacity: true)
        for node in columns[layer] { sortKeys.append((center(node), node)) }
        if !SankeyBandLists.isInOrder(sortKeys) {
            sortKeys.sort(by: SankeyBandLists.isOrderedBefore)
            for position in sortKeys.indices { columns[layer][position] = sortKeys[position].1 }
        }
        restoreGaps(in: layer)
    }

    /// Pushes a column's nodes down past the ones above with the gap between them, then up within the chart's height.
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
