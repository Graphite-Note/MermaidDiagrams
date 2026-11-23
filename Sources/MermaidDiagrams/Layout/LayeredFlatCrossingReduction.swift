/**
 * File: LayeredFlatCrossingReduction.swift
 * ----------------------------------------
 * Layer: Core
 * Description: Orders the ranks of Pele's layered layout: barycenter sweeps, adjacent swaps, two attempts, the mirror.
 *
 * Authors: Bahey Shalash
 * Version: 0.2
 * Date: 23/11/2026
 */

extension LayeredFlatCrossingReduction {
    /// Orders the graph's ranks for few crossings and returns the crossings after and before.
    mutating func reduce() -> (crossings: Int, declared: Int) {
        if widest < 2 { return (0, 0) }
        let declared = count()
        if graph.vertexGroup != nil { prepareGroups() }
        var best = graph.vertexGroup != nil ? count() : declared
        if best == 0 { return (0, declared) }
        var bestOrder = graph.order
        // Require improvements over both the grouped and ungrouped starting orders.
        let start = min(best, declared)
        // The sweeps are run twice from the same start, going down first and going up first; of two orders with as few
        // crossings, the one that keeps more nodes in the order they were given. Only for graphs small enough to be
        // read node by node.
        let initial = graph.order
        let isSmall = graph.vertexCount <= LayeredFlatConstants.smallGraphVertexCount
        var chosen = bestOrder
        var chosenOutOfOrder = Int.max
        for attempt in 0..<(isSmall ? 2 : 1) {
            if attempt > 0 {
                graph.order = initial
                graph.settlePositions()
            }
            let (found, foundOrder) = attemptOrder(attempt: attempt, start: start, initial: initial, isSmall: isSmall)
            let outOfOrder = isSmall ? outOfOrderPairs() : 0
            if attempt == 0 || found < best || (found == best && outOfOrder < chosenOutOfOrder) {
                best = found
                chosen = foundOrder
                chosenOutOfOrder = outOfOrder
            }
        }
        graph.order = chosen
        graph.settlePositions()
        bestOrder = chosen
        // The retained grouped order may exceed the ungrouped threshold; recount it.
        if graph.vertexGroup != nil { best = count() }
        tryMirror(best: best, bestOrder: bestOrder, chosenOutOfOrder: chosenOutOfOrder, isSmall: isSmall)
        return (best, declared)
    }

    /// One attempt: sweeps until four in a row find nothing better, at most 24, then swaps for a small graph.
    private mutating func attemptOrder(attempt: Int, start: Int, initial: [Int], isSmall: Bool) -> (Int, [Int]) {
        var found = start
        var foundOrder = initial
        var sweepIndex = 0
        var stale = 0
        while stale < 4 && sweepIndex < LayeredFlatConstants.maximumSweeps {
            sweep(isDownward: (sweepIndex + attempt) % 2 == 0, isBiasedRight: sweepIndex % 4 >= 2)
            let crossings = count()
            if crossings < found {
                found = crossings
                foundOrder = graph.order
                stale = 0
                if crossings == 0 {
                    break
                }
            }
            sweepIndex += 1
            stale += 1
        }
        graph.order = foundOrder
        if isSmall && found > 0 {
            graph.settlePositions()
            transpose()
            let crossings = count()
            if crossings < found {
                found = crossings
                foundOrder = graph.order
            }
        }
        return (found, foundOrder)
    }

    /// A drawing and its mirror image cross as often: of the two, the one keeping more nodes in their given order.
    private mutating func tryMirror(best: Int, bestOrder: [Int], chosenOutOfOrder: Int, isSmall: Bool) {
        guard isSmall, !pins.contains(where: { pin in pin != 0 }) else { return }
        if chosenOutOfOrder == 0 || graph.isRankFixed[0] || graph.isRankFixed[graph.maximumRank] { return }
        for rank in 0...graph.maximumRank { graph.order[graph.rankStart[rank]..<graph.rankStart[rank + 1]].reverse() }
        graph.settlePositions()
        if count() > best || outOfOrderPairs() >= chosenOutOfOrder { graph.order = bestOrder }
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
            var moving = measureBarycenters(rank: rank, isDownward: isDownward)
            if graph.vertexGroup != nil {
                arrange(rank: rank, keys: barycenter)
                continue
            }
            if moving.count < 2 { continue }
            let position = graph.position
            moving.sortStably { first, second in
                barycenter[first] != barycenter[second] ? barycenter[first] - barycenter[second]
                    : Double(isBiasedRight ? position[second] - position[first] : position[first] - position[second])
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

    /// Each vertex's barycenter in `rank` from its neighbours above (downward) or below; returns those that move.
    private mutating func measureBarycenters(rank: Int, isDownward: Bool) -> [Int] {
        let start = graph.rankStart[rank]
        let end = graph.rankStart[rank + 1]
        let neighbourStart = isDownward ? graph.predecessorStart : graph.successorStart
        let list = isDownward ? graph.predecessorSegments : graph.successorSegments
        let other = isDownward ? graph.segmentFrom : graph.segmentTo
        let otherOffset = isDownward ? graph.segmentFromOffset : graph.segmentToOffset
        var moving: [Int] = []
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
        return moving
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
