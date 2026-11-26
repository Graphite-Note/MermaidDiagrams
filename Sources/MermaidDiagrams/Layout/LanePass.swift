/**
 * File: LanePass.swift
 * --------------------
 * Layer: Core
 * Description: One pass of the lane layout on spans of the thread's scratch arena: the ranked boxes and a point for
 *              each rank an edge passes, ordered across each rank by lane and then by their neighbours, and placed
 *              across the flow in their lanes.
 *
 * Authors: Bahey Shalash
 * Version: 0.3
 * Date: 26/11/2026
 */

import CoreGraphics

/// One pass of Pele's `place` in `laneLayout`, its vertices the items, then a point for every rank an edge passes through
/// (none for an edge given a plain route of its own, nor for any when there would be more than 20,000). Each rank is
/// ordered by lane first, then by where its vertices' neighbours sit, eight sweeps down and up; across the flow, the
/// vertices of a rank that share a lane sit side by side as a run, first centered in the lane, then moved toward their
/// neighbours in the same lane as far as the lane and the vertices beside them allow. A vertex's neighbours are one list
/// with a start per vertex, in the order they were linked, and the ranks' vertices one list with a start per rank.
struct LanePass {
    static let laneTitleDepth: CGFloat = 34
    static let sweepCount = 8
    static let maximumPassingPointCount = 20_000
    /// The room a lane keeps beside a handoff along its margin.
    static let marginRoom: CGFloat = 20
    static let alignmentPassCount = 4

    let setup: LaneLayoutItems
    let spacing: LayeredSpacing
    /// The edges given a plain route of their own, which keep no room through the ranks they pass.
    let isPlain: ScratchSpan<Bool>
    let paddings: ScratchSpan<CGFloat>
    let vertexCount: Int
    let rank: ScratchSpan<Int>
    let lane: ScratchSpan<Int>
    let across: ScratchSpan<CGFloat>
    let along: ScratchSpan<CGFloat>
    let isPassingPoint: ScratchSpan<Bool>
    let maximumRank: Int
    /// By ranked edge: the ranks it spans, its first passing point and the one that holds its text (-1 for none).
    let spans: ScratchSpan<Int>
    let firstPassingPoint: ScratchSpan<Int>
    let labelVertex: ScratchSpan<Int>
    let upperNeighbors: LaneAdjacency
    let lowerNeighbors: LaneAdjacency
    /// The vertices of rank `r` are `rowVertices[rowStarts[r]..<rowStarts[r + 1]]`, in their order across the rank.
    let rowStarts: ScratchSpan<Int>
    let rowVertices: ScratchSpan<Int>
    let position: ScratchSpan<Double>
    let centers: ScratchSpan<CGFloat>
    let laneStarts: ScratchSpan<CGFloat>
    let titleDepth: CGFloat

    init(setup: LaneLayoutItems, spacing: LayeredSpacing, isPlain: ScratchSpan<Bool>, keepsMargin: ScratchSpan<Bool>, arena: DiagramScratchArena) {
        self.setup = setup
        self.spacing = spacing
        self.isPlain = isPlain
        let paddings: ScratchSpan<CGFloat> = arena.uninitializedSpan(count: setup.laneCount)
        for lane in 0..<setup.laneCount { paddings[lane] = keepsMargin[lane] ? max(setup.lanePaddings[lane], Self.marginRoom) : setup.lanePaddings[lane] }
        self.paddings = paddings
        let vertices = LanePassVertices(setup: setup, isPlain: isPlain, arena: arena)
        vertexCount = vertices.vertexCount
        rank = vertices.rank
        lane = vertices.lane
        across = vertices.across
        along = vertices.along
        isPassingPoint = vertices.isPassingPoint
        maximumRank = vertices.maximumRank
        spans = vertices.spans
        firstPassingPoint = vertices.firstPassingPoint
        labelVertex = vertices.labelVertex
        let uppers = vertices.linkUppers
        let lowers = vertices.linkLowers
        upperNeighbors = LaneAdjacency(nodeCount: vertices.vertexCount, count: uppers.count, arena: arena, nodeOf: { link in lowers[link] }) { link in uppers[link] }
        lowerNeighbors = LaneAdjacency(nodeCount: vertices.vertexCount, count: uppers.count, arena: arena, nodeOf: { link in uppers[link] }) { link in lowers[link] }
        let vertexRanks = vertices.rank
        let rows = LaneAdjacency(nodeCount: vertices.maximumRank + 1, count: vertices.vertexCount, arena: arena) { vertex in vertexRanks[vertex] }
        rowStarts = rows.starts
        rowVertices = rows.members
        position = arena.span(count: vertices.vertexCount, repeating: 0)
        centers = arena.span(count: vertices.vertexCount, repeating: 0)
        laneStarts = arena.span(count: setup.laneCount + 1, repeating: 0)
        titleDepth = Self.titleDepth(setup)
        order(arena: arena)
        measureLanes(arena: arena)
        placeAcross(arena: arena)
    }

