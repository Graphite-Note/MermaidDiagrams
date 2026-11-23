/**
 * File: LayeredFlatStraightening.swift
 * ------------------------------------
 * Layer: Core
 * Description: Moves the bends of Pele's layered layout onto straight lines and leaves out those nothing is in the way of.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 23/11/2026
 */

extension LayeredFlatGraph {
    /// Moves the bends in ranks that hold only bends onto the straight line between the nearest points of their edges
    /// held in place, and marks those left out of the route; only twins, bends of edges between the same two points,
    /// stay, `separation` apart around the line (Pele's `straighten`).
    func straighten(_ across: inout [Double], emptyRanks: [Bool], firstBend: [Int], edgeRankSpan: [Int], separation: Double, isOnLine: inout [Bool]) {
        var wanted = [Double](repeating: 0, count: across.count)
        var lineFrom = [Double](repeating: 0, count: across.count)
        var lineTo = [Double](repeating: 0, count: across.count)
        for edgeIndex in firstBend.indices where firstBend[edgeIndex] >= 0 {
            let firstOfEdge = firstBend[edgeIndex]
            let end = firstOfEdge + edgeRankSpan[edgeIndex] - 1
            // A bend's rank is its place in the run, counted from the rank after the edge's first node.
            let base = vertexRank[firstOfEdge]
            var bend = firstOfEdge
            while bend < end {
                if !emptyRanks[base + bend - firstOfEdge] {
                    bend += 1
                    continue
                }
                var last = bend
                while last + 1 < end && emptyRanks[base + last + 1 - firstOfEdge] { last += 1 }
                let above = predecessorSegments[predecessorStart[bend]]
                let below = successorSegments[successorStart[last]]
                let start = across[segmentFrom[above]] + segmentFromOffset[above]
                let finish = across[segmentTo[below]] + segmentToOffset[below]
                let steps = Double(last - bend + 2)
                for passing in bend...last {
                    wanted[passing] = start + (finish - start) * Double(passing - bend + 1) / steps
                    lineFrom[passing] = start
                    lineTo[passing] = finish
                }
                bend = last + 1
            }
        }
        placeTwins(&across, emptyRanks: emptyRanks, wanted: wanted, lineFrom: lineFrom, lineTo: lineTo, separation: separation, isOnLine: &isOnLine)
    }

    private func placeTwins(_ across: inout [Double], emptyRanks: [Bool], wanted: [Double], lineFrom: [Double], lineTo: [Double],
                            separation: Double, isOnLine: inout [Bool]) {
        guard maximumRank > 1 else { return }
        for rank in 1..<maximumRank where emptyRanks[rank] {
            var row = Array(order[rankStart[rank]..<rankStart[rank + 1]])
            row.sortStably { first, second in
                if lineFrom[first] != lineFrom[second] { return lineFrom[first] - lineFrom[second] }
                if lineTo[first] != lineTo[second] { return lineTo[first] - lineTo[second] }
                return Double(first - second)
            }
            var index = 0
            while index < row.count {
                var twins: [Int] = []
                var next = index
                while next < row.count && abs(lineFrom[row[next]] - lineFrom[row[index]]) < LayeredFlatConstants.twinDistance
                    && abs(lineTo[row[next]] - lineTo[row[index]]) < LayeredFlatConstants.twinDistance {
                    twins.append(row[next])
                    next += 1
                }
                // The twins keep the order the rank gave them, so that two edges do not swap sides on the way.
                twins.sortStably { first, second in Double(position[first] - position[second]) }
                for (twinIndex, twin) in twins.enumerated() {
                    across[twin] = wanted[twin] + (Double(twinIndex) - Double(twins.count - 1) / 2) * separation
                    if twins.count == 1 || separation == 0 { isOnLine[twin] = true }
                }
                index = next
            }
        }
    }

    /// In a rank of labels and bends only, a bend that its edge would pass clear of every label without is left out,
    /// and the edge turns in the whole height between the ranks either side (Pele's `pastLabels`).
    func passLabels(_ across: inout [Double], firstBend: [Int], edgeRankSpan: [Int], clearance: Double, isOnLine: inout [Bool]) {
        var isLabelled = [Bool](repeating: false, count: maximumRank + 1)
        var any = false
        for rank in 1..<max(1, maximumRank) {
            var hasLabels = false
            var hasOthers = false
            for index in rankStart[rank]..<rankStart[rank + 1] {
                let kind = vertexKind[order[index]]
                if kind == .label { hasLabels = true } else if kind != .bend { hasOthers = true }
            }
            if hasLabels && !hasOthers {
                isLabelled[rank] = true
                any = true
            }
        }
        if !any { return }
        for edgeIndex in firstBend.indices where firstBend[edgeIndex] >= 0 {
            let firstOfEdge = firstBend[edgeIndex]
            let end = firstOfEdge + edgeRankSpan[edgeIndex] - 1
            for bend in firstOfEdge..<end where vertexKind[bend] == .bend && isLabelled[vertexRank[bend]] {
                passLabel(bend, firstOfEdge: firstOfEdge, end: end, across: &across, clearance: clearance, isOnLine: &isOnLine)
            }
        }
    }

    private func passLabel(_ bend: Int, firstOfEdge: Int, end: Int, across: inout [Double], clearance: Double, isOnLine: inout [Bool]) {
        // The points on either side that the edge is held at, past any bends already left out.
        var first = bend
        var last = bend
        while first > firstOfEdge && isOnLine[first - 1] { first -= 1 }
        while last + 1 < end && isOnLine[last + 1] { last += 1 }
        let above = predecessorSegments[predecessorStart[first]]
        let below = successorSegments[successorStart[last]]
        let start = across[segmentFrom[above]] + segmentFromOffset[above]
        let finish = across[segmentTo[below]] + segmentToOffset[below]
        let low = min(start, finish) - clearance
        let high = max(start, finish) + clearance
        let rank = vertexRank[bend]
        for index in rankStart[rank]..<rankStart[rank + 1] {
            let label = order[index]
            if vertexKind[label] == .label && across[label] + vertexWidth[label] / 2 > low && across[label] - vertexWidth[label] / 2 < high { return }
        }
        isOnLine[bend] = true
        // The bends left out between the two points lie on the line between them.
        let steps = Double(last - first + 2)
        for passing in first...last { across[passing] = start + (finish - start) * Double(passing - first + 1) / steps }
    }
}
