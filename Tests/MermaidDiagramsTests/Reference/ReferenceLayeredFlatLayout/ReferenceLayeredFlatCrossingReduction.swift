/**
 * File: ReferenceLayeredFlatCrossingReduction.swift
 * -------------------------------------------------
 * Layer: Tests
 * Description: The 0.7.0 layered layout kept as the reference the span layout is checked against: orders the ranks of
 *              Pele's layered layout: barycenter sweeps, adjacent swaps, two attempts, the mirror.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 24/11/2026
 */

@testable import MermaidDiagrams

extension ReferenceLayeredFlatCrossingReduction {
    /// Orders the graph's ranks for few crossings and returns the crossings after and before.
    mutating func reduce() -> (crossings: Int, declared: Int) {
        if widest < 2 { return (0, 0) }
        let declared = count()
        if graph.vertexGroup != nil { prepareGroups() }
        var best = graph.vertexGroup != nil ? count() : declared
        if best == 0 { return (0, declared) }
        // Require improvements over both the grouped and ungrouped starting orders.
        let start = min(best, declared)
        // The sweeps are run twice from the same start, going down first and going up first; of two orders with as few
        // crossings, the one that keeps more nodes in the order they were given. Only for graphs small enough to be
        // read node by node. The orders are kept in three lists of the workspace, copied into rather than shared.
        var initial = workspace.emptyIntegers(capacity: graph.vertexCount)
        initial.append(contentsOf: graph.order)
        var chosen = workspace.emptyIntegers(capacity: graph.vertexCount)
        chosen.append(contentsOf: graph.order)
        var found = workspace.emptyIntegers(capacity: graph.vertexCount)
        let isSmall = graph.vertexCount <= LayeredFlatConstants.smallGraphVertexCount
        var chosenOutOfOrder = Int.max
        for attempt in 0..<(isSmall ? 2 : 1) {
            if attempt > 0 {
                Self.copy(initial, into: &graph.order)
                graph.settlePositions()
            }
            let foundCrossings = attemptOrder(attempt: attempt, start: start, initial: initial, isSmall: isSmall, found: &found)
            let outOfOrder = isSmall ? outOfOrderPairs() : 0
            if attempt == 0 || foundCrossings < best || (foundCrossings == best && outOfOrder < chosenOutOfOrder) {
                best = foundCrossings
                Self.copy(found, into: &chosen)
                chosenOutOfOrder = outOfOrder
            }
        }
        Self.copy(chosen, into: &graph.order)
        graph.settlePositions()
        // The retained grouped order may exceed the ungrouped threshold; recount it.
        if graph.vertexGroup != nil { best = count() }
        tryMirror(best: best, bestOrder: chosen, chosenOutOfOrder: chosenOutOfOrder, isSmall: isSmall)
        workspace.recycle(consume initial)
        workspace.recycle(consume chosen)
        workspace.recycle(consume found)
        return (best, declared)
    }

    /// `target` made a copy of `source`, in its own storage.
    private static func copy(_ source: [Int], into target: inout [Int]) {
        target.removeAll(keepingCapacity: true)
        target.append(contentsOf: source)
    }

    /// One attempt: sweeps until four in a row find nothing better, at most 24, then swaps for a small graph. Returns
    /// the crossings of the order it found, written to `foundOrder`.
    private mutating func attemptOrder(attempt: Int, start: Int, initial: [Int], isSmall: Bool, found foundOrder: inout [Int]) -> Int {
        var found = start
        Self.copy(initial, into: &foundOrder)
        var sweepIndex = 0
        var stale = 0
        while stale < 4 && sweepIndex < LayeredFlatConstants.maximumSweeps {
            sweep(isDownward: (sweepIndex + attempt) % 2 == 0, isBiasedRight: sweepIndex % 4 >= 2)
            let crossings = count()
            if crossings < found {
                found = crossings
                Self.copy(graph.order, into: &foundOrder)
                stale = 0
                if crossings == 0 {
                    break
                }
            }
            sweepIndex += 1
            stale += 1
        }
        Self.copy(foundOrder, into: &graph.order)
        if isSmall && found > 0 {
            graph.settlePositions()
            transpose()
            let crossings = count()
            if crossings < found {
                found = crossings
                Self.copy(graph.order, into: &foundOrder)
            }
        }
        return found
    }

    /// A drawing and its mirror image cross as often: of the two, the one keeping more nodes in their given order.
    private mutating func tryMirror(best: Int, bestOrder: [Int], chosenOutOfOrder: Int, isSmall: Bool) {
        guard isSmall, !pins.contains(where: { pin in pin != 0 }) else { return }
        if chosenOutOfOrder == 0 || graph.isRankFixed[0] || graph.isRankFixed[graph.maximumRank] { return }
        for rank in 0...graph.maximumRank { graph.order[graph.rankStart[rank]..<graph.rankStart[rank + 1]].reverse() }
        graph.settlePositions()
        if count() > best || outOfOrderPairs() >= chosenOutOfOrder { Self.copy(bestOrder, into: &graph.order) }
    }

    /// How many pairs of nodes in one rank are not in the order they were given.
    private func outOfOrderPairs() -> Int {
        var total = 0
        for rank in 0...graph.maximumRank {
            let end = graph.rankStart[rank + 1]
            for index in graph.rankStart[rank]..<end where graph.order[index] < graph.nodeCount {
                for later in (index + 1)..<max(index + 1, end) where graph.order[later] < graph.order[index] { total += 1 }
            }
        }
        return total
    }