    /// The depth of the lanes' titles, at least 34 points.
    private static func titleDepth(_ setup: LaneLayoutItems) -> CGFloat {
        var depth = setup.lanes.isEmpty ? 0 : laneTitleDepth
        for box in setup.lanes { depth = max(depth, setup.boxes[box].padding.top) }
        return depth
    }

    @inline(__always)
    func rowRange(_ row: Int) -> Range<Int> { rowStarts[row]..<rowStarts[row + 1] }

    /// Each rank by lane, then by its first order, then eight sweeps that sort each rank by the mean position of each
    /// vertex's neighbours in the rank before (or keep its own position when it has none), by lane first. A sweep is a
    /// function of the ranks' orders alone, so once a sweep down and the sweep up after it, or the other way round, both
    /// leave every rank as it was, the sweeps left would too, and they are not run.
    private func order(arena: DiagramScratchArena) {
        let mark = arena.mark()
        defer { arena.release(to: mark) }
        let key = arena.span(count: vertexCount, repeating: Double(0))
        for row in 0...maximumRank {
            for (index, slot) in rowRange(row).enumerated() { key[rowVertices[slot]] = Double(index) }
            _ = settle(row, key: key, arena: arena)
        }
        guard maximumRank > 0 else { return }
        var unchangedSweeps = 0
        for sweep in 0..<Self.sweepCount {
            guard unchangedSweeps < 2 else { return }
            var isChanged = false
            let isDownward = sweep.isMultiple(of: 2)
            let neighbors = isDownward ? upperNeighbors : lowerNeighbors
            for step in 1...maximumRank {
                let row = isDownward ? step : maximumRank - step
                for slot in rowRange(row) {
                    let vertex = rowVertices[slot]
                    let count = neighbors.count(of: vertex)
                    guard count > 0 else {
                        key[vertex] = position[vertex]
                        continue
                    }
                    var sum: Double = 0
                    for neighborSlot in neighbors.range(of: vertex) { sum += position[neighbors.members[neighborSlot]] }
                    key[vertex] = sum / Double(count)
                }
                if settle(row, key: key, arena: arena) { isChanged = true }
            }
            unchangedSweeps = isChanged ? 0 : unchangedSweeps + 1
        }
    }

    /// A rank sorted by lane, key and vertex, a strict order every sort agrees on, and each vertex's position in it;
    /// whether the rank's order changed. Each vertex's position was its place in the rank before the sort, so a position
    /// changes exactly when the order does.
    private func settle(_ row: Int, key: ScratchSpan<Double>, arena: DiagramScratchArena) -> Bool {
        let range = rowRange(row)
        let lane = lane
        rowVertices.sortStably(range, in: arena) { first, second in (lane[first], key[first], first) < (lane[second], key[second], second) }
        var isChanged = false
        for (index, slot) in range.enumerated() {
            let vertex = rowVertices[slot]
            if position[vertex] != Double(index) { isChanged = true }
            position[vertex] = Double(index)
        }
        return isChanged
    }

    /// The gap between two neighbours of a run: the edge separation beside a passing point, else the node separation.
    @inline(__always)
    func gap(_ first: Int, _ second: Int) -> CGFloat {
        isPassingPoint[first] || isPassingPoint[second] ? spacing.edgeSeparation : spacing.nodeSeparation
    }

    /// The end of the run of the ranks' list that starts at `start` and ends before `end`: the vertices of one lane side
    /// by side.
    @inline(__always)
    func runEnd(from start: Int, before end: Int) -> Int {
        var last = start
        while last + 1 < end, lane[rowVertices[last + 1]] == lane[rowVertices[start]] { last += 1 }
        return last
    }

    /// The breadth of the run from `first` to `last` of the ranks' list.
    func runSize(_ first: Int, _ last: Int) -> CGFloat {
        var size = across[rowVertices[first]]
        for index in first..<last { size += gap(rowVertices[index], rowVertices[index + 1]) + across[rowVertices[index + 1]] }
        return size
    }

