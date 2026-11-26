/**
 * File: SankeyBandStacking.swift
 * ------------------------------
 * Layer: Core
 * Description: The inner steps of a Sankey diagram's settling passes on its lists' storage: a node's bands put in the
 *              order of the nodes at their other ends and stacked, every node's at once, and a column moved toward where
 *              its bands run level and put in order, each list borrowed once for the whole step instead of checked and
 *              grown at each band.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 26/11/2026
 */

/// The settling passes' steps over borrowed storage. `keys` and `previousOrder` hold room for the most bands a node
/// has on one side and the most nodes a column has; the steps read and write only the first places they need.
enum SankeyBandStacking {
    typealias Node = SankeyPlacement.Node
    typealias Link = SankeyPlacement.Link

    /// The middle of `node`, the key bands and columns are put in order by.
    @inline(__always)
    static func center(_ node: Int, in nodes: UnsafeMutableBufferPointer<Node>) -> Double {
        nodes[node].y + nodes[node].height / 2
    }

    /// The bands `bands[range]` of one node top to bottom in the order of the middles of the nodes at their other ends
    /// (their targets when `byTargets`, for the bands leaving it), each band's middle below the node's top written to
    /// `offsets`. Returns whether their order changed, the order before in `previousOrder[0..<range.count]` when it did.
    /// The bands are put in order as sorting them by their keys would put them: a list already in order is left as it
    /// is, as Swift's sort leaves it, and any other is sorted by the same sort over the same keys.
    static func stack(_ range: Range<Int>, bands: UnsafeMutableBufferPointer<Int>, byTargets: Bool, links: UnsafeBufferPointer<Link>,
                      nodes: UnsafeMutableBufferPointer<Node>, offsets: UnsafeMutableBufferPointer<Double>, keys: UnsafeMutableBufferPointer<(Double, Int)>,
                      previousOrder: UnsafeMutableBufferPointer<Int>) -> Bool {
        let count = range.count
        precondition(count <= keys.count && count <= previousOrder.count, "room for a node's bands")
        var isInOrder = true
        for offset in 0..<count {
            let linkIndex = bands[range.lowerBound + offset]
            let key = (center(byTargets ? links[linkIndex].target : links[linkIndex].source, in: nodes), linkIndex)
            if offset > 0, SankeyBandLists.isOrderedBefore(key, keys[offset - 1]) { isInOrder = false }
            keys[offset] = key
        }
        if !isInOrder {
            for offset in 0..<count { previousOrder[offset] = bands[range.lowerBound + offset] }
            var sorted = UnsafeMutableBufferPointer(rebasing: keys[0..<count])
            sorted.sort(by: SankeyBandLists.isOrderedBefore)
            for offset in 0..<count { bands[range.lowerBound + offset] = keys[offset].1 }
        }
        var total = 0.0
        for position in range {
            let linkIndex = bands[position]
            offsets[linkIndex] = total + links[linkIndex].thickness / 2
            total += links[linkIndex].thickness
        }
        return !isInOrder
    }

