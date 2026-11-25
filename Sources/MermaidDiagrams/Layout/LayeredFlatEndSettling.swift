/**
 * File: LayeredFlatEndSettling.swift
 * ----------------------------------
 * Layer: Core
 * Description: Moves the ends of edges along their sides once the nodes have places, so that edges run straight.
 *
 * Authors: Bahey Shalash
 * Version: 0.6
 * Date: 25/11/2026
 */

/// Pele's `settle` (layout/layered.ts): an end moves along its side when that lets its edge run straight; any other end
/// leans towards where its edge goes, where its side is long enough, and an end with a side to itself stays in the
/// middle. The ends of one side keep their order and spacing, pooled by isotonic fitting between the held ends.
struct LayeredFlatEndSettling {
    let graph: LayeredFlatGraph
    let nodes: ScratchSpan<LayeredFlatNode>
    let across: ScratchSpan<Double>
    let fromEnds: ScratchSpan<LayeredSegmentEnd>
    let toEnds: ScratchSpan<LayeredSegmentEnd>
    /// How many free ends each side of each vertex has, side 0 first (`LayeredFlatGraph.freeEnds`).
    let free: ScratchSpan<Int>
    let emptyRanks: ScratchSpan<Bool>?
    let arena: DiagramScratchArena

    /// The settling's lists come from `arena`; the caller gives them back once the settling is finished. `across` is
    /// only read while the ends settle. Every method reads the settling as it is and changes only spans and the lists
    /// handed to it, so that none copies the settling to call another.
    init(graph: LayeredFlatGraph, nodes: ScratchSpan<LayeredFlatNode>, across: ScratchSpan<Double>,
         fromEnds: ScratchSpan<LayeredSegmentEnd>, toEnds: ScratchSpan<LayeredSegmentEnd>, free: ScratchSpan<Int>,
         emptyRanks: ScratchSpan<Bool>?, arena: DiagramScratchArena) {
        self.graph = graph
        self.nodes = nodes
        self.across = across
        self.fromEnds = fromEnds
        self.toEnds = toEnds
        self.free = free
        self.emptyRanks = emptyRanks
        self.arena = arena
    }

    /// The free ends of every side in order, with their least gaps, and all their ends in order, one side after another.
    private struct SideEnds {
        var segments: ScratchList<Int>
        var room: ScratchList<Double>
        var all: ScratchList<Int>
    }

    /// The pooled sums and counts of a run being fitted, kept between runs so that every fit reuses one pair.
    private struct Pools {
        var sum: ScratchList<Double>
        var count: ScratchList<Int>
    }

    /// One side of a node whose ends may move: where its free ends and their least gaps start in `segments` and
    /// `room` of the sides' ends, and where all its ends start in `all`, and how many.
    private struct Side {
        var vertex: Int
        var side: Int
        var span: Double
        var segmentStart: Int
        var allStart: Int
        var allCount: Int
    }