    /// Each lane's breadth, enough for its fullest rank and for its title, and where it starts across the flow.
    private func measureLanes(arena: DiagramScratchArena) {
        let mark = arena.mark()
        defer { arena.release(to: mark) }
        let laneCount = setup.laneCount
        let breadth = arena.span(count: laneCount, repeating: CGFloat(0))
        for (slot, box) in setup.lanes.enumerated() { breadth[slot] = max(0, setup.boxes[box].minimumWidth - 2 * paddings[slot]) }
        for row in 0...maximumRank {
            let range = rowRange(row)
            var start = range.lowerBound
            while start < range.upperBound {
                let last = runEnd(from: start, before: range.upperBound)
                let runLane = lane[rowVertices[start]]
                breadth[runLane] = max(breadth[runLane], runSize(start, last))
                start = last + 1
            }
        }
        laneStarts[0] = 0
        for slot in 0..<laneCount { laneStarts[slot + 1] = laneStarts[slot] + breadth[slot] + 2 * paddings[slot] }
    }

    /// Across the flow: each run centered in its lane, then four passes, down and up, that move each vertex toward the mean
    /// of its neighbours in the same lane in the rank before, as far as its lane and the vertices beside it allow. A pass
    /// is a function of the centers alone, so once two passes in a row move no center by a bit, the passes left would
    /// not either, and they are not run.
    private func placeAcross(arena: DiagramScratchArena) {
        for row in 0...maximumRank {
            let range = rowRange(row)
            var start = range.lowerBound
            while start < range.upperBound {
                let last = runEnd(from: start, before: range.upperBound)
                center(start, last)
                start = last + 1
            }
        }
        guard maximumRank > 0 else { return }
        let mark = arena.mark()
        defer { arena.release(to: mark) }
        let wanted = arena.span(count: vertexCount, repeating: CGFloat(0))
        var unchangedPasses = 0
        for pass in 0..<Self.alignmentPassCount {
            guard unchangedPasses < 2 else { return }
            var isChanged = false
            let isDownward = pass.isMultiple(of: 2)
            let neighbors = isDownward ? upperNeighbors : lowerNeighbors
            for step in 1...maximumRank {
                let range = rowRange(isDownward ? step : maximumRank - step)
                for slot in range { wanted[rowVertices[slot]] = wantedCenter(of: rowVertices[slot], neighbors: neighbors) }
                var start = range.lowerBound
                while start < range.upperBound {
                    let last = runEnd(from: start, before: range.upperBound)
                    if align(start, last, wanted: wanted) { isChanged = true }
                    start = last + 1
                }
            }
            unchangedPasses = isChanged ? 0 : unchangedPasses + 1
        }
    }

    /// The mean center of the vertex's neighbours in its lane, or its own center when it has none there.
    private func wantedCenter(of vertex: Int, neighbors: LaneAdjacency) -> CGFloat {
        var sum: CGFloat = 0
        var count = 0
        for neighborSlot in neighbors.range(of: vertex) {
            let neighbor = neighbors.members[neighborSlot]
            guard lane[neighbor] == lane[vertex] else { continue }
            sum += centers[neighbor]
            count += 1
        }
        return count == 0 ? centers[vertex] : sum / CGFloat(count)
    }

    /// A run centered between its lane's paddings.
    private func center(_ first: Int, _ last: Int) {
        let slot = lane[rowVertices[first]]
        var start = (laneStarts[slot] + paddings[slot] + (laneStarts[slot + 1] - paddings[slot]) - runSize(first, last)) / 2
        for index in first...last {
            let vertex = rowVertices[index]
            centers[vertex] = start + across[vertex] / 2
            if index < last { start += across[vertex] + gap(vertex, rowVertices[index + 1]) }
        }
    }

    /// A run moved to where its vertices want to be, kept in order, apart and inside its lane's paddings; whether any of
    /// its centers changed, to the bit. A vertex's wanted center, read once, keeps its center from before.
    private func align(_ first: Int, _ last: Int, wanted: ScratchSpan<CGFloat>) -> Bool {
        let slot = lane[rowVertices[first]]
        var floor = laneStarts[slot] + paddings[slot]
        for index in first...last {
            let vertex = rowVertices[index]
            let before = centers[vertex]
            centers[vertex] = max(wanted[vertex], floor + across[vertex] / 2)
            wanted[vertex] = before
            if index < last { floor = centers[vertex] + across[vertex] / 2 + gap(vertex, rowVertices[index + 1]) }
        }
        var isChanged = false
        var ceiling = laneStarts[slot + 1] - paddings[slot]
        for index in stride(from: last, through: first, by: -1) {
            let vertex = rowVertices[index]
            centers[vertex] = min(centers[vertex], ceiling - across[vertex] / 2)
            if centers[vertex].bitPattern != wanted[vertex].bitPattern { isChanged = true }
            if index > first { ceiling = centers[vertex] - across[vertex] / 2 - gap(rowVertices[index - 1], vertex) }
        }
        return isChanged
    }
}
