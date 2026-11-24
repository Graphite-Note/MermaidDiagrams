/**
 * File: SankeyBandLists.swift
 * ---------------------------
 * Layer: Core
 * Description: The bands on one side of every node of a Sankey diagram in one flat list, node by node, so that the
 *              settling passes put each node's bands in order where they lie instead of copying lists out and in.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 23/11/2026
 */

/// The bands (by their link's place) leaving or entering each node, in one list: node `n`'s are at `range(of: n)`, in
/// the order of the links until they are stacked.
struct SankeyBandLists {
    /// The bands of every node, node after node.
    private(set) var bands: [Int]
    /// Where each node's bands start in `bands`, then the count of bands.
    private let starts: [Int]

    /// The lists of `nodeCount` nodes, `ends` giving the node on this side of each link, in the links' order.
    init(nodeCount: Int, ends: some Collection<Int>) {
        var starts = [Int](repeating: 0, count: nodeCount + 1)
        for node in ends { starts[node + 1] += 1 }
        for node in 0..<nodeCount { starts[node + 1] += starts[node] }
        var next = starts
        var bands = [Int](repeating: 0, count: ends.count)
        for (linkIndex, node) in ends.enumerated() {
            bands[next[node]] = linkIndex
            next[node] += 1
        }
        self.bands = bands
        self.starts = starts
    }

    func range(of node: Int) -> Range<Int> {
        starts[node]..<starts[node + 1]
    }

    func count(of node: Int) -> Int {
        starts[node + 1] - starts[node]
    }

    /// The bands of `node`.
    subscript(node: Int) -> ArraySlice<Int> {
        bands[range(of: node)]
    }

    /// Puts the bands at `range` in the order of `keys` (each band's key and the band, in the bands' order), as sorting
    /// the bands by them would: a list already in order is left as it is, as Swift's sort leaves it. Returns whether
    /// the order changed, the order before in `previousOrder` when it did; `keys` is left sorted.
    mutating func putInOrder(_ range: Range<Int>, keys: inout [(Double, Int)], previousOrder: inout [Int]) -> Bool {
        guard !Self.isInOrder(keys) else { return false }
        previousOrder.removeAll(keepingCapacity: true)
        previousOrder.append(contentsOf: bands[range])
        keys.sort(by: Self.isOrderedBefore)
        for (offset, key) in keys.enumerated() { bands[range.lowerBound + offset] = key.1 }
        return true
    }

    /// The order the settling passes sort by: by key, then by the band or node, as a tuple compares.
    static func isOrderedBefore(_ first: (Double, Int), _ second: (Double, Int)) -> Bool {
        first < second
    }

    /// Whether no key comes before the one ahead of it: such a list is one run, which Swift's sort leaves as it is (its
    /// insertion sort moves no element of it, and its run search finds the whole list ascending), so it need not sort.
    static func isInOrder(_ keys: [(Double, Int)]) -> Bool {
        var position = 1
        while position < keys.count {
            if isOrderedBefore(keys[position], keys[position - 1]) { return false }
            position += 1
        }
        return true
    }
}
