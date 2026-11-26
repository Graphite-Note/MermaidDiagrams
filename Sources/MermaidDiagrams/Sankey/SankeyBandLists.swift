/**
 * File: SankeyBandLists.swift
 * ---------------------------
 * Layer: Core
 * Description: The bands on one side of every node of a Sankey diagram in one flat list, node by node, so that the
 *              settling passes put each node's bands in order where they lie instead of copying lists out and in.
 *
 * Authors: Bahey Shalash
 * Version: 0.2
 * Date: 26/11/2026
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

    /// Calls `body` with the bands to put in order where they lie, and where each node's start (the count of bands
    /// after the last node's): node `n`'s are at `starts[n]..<starts[n + 1]`.
    mutating func withBands<Result>(_ body: (UnsafeMutableBufferPointer<Int>, UnsafeBufferPointer<Int>) -> Result) -> Result {
        starts.withUnsafeBufferPointer { starts in bands.withUnsafeMutableBufferPointer { bands in body(bands, starts) } }
    }

    /// The order the settling passes sort by: by key, then by the band or node, as a tuple compares.
    static func isOrderedBefore(_ first: (Double, Int), _ second: (Double, Int)) -> Bool {
        first < second
    }
}