    /// Where the end of `segment` on `vertex` should be, from the middle of its side, following the edge up (side 0)
    /// or down to the next point held in place.
    private func wanted(_ segment: Int, side: Int, vertex: Int, span: Double, isAgain: Bool) -> Double {
        let vertexCount = graph.vertexCount, free = free, across = across
        if free[side * vertexCount + vertex] < 2 { return 0 }
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
        if other < graph.nodeCount && nodes[other].kind == .node && otherEnd != .held && free[(1 - side) * vertexCount + other] >= 2 {
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

    /// The sides whose ends may move, their ends written to `sideEnds`.
    private func sides(into sideEnds: inout SideEnds) -> ScratchList<Side> {
        var found = arena.list(capacity: 2 * graph.nodeCount, of: Side.self)
        var ends = LayeredSideEnds(arena: arena)
        var all = arena.list(capacity: 8, of: Int.self)
        // The graph's lists read once, outside the loops, for both sides.
        let position = graph.position, segmentFrom = graph.segmentFrom, segmentTo = graph.segmentTo
        let predecessorStart = graph.predecessorStart, successorStart = graph.successorStart
        let predecessorSegments = graph.predecessorSegments, successorSegments = graph.successorSegments
        for vertex in 0..<graph.nodeCount {
            let span = min(nodes[vertex].sideSpan, graph.vertexWidth[vertex])
            if span <= 0 || nodes[vertex].kind != .node { continue }
            for side in 0..<2 {
                graph.fillSideEnds(of: vertex, side: side, span: span, kinds: side == 0 ? toEnds : fromEnds, into: &ends, arena: arena)
                if ends.segments.isEmpty { continue }
                if ends.segments.count == 1 { ends.room.append(0) }
                let starts = side == 0 ? predecessorStart : successorStart
                all.removeAll()
                all.append(contentsOf: (side == 0 ? predecessorSegments : successorSegments).part(starts[vertex]..<starts[vertex + 1]))
                let other = side == 0 ? segmentFrom : segmentTo
                all.sortStably(in: arena) { first, second in
                    (position[other[first]] != position[other[second]] ? Double(position[other[first]] - position[other[second]])
                        : Double(first - second)) < 0
                }
                found.append(Side(vertex: vertex, side: side, span: span, segmentStart: sideEnds.segments.count, allStart: sideEnds.all.count,
                                  allCount: all.count))
                sideEnds.segments.append(contentsOf: ends.segments.elements)
                sideEnds.room.append(contentsOf: ends.room.elements)
                sideEnds.all.append(contentsOf: all.elements)
            }
        }
        return found
    }

    /// The ends of an edge follow each other, so the nodes are gone over until none moves, six times at most.
    func settle() {
        // Every segment has an end on each side: no side list holds more than all of them.
        let endCount = 2 * graph.segmentCount
        var pools = Pools(sum: arena.list(capacity: 8, of: Double.self), count: arena.list(capacity: 8, of: Int.self))
        var sideEnds = SideEnds(segments: arena.list(capacity: endCount, of: Int.self), room: arena.list(capacity: endCount, of: Double.self),
                                all: arena.list(capacity: endCount, of: Int.self))
        let sides = sides(into: &sideEnds)
        let ends = (segments: sideEnds.segments.elements, room: sideEnds.room.elements, all: sideEnds.all.elements)
        var pass = 0
        var moved = true
        while moved && pass < 6 {
            moved = false
            for side in sides where settle(side, ends: ends, pools: &pools, isAgain: pass > 0) { moved = true }
            pass += 1
        }
    }

    /// The sides' ends as `SideEnds` holds them once every side is found.
    private typealias SettledEnds = (segments: ScratchSpan<Int>, room: ScratchSpan<Double>, all: ScratchSpan<Int>)

    /// Settles one side: held ends divide the free ends into runs, each fitted between the held ends around it.
    private func settle(_ side: Side, ends: SettledEnds, pools: inout Pools, isAgain: Bool) -> Bool {
        let kinds = side.side == 0 ? toEnds : fromEnds
        var moved = false
        var first = 0
        var low = -side.span / 2
        for index in 0...side.allCount {
            let isHeld = index < side.allCount && kinds[ends.all[side.allStart + index]] == .held
            if index < side.allCount && !isHeld { continue }
            // Free ends since the last held end occupy segments[first..<first + size].
            var size = 0
            var back = index - 1
            while back >= 0 && kinds[ends.all[side.allStart + back]] != .held { size += 1; back -= 1 }
            let high = isHeld ? offset(ends.all[side.allStart + index], side: side.side) - LayeredFlatConstants.portPitch : side.span / 2
            if size > 0 {
                if fit(side, ends: ends, pools: &pools, first: first, size: size, low: low, high: high, isAgain: isAgain) { moved = true }
                first += size
            }
            if isHeld { low = offset(ends.all[side.allStart + index], side: side.side) + LayeredFlatConstants.portPitch }
        }
        return moved
    }

    private func offset(_ segment: Int, side: Int) -> Double { side == 0 ? graph.segmentToOffset[segment] : graph.segmentFromOffset[segment] }

    private func setOffset(_ segment: Int, side: Int, to offset: Double) {
        if side == 0 { graph.segmentToOffset[segment] = offset } else { graph.segmentFromOffset[segment] = offset }
    }

    /// Isotonic fitting of one run of free ends: their order and spacing kept by pooling neighbours that are too close,
    /// a run that cannot fit between its held ends centred between them. Whether an end moved.
    private func fit(_ side: Side, ends: SettledEnds, pools: inout Pools, first: Int, size: Int, low: Double, high: Double,
                     isAgain: Bool) -> Bool {
        let total = pool(side, ends: ends, pools: &pools, first: first, size: size, isAgain: isAgain)
        let sum = pools.sum.elements
        let count = pools.count.elements
        var before: Double = 0
        var moved = false
        var placed = 0
        for block in sum.indices {
            let level = high - total < low ? (low + high - total) / 2 : max(low, min(high - total, sum[block] / Double(count[block])))
            for _ in 0..<count[block] {
                if placed > 0 { before += ends.room[side.segmentStart + first + placed] }
                let segment = ends.segments[side.segmentStart + first + placed]
                if abs(offset(segment, side: side.side) - level - before) > 0.01 { moved = true }
                setOffset(segment, side: side.side, to: level + before)
                placed += 1
            }
        }
        return moved
    }

    /// The wanted places of a run of free ends pooled into blocks, each a sum of places and how many ends it holds, in
    /// `pools`; returns the room the run takes.
    private func pool(_ side: Side, ends: SettledEnds, pools: inout Pools, first: Int, size: Int, isAgain: Bool) -> Double {
        pools.sum.removeAll()
        pools.count.removeAll()
        var before: Double = 0
        for index in 0..<size {
            let at = side.segmentStart + first + index
            if index > 0 { before += ends.room[at] }
            pools.sum.append(wanted(ends.segments[at], side: side.side, vertex: side.vertex, span: side.span, isAgain: isAgain) - before)
            pools.count.append(1)
            // Keep ends together when spacing forced them to share a place.
            var together = index > 0 && ends.room[at] == 0
            while pools.sum.count > 1
                && (together || pools.sum[pools.sum.count - 2] / Double(pools.count[pools.count.count - 2])
                    > pools.sum[pools.sum.count - 1] / Double(pools.count[pools.count.count - 1])) {
                together = false
                let top = pools.sum.removeLast()
                let pooled = pools.count.removeLast()
                pools.sum[pools.sum.count - 1] += top
                pools.count[pools.count.count - 1] += pooled
            }
        }
        return before
    }
}
