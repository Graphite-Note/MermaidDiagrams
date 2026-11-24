/**
 * File: ReferenceLanePass.swift
 * -----------------------------
 * Layer: Tests
 * Description: The 0.7.0 LanePass kept as the reference the lane layout on the scratch arena is checked against: one
 *              pass of the lane layout: the ranked boxes and a point for each rank an edge passes, ordered across each
 *              rank by lane and then by their neighbours, and placed across the flow in their lanes.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 24/11/2026
 */

import CoreGraphics
@testable import MermaidDiagrams

/// One pass of Pele's `place` in `laneLayout`, its vertices the items, then a point for every rank an edge passes through
/// (none for an edge given a plain route of its own, nor for any when there would be more than 20,000). Each rank is
/// ordered by lane first, then by where its vertices' neighbours sit, eight sweeps down and up; across the flow, the
/// vertices of a rank that share a lane sit side by side as a run, first centered in the lane, then moved toward their
/// neighbours in the same lane as far as the lane and the vertices beside them allow.
struct ReferenceLanePass {
    static let laneTitleDepth: CGFloat = 34
    static let sweepCount = 8
    static let maximumPassingPointCount = 20_000
    /// The room a lane keeps beside a handoff along its margin.
    static let marginRoom: CGFloat = 20
    static let alignmentPassCount = 4

    let setup: ReferenceLaneLayoutItems
    let spacing: LayeredSpacing
    /// The edges given a plain route of their own, which keep no room through the ranks they pass.
    let isPlain: [Bool]
    let paddings: [CGFloat]
    private(set) var rank: [Int] = []
    private(set) var lane: [Int] = []
    private(set) var across: [CGFloat] = []
    private(set) var along: [CGFloat] = []
    private(set) var isPassingPoint: [Bool] = []
    private(set) var maximumRank = 0
    private(set) var spans: [Int] = []
    private(set) var firstPassingPoint: [Int?] = []
    private(set) var labelVertex: [Int?] = []
    private(set) var upperNeighbors: [[Int]] = []
    private(set) var lowerNeighbors: [[Int]] = []
    private(set) var rows: [[Int]] = []
    private(set) var position: [Double] = []
    var centers: [CGFloat] = []
    private(set) var laneStarts: [CGFloat] = []
    private(set) var titleDepth: CGFloat = 0

    init(setup: ReferenceLaneLayoutItems, spacing: LayeredSpacing, isPlain: [Bool], keepsMargin: [Bool]) {
        self.setup = setup
        self.spacing = spacing
        self.isPlain = isPlain
        paddings = setup.lanePaddings.enumerated().map { lane, room in keepsMargin[lane] ? max(room, Self.marginRoom) : room }
        addVertices()
        order()
        measureLanes()
        placeAcross()
    }

    var vertexCount: Int { rank.count }

    /// The items, then each edge's passing points, its text on the one in the middle of its span.
    private mutating func addVertices() {
        spans = setup.edges.map { edge in abs(setup.ranks[edge.head] - setup.ranks[edge.tail]) }
        let passingPointCount = zip(setup.edges.indices, spans).reduce(0) { count, pair in isPlain[pair.0] ? count : count + pair.1 - 1 }
        let isDirect = passingPointCount > Self.maximumPassingPointCount
        rank = setup.ranks
        lane = setup.itemLanes
        across = setup.itemAcross
        along = setup.itemAlong
        isPassingPoint = Array(repeating: false, count: setup.items.count)
        maximumRank = rank.max() ?? 0
        upperNeighbors = Array(repeating: [], count: setup.items.count)
        lowerNeighbors = Array(repeating: [], count: setup.items.count)
        firstPassingPoint = Array(repeating: nil, count: setup.edges.count)
        labelVertex = Array(repeating: nil, count: setup.edges.count)
        for (edgeIndex, edge) in setup.edges.enumerated() {
            if isDirect || spans[edgeIndex] < 2 || isPlain[edgeIndex] {
                link(edge.upper, edge.lower)
            } else {
                addPassingPoints(of: edgeIndex)
            }
        }
    }

