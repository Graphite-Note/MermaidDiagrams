/**
 * File: LayeredFlatEndSettling.swift
 * ----------------------------------
 * Layer: Core
 * Description: Moves the ends of edges along their sides once the nodes have places, so that edges run straight.
 *
 * Authors: Bahey Shalash
 * Version: 0.3
 * Date: 23/11/2026
 */

/// Pele's `settle` (layout/layered.ts): an end moves along its side when that lets its edge run straight; any other end
/// leans towards where its edge goes, where its side is long enough, and an end with a side to itself stays in the
/// middle. The ends of one side keep their order and spacing, pooled by isotonic fitting between the held ends.
struct LayeredFlatEndSettling {
    var graph: LayeredFlatGraph
    let nodes: [LayeredFlatNode]
    let across: [Double]
    let fromEnds: [LayeredSegmentEnd]
    let toEnds: [LayeredSegmentEnd]
    let free: [[Int]]
    let emptyRanks: [Bool]?
    /// The pooled sums and counts of a run being fitted, kept between runs so that every fit reuses one pair.
    private var poolSum: [Double] = []
    private var poolCount: [Int] = []

    init(graph: consuming LayeredFlatGraph, nodes: [LayeredFlatNode], across: [Double], fromEnds: [LayeredSegmentEnd],
         toEnds: [LayeredSegmentEnd], free: [[Int]], emptyRanks: [Bool]?) {
        self.graph = graph
        self.nodes = nodes
        self.across = across
        self.fromEnds = fromEnds
        self.toEnds = toEnds
        self.free = free
        self.emptyRanks = emptyRanks
    }

    /// One side of a node whose ends may move: its free ends in order with their least gaps, and all its ends in order.
    private struct Side {
        var vertex: Int
        var side: Int
        var span: Double
        var segments: [Int]
        var room: [Double]
        var all: [Int]
    }

    /// Where the end of `segment` on `vertex` should be, from the middle of its side, following the edge up (side 0)
    /// or down to the next point held in place.
    private func wanted(_ segment: Int, side: Int, vertex: Int, span: Double, isAgain: Bool) -> Double {
        if free[side][vertex] < 2 { return 0 }
        let segment = graph.followed(segment, isUpward: side == 0, emptyRanks: emptyRanks)
        let other = side == 0 ? graph.segmentFrom[segment] : graph.segmentTo[segment]
        let point = across[other] + (side == 0 ? graph.segmentFromOffset[segment] : graph.segmentToOffset[segment])
        // Once the other end has its place, this one comes into line with it if it can.
        if isAgain && abs(point - across[vertex]) <= span / 2 + LayeredFlatConstants.inLine {
            return max(-span / 2, min(span / 2, point - across[vertex]))
        }
        // The part of the other side that its end may move along, if it may move.
        var middle = point
        var width: Double = 0
        let otherEnd = side == 0 ? fromEnds[segment] : toEnds[segment]
        if other < graph.nodeCount && nodes[other].kind == .node && otherEnd != .held && free[1 - side][other] >= 2 {
            width = max(0, min(nodes[other].sideSpan, graph.vertexWidth[other]))
            if width > 0 { middle = across[other] }
        }
        let low = max(across[vertex] - span / 2, middle - width / 2)
        let high = min(across[vertex] + span / 2, middle + width / 2)
        // Two sides with no part in line: the end leans towards the other, if its side is long enough.
        if low > high + LayeredFlatConstants.inLine {
            let lean = max(0, span / 2 - LayeredFlatConstants.leanClear)
            return max(-lean, min(lean, point - across[vertex]))
        }
        // Both ends settle on one place in the part the two sides share: nearer the middle of the narrower.
        let place = (across[vertex] * width + middle * span) / (width + span)
        return max(low, min(high, place)) - across[vertex]
    }

    private func sides() -> [Side] {
        var found: [Side] = []
        for vertex in 0..<graph.nodeCount {
            let span = min(nodes[vertex].sideSpan, graph.vertexWidth[vertex])
            if span <= 0 || nodes[vertex].kind != .node { continue }
            for side in 0..<2 {
                let other = side == 0 ? graph.segmentFrom : graph.segmentTo
                let starts = side == 0 ? graph.predecessorStart : graph.successorStart
                let list = side == 0 ? graph.predecessorSegments : graph.successorSegments
                var ends = graph.sideEnds(of: vertex, side: side, span: span, kinds: side == 0 ? toEnds : fromEnds)
                if ends.segments.isEmpty { continue }
                if ends.segments.count == 1 { ends.room = [0] }
                var all = Array(list[starts[vertex]..<starts[vertex + 1]])
                let position = graph.position
                all.sortStably { first, second in
                    position[other[first]] != position[other[second]] ? Double(position[other[first]] - position[other[second]]) : Double(first - second)
                }
                found.append(Side(vertex: vertex, side: side, span: span, segments: ends.segments, room: ends.room, all: all))
            }
        }
        return found
    }

