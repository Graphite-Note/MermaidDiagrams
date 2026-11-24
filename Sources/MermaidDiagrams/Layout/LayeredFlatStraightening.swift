/**
 * File: LayeredFlatStraightening.swift
 * ------------------------------------
 * Layer: Core
 * Description: Moves the bends of Pele's layered layout onto straight lines and leaves out those nothing is in the way of.
 *
 * Authors: Bahey Shalash
 * Version: 0.4
 * Date: 24/11/2026
 */

extension LayeredFlatGraph {
    /// Moves the bends in ranks that hold only bends onto the straight line between the nearest points of their edges
    /// held in place, and marks those left out of the route; only twins, bends of edges between the same two points,
    /// stay, `separation` apart around the line (Pele's `straighten`).
    func straighten(_ across: ScratchSpan<Double>, emptyRanks: ScratchSpan<Bool>, firstBend: ScratchSpan<Int>, edgeRankSpan: ScratchSpan<Int>,
                    separation: Double, isOnLine: ScratchSpan<Bool>, arena: DiagramScratchArena) {
        let mark = arena.mark()
        defer { arena.release(to: mark) }
        let wanted = arena.span(count: across.count, repeating: 0.0)
        let lineFrom = arena.span(count: across.count, repeating: 0.0)
        let lineTo = arena.span(count: across.count, repeating: 0.0)
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
        placeTwins(across, emptyRanks: emptyRanks, wanted: wanted, lineFrom: lineFrom, lineTo: lineTo, separation: separation, isOnLine: isOnLine,
                   arena: arena)
    }

    private func placeTwins(_ across: ScratchSpan<Double>, emptyRanks: ScratchSpan<Bool>, wanted: ScratchSpan<Double>, lineFrom: ScratchSpan<Double>,
                            lineTo: ScratchSpan<Double>, separation: Double, isOnLine: ScratchSpan<Bool>, arena: DiagramScratchArena) {
        guard maximumRank > 1 else { return }
        // One list for each rank's row and one for each run of twins.
        var row = arena.list(capacity: 8, of: Int.self)
        var twins = arena.list(capacity: 8, of: Int.self)
        for rank in 1..<maximumRank where emptyRanks[rank] {
            row.removeAll()
            row.append(contentsOf: order.part(rankStart[rank]..<rankStart[rank + 1]))
            row.sortStably(in: arena) { first, second in
                if lineFrom[first] != lineFrom[second] { return lineFrom[first] - lineFrom[second] < 0 }
                if lineTo[first] != lineTo[second] { return lineTo[first] - lineTo[second] < 0 }
                return first - second < 0
            }
            var index = 0
            while index < row.count {
                twins.removeAll()
                var next = index
                while next < row.count && abs(lineFrom[row[next]] - lineFrom[row[index]]) < LayeredFlatConstants.twinDistance
                    && abs(lineTo[row[next]] - lineTo[row[index]]) < LayeredFlatConstants.twinDistance {
                    twins.append(row[next])
                    next += 1
                }
                // The twins keep the order the rank gave them, so that two edges do not swap sides on the way.
                twins.sortStably(in: arena) { first, second in position[first] - position[second] < 0 }
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
    func passLabels(_ across: ScratchSpan<Double>, firstBend: ScratchSpan<Int>, edgeRankSpan: ScratchSpan<Int>, clearance: Double,
                    isOnLine: ScratchSpan<Bool>, arena: DiagramScratchArena) {
        let mark = arena.mark()
        defer { arena.release(to: mark) }
        guard let isLabelled = labelledRanks(arena: arena) else { return }
        // The labels of each rank in their order across it, so that a bend is checked against its rank's labels only.
        let labelStart = arena.span(count: maximumRank + 2, repeating: 0)
        var labels = arena.list(capacity: vertexCount, of: Int.self)
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
                passLabel(bend, firstOfEdge: firstOfEdge, end: end, labels: labels.elements.part(labelStart[rank]..<labelStart[rank + 1]),
                          across: across, clearance: clearance, isOnLine: isOnLine)
            }
        }
    }

    /// The ranks that hold labels and bends only, in a span of the arena, or nil when none does.
    private func labelledRanks(arena: DiagramScratchArena) -> ScratchSpan<Bool>? {
        let isLabelled = arena.span(count: maximumRank + 1, repeating: false)
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
        return any ? isLabelled : nil
    }

    private func passLabel(_ bend: Int, firstOfEdge: Int, end: Int, labels: ScratchSpan<Int>, across: ScratchSpan<Double>, clearance: Double,
                           isOnLine: ScratchSpan<Bool>) {
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