    /// A point in each rank between the edge's ends, crossing from its first lane to its last evenly along the way.
    private mutating func addPassingPoints(of edgeIndex: Int) {
        let edge = setup.edges[edgeIndex]
        let upperRank = rank[edge.upper]
        let lowerRank = rank[edge.lower]
        var labelRank = -1
        if edge.hasLabel {
            labelRank = upperRank + (lowerRank - upperRank) / 2
            if setup.step == 2, labelRank.isMultiple(of: 2) { labelRank -= 1 }
        }
        firstPassingPoint[edgeIndex] = vertexCount
        var previous = edge.upper
        for passingRank in (upperRank + 1)..<lowerRank {
            let vertex = vertexCount
            let share = CGFloat((lane[edge.lower] - lane[edge.upper]) * (passingRank - upperRank)) / CGFloat(lowerRank - upperRank)
            rank.append(passingRank)
            lane.append(lane[edge.upper] + Int((share + 0.5).rounded(.down)))
            isPassingPoint.append(true)
            across.append(passingRank == labelRank ? edge.labelAcross : 0)
            along.append(passingRank == labelRank ? edge.labelAlong : 0)
            if passingRank == labelRank { labelVertex[edgeIndex] = vertex }
            upperNeighbors.append([])
            lowerNeighbors.append([])
            link(previous, vertex)
            previous = vertex
        }
        link(previous, edge.lower)
    }

    private mutating func link(_ upper: Int, _ lower: Int) {
        lowerNeighbors[upper].append(lower)
        upperNeighbors[lower].append(upper)
    }

    /// Each rank by lane, then by its first order, then eight sweeps that sort each rank by the mean position of each
    /// vertex's neighbours in the rank before (or keep its own position when it has none), by lane first.
    private mutating func order() {
        rows = Array(repeating: [], count: maximumRank + 1)
        for vertex in 0..<vertexCount { rows[rank[vertex]].append(vertex) }
        position = Array(repeating: 0, count: vertexCount)
        var key = [Double](repeating: 0, count: vertexCount)
        for row in rows.indices {
            for (index, vertex) in rows[row].enumerated() { key[vertex] = Double(index) }
            settle(row, key: key)
        }
        guard maximumRank > 0 else { return }
        for sweep in 0..<Self.sweepCount {
            let isDownward = sweep.isMultiple(of: 2)
            for step in 1...maximumRank {
                let row = isDownward ? step : maximumRank - step
                for vertex in rows[row] {
                    let neighbors = isDownward ? upperNeighbors[vertex] : lowerNeighbors[vertex]
                    key[vertex] = neighbors.isEmpty ? position[vertex] : neighbors.reduce(0) { sum, neighbor in sum + position[neighbor] } / Double(neighbors.count)
                }
                settle(row, key: key)
            }
        }
    }

    private mutating func settle(_ row: Int, key: [Double]) {
        rows[row].sort { first, second in (lane[first], key[first], first) < (lane[second], key[second], second) }
        for (index, vertex) in rows[row].enumerated() { position[vertex] = Double(index) }
    }

    /// The gap between two neighbours of a run: the edge separation beside a passing point, else the node separation.
    func gap(_ first: Int, _ second: Int) -> CGFloat {
        isPassingPoint[first] || isPassingPoint[second] ? spacing.edgeSeparation : spacing.nodeSeparation
    }

    /// The runs of a row, each the vertices of one lane side by side, as ranges of the row.
    func runs(of row: [Int]) -> [ClosedRange<Int>] {
        var runs: [ClosedRange<Int>] = []
        var start = 0
        while start < row.count {
            var end = start
            while end + 1 < row.count, lane[row[end + 1]] == lane[row[start]] { end += 1 }
            runs.append(start...end)
            start = end + 1
        }
        return runs
    }

