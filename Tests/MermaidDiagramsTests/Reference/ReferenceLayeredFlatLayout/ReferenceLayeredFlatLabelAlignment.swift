/**
 * File: ReferenceLayeredFlatLabelAlignment.swift
 * ----------------------------------------------
 * Layer: Tests
 * Description: The 0.7.0 layered layout kept as the reference the span layout is checked against: brings the labels and
 *              bends of each edge of Pele's layered layout into line with one of its ends.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 24/11/2026
 */

@testable import MermaidDiagrams

/// Pele's `alignLabels` (layout/layered.ts): an edge runs straight from the end with fewer edges beside it, or else the
/// other, as far as what is beside its labels and bends leaves room, and turns once, at the other end. Bends in ranks
/// that hold nothing else are left to straightening.
struct ReferenceLayeredFlatLabelAlignment {
    /// Moved in and back out by the caller, so that the graph is never copied.
    var graph: ReferenceLayeredFlatGraph
    let nodes: [LayeredFlatNode]
    /// How many free ends each side of each vertex has, side 0 first (`ReferenceLayeredFlatGraph.freeEnds`).
    let free: [Int]
    let options: LayeredFlatOptions
    let emptyRanks: [Bool]?

    private func isPlaced(_ vertex: Int) -> Bool {
        graph.vertexKind[vertex] == .label || (graph.vertexKind[vertex] == .bend && !(emptyRanks?[graph.vertexRank[vertex]] ?? false))
    }

    /// Where `segment` ends on the way up (side 0) or down, and how many ends share that side of the node there.
    private func end(of segment: Int, side: Int, across: [Double]) -> (at: Double, sharing: Int) {
        let vertex = side == 0 ? graph.segmentFrom[segment] : graph.segmentTo[segment]
        let at = across[vertex] + (side == 0 ? graph.segmentFromOffset[segment] : graph.segmentToOffset[segment])
        return (at, vertex < graph.nodeCount && nodes[vertex].kind == .node ? free[(1 - side) * graph.vertexCount + vertex] : 0)
    }

    /// The room the neighbours in its rank leave a label or bend: a full gap from a node or between two labels, half of
    /// one between a label and a line that passes it.
    private func room(of vertex: Int, across: [Double]) -> (least: Double, most: Double) {
        let start = graph.rankStart[graph.vertexRank[vertex]]
        let index = start + graph.position[vertex]
        let separation = options.edgeSeparation
        func clearance(_ other: Int) -> Double {
            graph.vertexWidth[other] / 2 + graph.vertexWidth[vertex] / 2
                + (graph.vertexKind[other] == .node ? options.nodeSeparation / 2 + separation / 2
                    : graph.vertexKind[other] == graph.vertexKind[vertex] ? separation : separation / 2)
        }
        let least = index > start ? across[graph.order[index - 1]] + clearance(graph.order[index - 1]) : -Double.infinity
        let most = index + 1 < graph.rankStart[graph.vertexRank[vertex] + 1] ? across[graph.order[index + 1]] - clearance(graph.order[index + 1]) : Double.infinity
        return (least, most)
    }

    /// The place between `least` and `most` in line with one of two ends, the one with fewer ends beside it first (or
    /// the nearer), or else nearest the first choice.
    private func choose(_ at: Double, up: (at: Double, sharing: Int), down: (at: Double, sharing: Int), least: Double, most: Double) -> Double {
        let upFirst = up.sharing != down.sharing ? up.sharing < down.sharing : abs(up.at - at) <= abs(down.at - at)
        let firstChoice = upFirst ? up.at : down.at
        let secondChoice = upFirst ? down.at : up.at
        if firstChoice >= least && firstChoice <= most { return firstChoice }
        if secondChoice >= least && secondChoice <= most { return secondChoice }
        return max(least, min(most, firstChoice))
    }

    func align(_ across: inout [Double], workspace: ReferenceLayeredFlatWorkspace) {
        guard graph.maximumRank > 1 else { return }
        var isDone = workspace.flags(count: graph.vertexCount, repeating: false)
        // One list of an edge's labels and bends, refilled for each edge.
        var chain = workspace.emptyIntegers(capacity: 0)
        for rank in 1..<graph.maximumRank {
            for index in graph.rankStart[rank]..<graph.rankStart[rank + 1] {
                let vertex = graph.order[index]
                if !isPlaced(vertex) || isDone[vertex] { continue }
                alignChain(through: vertex, across: &across, isDone: &isDone, chain: &chain)
            }
        }
        workspace.recycle(consume isDone)
        workspace.recycle(consume chain)
    }

    private func upperSegment(of vertex: Int) -> Int { graph.predecessorSegments[graph.predecessorStart[vertex]] }
    private func lowerSegment(of vertex: Int) -> Int { graph.successorSegments[graph.successorStart[vertex]] }

    /// The edge's labels and bends from its first node to its last, and the room they share: all on one line when there
    /// is one, else each in line with the nearest point above or below that is held in place.
    private func alignChain(through vertex: Int, across: inout [Double], isDone: inout [Bool], chain: inout [Int]) {
        var top = vertex
        while graph.vertexKind[graph.segmentFrom[upperSegment(of: top)]].isPassingPoint { top = graph.segmentFrom[upperSegment(of: top)] }
        var bottom = top
        var least = -Double.infinity
        var most = Double.infinity
        chain.removeAll(keepingCapacity: true)
        var current = top
        while graph.vertexKind[current].isPassingPoint {
            bottom = current
            if isPlaced(current) {
                isDone[current] = true
                chain.append(current)
                let room = room(of: current, across: across)
                least = max(least, room.least)
                most = min(most, room.most)
            }
            current = graph.segmentTo[lowerSegment(of: current)]
        }
        if least <= most {
            let at = choose(across[chain[0]], up: end(of: upperSegment(of: top), side: 0, across: across),
                            down: end(of: lowerSegment(of: bottom), side: 1, across: across), least: least, most: most)
            for passing in chain { across[passing] = at }
            return
        }
        for passing in chain {
            let room = room(of: passing, across: across)
            if room.least > room.most { continue }
            let up = end(of: graph.followed(upperSegment(of: passing), isUpward: true, emptyRanks: emptyRanks), side: 0, across: across)
            let down = end(of: graph.followed(lowerSegment(of: passing), isUpward: false, emptyRanks: emptyRanks), side: 1, across: across)
            across[passing] = choose(across[passing], up: up, down: down, least: room.least, most: room.most)
        }
    }
}