    /// The ends of an edge follow each other, so the nodes are gone over until none moves, six times at most.
    mutating func settle() {
        let sides = sides()
        var pass = 0
        var moved = true
        while moved && pass < 6 {
            moved = false
            for side in sides where settle(side, isAgain: pass > 0) { moved = true }
            pass += 1
        }
    }

    /// Settles one side: held ends divide the free ends into runs, each fitted between the held ends around it.
    private mutating func settle(_ side: Side, isAgain: Bool) -> Bool {
        let kinds = side.side == 0 ? toEnds : fromEnds
        var moved = false
        var first = 0
        var low = -side.span / 2
        for index in 0...side.all.count {
            let isHeld = index < side.all.count && kinds[side.all[index]] == .held
            if index < side.all.count && !isHeld { continue }
            // Free ends since the last held end occupy segments[first..<first + size].
            var size = 0
            var back = index - 1
            while back >= 0 && kinds[side.all[back]] != .held { size += 1; back -= 1 }
            let high = isHeld ? offset(side.all[index], side: side.side) - LayeredFlatConstants.portPitch : side.span / 2
            if size > 0 {
                if fit(side, first: first, size: size, low: low, high: high, isAgain: isAgain) { moved = true }
                first += size
            }
            if isHeld { low = offset(side.all[index], side: side.side) + LayeredFlatConstants.portPitch }
        }
        return moved
    }

    private func offset(_ segment: Int, side: Int) -> Double { side == 0 ? graph.segmentToOffset[segment] : graph.segmentFromOffset[segment] }

    private mutating func setOffset(_ segment: Int, side: Int, to offset: Double) {
        if side == 0 { graph.segmentToOffset[segment] = offset } else { graph.segmentFromOffset[segment] = offset }
    }

    /// Isotonic fitting of one run of free ends: their order and spacing kept by pooling neighbours that are too close,
    /// a run that cannot fit between its held ends centred between them. Whether an end moved.
    private mutating func fit(_ side: Side, first: Int, size: Int, low: Double, high: Double, isAgain: Bool) -> Bool {
        var sum: [Double] = []
        var count: [Int] = []
        swap(&sum, &poolSum)
        swap(&count, &poolCount)
        defer {
            swap(&sum, &poolSum)
            swap(&count, &poolCount)
        }
        let total = pool(side, first: first, size: size, isAgain: isAgain, sum: &sum, count: &count)
        var before: Double = 0
        var moved = false
        var placed = 0
        for block in sum.indices {
            let level = high - total < low ? (low + high - total) / 2 : max(low, min(high - total, sum[block] / Double(count[block])))
            for _ in 0..<count[block] {
                if placed > 0 { before += side.room[first + placed] }
                let segment = side.segments[first + placed]
                if abs(offset(segment, side: side.side) - level - before) > 0.01 { moved = true }
                setOffset(segment, side: side.side, to: level + before)
                placed += 1
            }
        }
        return moved
    }

    /// The wanted places of a run of free ends pooled into blocks, each a sum of places and how many ends it holds;
    /// returns the room the run takes.
    private func pool(_ side: Side, first: Int, size: Int, isAgain: Bool, sum: inout [Double], count: inout [Int]) -> Double {
        sum.removeAll(keepingCapacity: true)
        count.removeAll(keepingCapacity: true)
        var before: Double = 0
        for index in 0..<size {
            if index > 0 { before += side.room[first + index] }
            sum.append(wanted(side.segments[first + index], side: side.side, vertex: side.vertex, span: side.span, isAgain: isAgain) - before)
            count.append(1)
            // Keep ends together when spacing forced them to share a place.
            var together = index > 0 && side.room[first + index] == 0
            while sum.count > 1 && (together || sum[sum.count - 2] / Double(count[count.count - 2]) > sum[sum.count - 1] / Double(count[count.count - 1])) {
                together = false
                let top = sum.removeLast()
                let pooled = count.removeLast()
                sum[sum.count - 1] += top
                count[count.count - 1] += pooled
            }
        }
        return before
    }
}
