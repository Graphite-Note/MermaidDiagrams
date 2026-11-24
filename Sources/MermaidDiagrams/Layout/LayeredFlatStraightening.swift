/**
 * File: LayeredFlatStraightening.swift
 * ------------------------------------
 * Layer: Core
 * Description: Moves the bends of Pele's layered layout onto straight lines and leaves out those nothing is in the way of.
 *
 * Authors: Bahey Shalash
 * Version: 0.3
 * Date: 23/11/2026
 */

extension LayeredFlatGraph {
    /// Moves the bends in ranks that hold only bends onto the straight line between the nearest points of their edges
    /// held in place, and marks those left out of the route; only twins, bends of edges between the same two points,
    /// stay, `separation` apart around the line (Pele's `straighten`).
    func straighten(_ across: inout [Double], emptyRanks: [Bool], firstBend: [Int], edgeRankSpan: [Int], separation: Double, isOnLine: inout [Bool],
                    workspace: LayeredFlatWorkspace) {
        var wanted = workspace.numbers(count: across.count, repeating: 0)
        var lineFrom = workspace.numbers(count: across.count, repeating: 0)
        var lineTo = workspace.numbers(count: across.count, repeating: 0)
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
        placeTwins(&across, emptyRanks: emptyRanks, wanted: wanted, lineFrom: lineFrom, lineTo: lineTo, separation: separation, isOnLine: &isOnLine,
                   workspace: workspace)
        workspace.recycle(consume wanted)
        workspace.recycle(consume lineFrom)
        workspace.recycle(consume lineTo)
    }

    private func placeTwins(_ across: inout [Double], emptyRanks: [Bool], wanted: [Double], lineFrom: [Double], lineTo: [Double],
                            separation: Double, isOnLine: inout [Bool], workspace: LayeredFlatWorkspace) {
        guard maximumRank > 1 else { return }
        // One list for each rank's row, one for each run of twins, and the merge sort's spare.
        var row = workspace.emptyIntegers(capacity: 0)
        var twins = workspace.emptyIntegers(capacity: 0)
        var spare = workspace.emptyIntegers(capacity: 0)
        defer {
            workspace.recycle(row)
            workspace.recycle(twins)
            workspace.recycle(spare)
        }
        for rank in 1..<maximumRank where emptyRanks[rank] {
            row.removeAll(keepingCapacity: true)
            row.append(contentsOf: order[rankStart[rank]..<rankStart[rank + 1]])
            row.sortStably(spare: &spare) { first, second in
                if lineFrom[first] != lineFrom[second] { return lineFrom[first] - lineFrom[second] < 0 }
                if lineTo[first] != lineTo[second] { return lineTo[first] - lineTo[second] < 0 }
                return first - second < 0
            }
            var index = 0
            while index < row.count {
                twins.removeAll(keepingCapacity: true)
                var next = index
                while next < row.count && abs(lineFrom[row[next]] - lineFrom[row[index]]) < LayeredFlatConstants.twinDistance
                    && abs(lineTo[row[next]] - lineTo[row[index]]) < LayeredFlatConstants.twinDistance {
                    twins.append(row[next])
                    next += 1
                }
                // The twins keep the order the rank gave them, so that two edges do not swap sides on the way.
                twins.sortStably(spare: &spare) { first, second in position[first] - position[second] < 0 }
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
    func passLabels(_ across: inout [Double], firstBend: [Int], edgeRankSpan: [Int], clearance: Double, isOnLine: inout [Bool],
                    workspace: LayeredFlatWorkspace) {
        guard let isLabelled = labelledRanks(workspace: workspace) else { return }
        defer { workspace.recycle(isLabelled) }
        // The labels of each rank in their order across it, so that a bend is checked against its rank's labels only.
        var labelStart = workspace.integers(count: maximumRank + 2, repeating: 0)
        var labels = workspace.emptyIntegers(capacity: 0)
        defer {
            workspace.recycle(labelStart)
            workspace.recycle(labels)
        }
        for rank in 0...maximumRank {
            labelStart[rank] = labels.count
            for index in rankStart[rank]..<rankStart[rank + 1] where isLabelled[rank] && vertexKind[order[index]] == .label {
                labels.append(order[index])
            }
        }
        labelStart[maximumRank + 1] = labels.count
        for edgeIndex in firstBend.indices where firstBend[edgeIndex] >= 0 {
            let firstOfEdge = firstBend[edgeIndex]
            let end = firstOfEdge + edgeRankSpan[edgeIndex] - 1
            for bend in firstOfEdge..<end where vertexKind[bend] == .bend && isLabelled[vertexRank[bend]] {
                let rank = vertexRank[bend]
                passLabel(bend, firstOfEdge: firstOfEdge, end: end, labels: labels[labelStart[rank]..<labelStart[rank + 1]], across: &across,
                          clearance: clearance, isOnLine: &isOnLine)
            }
        }
    }

    /// The ranks that hold labels and bends only, in a list of `workspace`, or nil when none does.
    private func labelledRanks(workspace: LayeredFlatWorkspace) -> [Bool]? {
        var isLabelled = workspace.flags(count: maximumRank + 1, repeating: false)
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
        if any { return isLabelled }
        workspace.recycle(consume isLabelled)
        return nil
    }

    private func passLabel(_ bend: Int, firstOfEdge: Int, end: Int, labels: ArraySlice<Int>, across: inout [Double], clearance: Double,
                           isOnLine: inout [Bool]) {
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
        for label in labels where across[label] + vertexWidth[label] / 2 > low && across[label] - vertexWidth[label] / 2 < high { return }
        isOnLine[bend] = true
        // The bends left out between the two points lie on the line between them.
        let steps = Double(last - first + 2)
        for passing in first...last { across[passing] = start + (finish - start) * Double(passing - first + 1) / steps }
    }
}
