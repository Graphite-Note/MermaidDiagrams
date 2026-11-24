/**
 * File: LayeredFlatEndSpreading.swift
 * -----------------------------------
 * Layer: Core
 * Description: Gives the ends of edges on one side of a node places of their own, and lines border ports up with ends.
 *
 * Authors: Bahey Shalash
 * Version: 0.4
 * Date: 23/11/2026
 */

/// The ends on one side of a node, in the order of their other ends, and the room before each.
struct LayeredSideEnds {
    var segments: [Int] = []
    var room: [Double] = []
    var total: Double = 0

    /// Empty lists from `workspace`.
    init(workspace: LayeredFlatWorkspace) {
        segments = workspace.emptyIntegers(capacity: 0)
        room = workspace.emptyNumbers(capacity: 0)
    }

    /// Gives the lists back to `workspace`.
    consuming func recycle(into workspace: LayeredFlatWorkspace) {
        workspace.recycle(segments)
        workspace.recycle(room)
    }
}

extension LayeredFlatGraph {
    /// The ends of edges that may move along one side of `vertex` (0 the side its edges arrive at, 1 the other), ordered
    /// by their other ends, and their least gaps: a full pitch where there is room, else edges that leave side by side
    /// closer together, else neighbours that run the same way sharing a place (Pele's `sideEnds`).
    /// Written into `ends`, whose lists are refilled in place so that one value serves every side.
    func fillSideEnds(of vertex: Int, side: Int, span: Double, kinds: [LayeredSegmentEnd], into ends: inout LayeredSideEnds) {
        let starts = side == 0 ? predecessorStart : successorStart
        let list = side == 0 ? predecessorSegments : successorSegments
        let other = side == 0 ? segmentFrom : segmentTo
        ends.segments.removeAll(keepingCapacity: true)
        ends.room.removeAll(keepingCapacity: true)
        ends.total = 0
        for position in starts[vertex]..<starts[vertex + 1] where kinds[list[position]] != .held { ends.segments.append(list[position]) }
        if ends.segments.count < 2 { return }
        let positions = position
        ends.segments.sortStably { first, second in
            positions[other[first]] != positions[other[second]] ? Double(positions[other[first]] - positions[other[second]]) : Double(first - second)
        }
        func fill(_ share: (_ leaves: Bool, _ same: Bool) -> Double) -> Double {
            var total: Double = 0
            ends.room.removeAll(keepingCapacity: true)
            ends.room.append(0)
            for index in 1..<ends.segments.count {
                let same = kinds[ends.segments[index]] == kinds[ends.segments[index - 1]]
                ends.room.append(share(same && kinds[ends.segments[index]] == .leaves, same))
                total += ends.room[index]
            }
            return total
        }
        var total = fill { _, _ in 1 }
        if span / total < LayeredFlatConstants.minimumPitch { total = fill { leaves, _ in leaves ? 0.5 : 1 } }
        if span / total < LayeredFlatConstants.minimumPitch { total = fill { _, same in same ? 0 : 1 } }
        if total == 0 { return }
        let pitch = min(LayeredFlatConstants.portPitch, span / total)
        for index in 1..<ends.room.count { ends.room[index] *= pitch }
        ends.total = total * pitch
    }

    /// Gives the ends that meet one side of a node places of their own along it, around its middle (Pele's `spread`).
    mutating func spreadEnds(nodes: [LayeredFlatNode], fromEnds: [LayeredSegmentEnd], toEnds: [LayeredSegmentEnd],
                             workspace: LayeredFlatWorkspace) {
        var ends = LayeredSideEnds(workspace: workspace)
        defer { ends.recycle(into: workspace) }
        for vertex in 0..<nodeCount {
            let span = min(nodes[vertex].sideSpan, vertexWidth[vertex])
            if span <= 0 || nodes[vertex].kind != .node { continue }
            for side in 0..<2 {
                fillSideEnds(of: vertex, side: side, span: span, kinds: side == 0 ? toEnds : fromEnds, into: &ends)
                if ends.total == 0 { continue }
                var at = -ends.total / 2
                for index in ends.segments.indices {
                    at += ends.room[index]
                    if side == 0 { segmentToOffset[ends.segments[index]] = at } else { segmentFromOffset[ends.segments[index]] = at }
                }
            }
        }
    }

    /// How many ends that may move each node has on the side its edges arrive at, and on the other (Pele's `freeEnds`):
    /// side `side` of vertex `vertex` at `side * vertexCount + vertex`.
    func freeEnds(fromEnds: [LayeredSegmentEnd], toEnds: [LayeredSegmentEnd], workspace: LayeredFlatWorkspace) -> [Int] {
        var free = workspace.integers(count: 2 * vertexCount, repeating: 0)
        for segment in 0..<segmentCount {
            if toEnds[segment] != .held { free[segmentTo[segment]] += 1 }
            if fromEnds[segment] != .held { free[vertexCount + segmentFrom[segment]] += 1 }
        }
        return free
    }

    /// Aligns border ports with the ends on their nodes so that edges run straight across the gap, where every port of
    /// the rank can move without passing or meeting its neighbours (Pele's `alignPorts`).
    func alignPorts(_ across: inout [Double], emptyRanks: [Bool]?) {
        for (rank, kind) in [(0, LayeredVertexKind.startPort), (maximumRank, LayeredVertexKind.endPort)] {
            let start = rankStart[rank]
            let end = rankStart[rank + 1]
            var targets: [Double] = []
            for index in start..<end {
                let vertex = order[index]
                let isStart = kind == .startPort
                let degree = isStart ? successorStart[vertex + 1] - successorStart[vertex] : predecessorStart[vertex + 1] - predecessorStart[vertex]
                if vertexKind[vertex] != kind || degree != 1 { break }
                let segment = followed(isStart ? successorSegments[successorStart[vertex]] : predecessorSegments[predecessorStart[vertex]],
                                       isUpward: !isStart, emptyRanks: emptyRanks)
                let at = isStart ? across[segmentTo[segment]] + segmentToOffset[segment] : across[segmentFrom[segment]] + segmentFromOffset[segment]
                if let last = targets.last, at < last + LayeredFlatConstants.twinDistance { break }
                targets.append(at)
            }
            if targets.isEmpty || targets.count != end - start { continue }
            for index in start..<end { across[order[index]] = targets[index - start] }
        }
    }
}