    func runSize(_ row: [Int], _ run: ClosedRange<Int>) -> CGFloat {
        var size = across[row[run.lowerBound]]
        for index in run.lowerBound..<run.upperBound { size += gap(row[index], row[index + 1]) + across[row[index + 1]] }
        return size
    }

    /// Each lane's breadth, enough for its fullest rank and for its title, and where it starts across the flow; the depth
    /// of the lanes' titles, at least 34 points.
    private mutating func measureLanes() {
        let laneCount = setup.laneCount
        var breadth = [CGFloat](repeating: 0, count: laneCount)
        titleDepth = setup.lanes.isEmpty ? 0 : Self.laneTitleDepth
        for (slot, box) in setup.lanes.enumerated() {
            breadth[slot] = max(0, setup.graph.boxes[box].minimumWidth - 2 * paddings[slot])
            titleDepth = max(titleDepth, setup.graph.boxes[box].padding.top)
        }
        for row in rows {
            for run in runs(of: row) { breadth[lane[row[run.lowerBound]]] = max(breadth[lane[row[run.lowerBound]]], runSize(row, run)) }
        }
        laneStarts = [0]
        for slot in 0..<laneCount { laneStarts.append(laneStarts[slot] + breadth[slot] + 2 * paddings[slot]) }
    }

    /// Across the flow: each run centered in its lane, then four passes, down and up, that move each vertex toward the mean
    /// of its neighbours in the same lane in the rank before, as far as its lane and the vertices beside it allow.
    private mutating func placeAcross() {
        centers = Array(repeating: 0, count: vertexCount)
        for row in rows {
            for run in runs(of: row) { center(row, run) }
        }
        guard maximumRank > 0 else { return }
        var wanted = [CGFloat](repeating: 0, count: vertexCount)
        for pass in 0..<Self.alignmentPassCount {
            let isDownward = pass.isMultiple(of: 2)
            for step in 1...maximumRank {
                let row = rows[isDownward ? step : maximumRank - step]
                for vertex in row {
                    let sameLane = (isDownward ? upperNeighbors[vertex] : lowerNeighbors[vertex]).filter { neighbor in lane[neighbor] == lane[vertex] }
                    wanted[vertex] = sameLane.isEmpty ? centers[vertex] : sameLane.reduce(0) { sum, neighbor in sum + centers[neighbor] } / CGFloat(sameLane.count)
                }
                for run in runs(of: row) { align(row, run, wanted: wanted) }
            }
        }
    }

    /// A run centered between its lane's paddings.
    private mutating func center(_ row: [Int], _ run: ClosedRange<Int>) {
        let slot = lane[row[run.lowerBound]]
        var start = (laneStarts[slot] + paddings[slot] + (laneStarts[slot + 1] - paddings[slot]) - runSize(row, run)) / 2
        for index in run {
            centers[row[index]] = start + across[row[index]] / 2
            if index < run.upperBound { start += across[row[index]] + gap(row[index], row[index + 1]) }
        }
    }

    /// A run moved to where its vertices want to be, kept in order, apart and inside its lane's paddings.
    private mutating func align(_ row: [Int], _ run: ClosedRange<Int>, wanted: [CGFloat]) {
        let slot = lane[row[run.lowerBound]]
        var floor = laneStarts[slot] + paddings[slot]
        for index in run {
            let vertex = row[index]
            centers[vertex] = max(wanted[vertex], floor + across[vertex] / 2)
            if index < run.upperBound { floor = centers[vertex] + across[vertex] / 2 + gap(vertex, row[index + 1]) }
        }
        var ceiling = laneStarts[slot + 1] - paddings[slot]
        for index in run.reversed() {
            let vertex = row[index]
            centers[vertex] = min(centers[vertex], ceiling - across[vertex] / 2)
            if index > run.lowerBound { ceiling = centers[vertex] - across[vertex] / 2 - gap(row[index - 1], vertex) }
        }
    }
}