    /// Each node's bands leaving it and entering it stacked, node after node.
    static func stackAll(leaving: inout SankeyBandLists, entering: inout SankeyBandLists, links: [Link], nodes: inout [Node],
                         sourceOffsets: inout [Double], targetOffsets: inout [Double], keys: inout [(Double, Int)], previousOrder: inout [Int]) {
        links.withUnsafeBufferPointer { links in
            nodes.withUnsafeMutableBufferPointer { nodes in
                keys.withUnsafeMutableBufferPointer { keys in
                    previousOrder.withUnsafeMutableBufferPointer { previousOrder in
                        sourceOffsets.withUnsafeMutableBufferPointer { sourceOffsets in
                            targetOffsets.withUnsafeMutableBufferPointer { targetOffsets in
                                leaving.withBands { leavingBands, leavingStarts in
                                    entering.withBands { enteringBands, enteringStarts in
                                        for node in nodes.indices {
                                            _ = stack(leavingStarts[node]..<leavingStarts[node + 1], bands: leavingBands, byTargets: true, links: links,
                                                      nodes: nodes, offsets: sourceOffsets, keys: keys, previousOrder: previousOrder)
                                            _ = stack(enteringStarts[node]..<enteringStarts[node + 1], bands: enteringBands, byTargets: false, links: links,
                                                      nodes: nodes, offsets: targetOffsets, keys: keys, previousOrder: previousOrder)
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    /// Moves each node of `column` `pull` of the way toward where its bands on `side` would run level (weighted by their
    /// thickness), the bands entering it when `towardSources`, after stacking them; the bands are weighed in the order
    /// they had before they were stacked. Then puts the column in the order of its nodes' middles.
    static func settle(_ column: inout [Int], pull: Double, towardSources: Bool, side: inout SankeyBandLists, links: [Link], nodes: inout [Node],
                       sourceOffsets: inout [Double], targetOffsets: inout [Double], keys: inout [(Double, Int)], previousOrder: inout [Int]) {
        links.withUnsafeBufferPointer { links in
            nodes.withUnsafeMutableBufferPointer { nodes in
                keys.withUnsafeMutableBufferPointer { keys in
                    previousOrder.withUnsafeMutableBufferPointer { previousOrder in
                        sourceOffsets.withUnsafeMutableBufferPointer { sourceOffsets in
                            targetOffsets.withUnsafeMutableBufferPointer { targetOffsets in
                                side.withBands { bands, starts in
                                    for node in column {
                                        let range = starts[node]..<starts[node + 1]
                                        guard !range.isEmpty else { continue }
                                        let isReordered = stack(range, bands: bands, byTargets: !towardSources, links: links, nodes: nodes,
                                                                offsets: towardSources ? targetOffsets : sourceOffsets, keys: keys, previousOrder: previousOrder)
                                        let wanted = level(of: node, range: range, isReordered: isReordered, bands: bands, towardSources: towardSources,
                                                           links: links, nodes: nodes, sourceOffsets: sourceOffsets, targetOffsets: targetOffsets,
                                                           previousOrder: previousOrder)
                                        nodes[node].y += (wanted - nodes[node].y) * pull
                                    }
                                }
                                column.withUnsafeMutableBufferPointer { column in putInOrder(column, nodes: nodes, keys: keys) }
                            }
                        }
                    }
                }
            }
        }
    }

    /// Where `node` would have its bands `range` run level: their levels weighted by their thickness, or the middles of
    /// the nodes at their other ends when none is thick.
    @inline(__always)
    private static func level(of node: Int, range: Range<Int>, isReordered: Bool, bands: UnsafeMutableBufferPointer<Int>, towardSources: Bool,
                              links: UnsafeBufferPointer<Link>, nodes: UnsafeMutableBufferPointer<Node>, sourceOffsets: UnsafeMutableBufferPointer<Double>,
                              targetOffsets: UnsafeMutableBufferPointer<Double>, previousOrder: UnsafeMutableBufferPointer<Int>) -> Double {
        var weighted = 0.0
        var weight = 0.0
        var plain = 0.0
        for position in range {
            let linkIndex = isReordered ? previousOrder[position - range.lowerBound] : bands[position]
            let link = links[linkIndex]
            let level = towardSources ? nodes[link.source].y + sourceOffsets[linkIndex] - targetOffsets[linkIndex]
                : nodes[link.target].y + targetOffsets[linkIndex] - sourceOffsets[linkIndex]
            weighted += level * link.thickness
            weight += link.thickness
            plain += center(towardSources ? link.source : link.target, in: nodes) - nodes[node].height / 2
        }
        return weight > 0 ? weighted / weight : plain / Double(range.count)
    }

    /// The column's nodes in the order of their middles, as sorting them by their keys would put them.
    private static func putInOrder(_ column: UnsafeMutableBufferPointer<Int>, nodes: UnsafeMutableBufferPointer<Node>,
                                   keys: UnsafeMutableBufferPointer<(Double, Int)>) {
        let count = column.count
        precondition(count <= keys.count, "room for a column's nodes")
        var isInOrder = true
        for position in 0..<count {
            let key = (center(column[position], in: nodes), column[position])
            if position > 0, SankeyBandLists.isOrderedBefore(key, keys[position - 1]) { isInOrder = false }
            keys[position] = key
        }
        guard !isInOrder else { return }
        var sorted = UnsafeMutableBufferPointer(rebasing: keys[0..<count])
        sorted.sort(by: SankeyBandLists.isOrderedBefore)
        for position in 0..<count { column[position] = keys[position].1 }
    }
}