    /// One barycenter sweep down (each rank by its upper neighbours) or up, ties broken towards the left or right.
    private mutating func sweep(isDownward: Bool, isBiasedRight: Bool) {
        for step in 1...max(1, graph.maximumRank) where step <= graph.maximumRank {
            let rank = isDownward ? step : graph.maximumRank - step
            if graph.isRankFixed[rank] { continue }
            var moving: [Int] = []
            swap(&moving, &movingVertices)
            defer { swap(&moving, &movingVertices) }
            measureBarycenters(rank: rank, isDownward: isDownward, into: &moving)
            if graph.vertexGroup != nil {
                arrange(rank: rank, keys: barycenter)
                continue
            }
            if moving.count < 2 { continue }
            // As `sortStably(by:)` with barycenter[first] - barycenter[second], or else the positions' difference
            // (towards the bias), as the comparison: a negative one puts `first` first.
            barycenter.withUnsafeBufferPointer { barycenter in
                graph.position.withUnsafeBufferPointer { position in
                    moving.sortStably(spare: &sortSpare) { first, second in
                        barycenter[first] != barycenter[second] ? barycenter[first] - barycenter[second] < 0
                            : (isBiasedRight ? position[second] < position[first] : position[first] < position[second])
                    }
                }
            }
            let start = graph.rankStart[rank]
            var next = 0
            for index in start..<graph.rankStart[rank + 1] where barycenter[graph.order[index]] != -1 {
                graph.order[index] = moving[next]
                next += 1
            }
            for index in start..<graph.rankStart[rank + 1] { graph.position[graph.order[index]] = index - start }
        }
    }

    /// Each vertex's barycenter in `rank` from its neighbours above (downward) or below; puts those that move in
    /// `moving`.
    private mutating func measureBarycenters(rank: Int, isDownward: Bool, into moving: inout [Int]) {
        let start = graph.rankStart[rank]
        let end = graph.rankStart[rank + 1]
        let neighbourStart = isDownward ? graph.predecessorStart : graph.successorStart
        let list = isDownward ? graph.predecessorSegments : graph.successorSegments
        let other = isDownward ? graph.segmentFrom : graph.segmentTo
        let otherOffset = isDownward ? graph.segmentFromOffset : graph.segmentToOffset
        moving.removeAll(keepingCapacity: true)
        moving.reserveCapacity(end - start)
        for index in start..<end {
            let vertex = graph.order[index]
            let pin = vertex < graph.nodeCount ? pins[vertex] : 0
            if pin != 0 {
                barycenter[vertex] = Double(pin) * 1e9
                moving.append(vertex)
                continue
            }
            let from = neighbourStart[vertex]
            let to = neighbourStart[vertex + 1]
            if from == to {
                if graph.vertexGroup != nil {
                    // Preserve relative position when there are no neighbours in the adjacent rank.
                    let across = isDownward ? graph.rankStart[rank] - graph.rankStart[rank - 1] : graph.rankStart[rank + 2] - graph.rankStart[rank + 1]
                    barycenter[vertex] = Double((index - start) * across) / Double(end - start)
                    continue
                }
                barycenter[vertex] = -1
                continue
            }
            var sum: Double = 0
            for position in from..<to {
                let neighbour = other[list[position]]
                sum += Double(graph.position[neighbour])
                if graph.hasOffsets && graph.vertexWidth[neighbour] > 0 { sum += otherOffset[list[position]] / graph.vertexWidth[neighbour] }
            }
            barycenter[vertex] = sum / Double(to - from)
            moving.append(vertex)
        }
    }

    /// Adjacent swaps that remove crossings the sweeps missed, in up to eight passes.
    private mutating func transpose() {
        for _ in 0..<8 {
            var improved = false
            for rank in 0...graph.maximumRank where !graph.isRankFixed[rank] {
                let start = graph.rankStart[rank]
                var index = start
                while index + 1 < graph.rankStart[rank + 1] {
                    let first = graph.order[index]
                    let second = graph.order[index + 1]
                    let sameGroup = graph.vertexGroup.map { groups in groups[first] == groups[second] } ?? true
                    if pin(first) == pin(second) && sameGroup && crossings(between: second, and: first) < crossings(between: first, and: second) {
                        graph.order[index] = second
                        graph.order[index + 1] = first
                        graph.position[second] = index - start
                        graph.position[first] = index + 1 - start
                        improved = true
                    }
                    index += 1
                }
            }
            if !improved { break }
        }
    }

    private func pin(_ vertex: Int) -> Int { vertex < graph.nodeCount ? pins[vertex] : 0 }

    /// Where segment `segment` meets its upper (`isUpper`) or lower vertex, as a position in that rank.
    private func meeting(_ segment: Int, isUpper: Bool) -> Double {
        let vertex = isUpper ? graph.segmentFrom[segment] : graph.segmentTo[segment]
        let offset = isUpper ? graph.segmentFromOffset[segment] : graph.segmentToOffset[segment]
        return graph.hasOffsets && graph.vertexWidth[vertex] > 0 ? Double(graph.position[vertex]) + offset / graph.vertexWidth[vertex]
            : Double(graph.position[vertex])
    }

    /// The crossings between the edges of `left` and `right`, with `left` placed before `right`.
    private func crossings(between left: Int, and right: Int) -> Int {
        var total = 0
        for position in graph.predecessorStart[left]..<graph.predecessorStart[left + 1] {
            let across = meeting(graph.predecessorSegments[position], isUpper: true)
            for other in graph.predecessorStart[right]..<graph.predecessorStart[right + 1]
            where across > meeting(graph.predecessorSegments[other], isUpper: true) { total += 1 }
        }
        for position in graph.successorStart[left]..<graph.successorStart[left + 1] {
            let across = meeting(graph.successorSegments[position], isUpper: false)
            for other in graph.successorStart[right]..<graph.successorStart[right + 1]
            where across > meeting(graph.successorSegments[other], isUpper: false) { total += 1 }
        }
        return total
    }
}
