/**
 * File: LayeredFlatBands.swift
 * ----------------------------
 * Layer: Core
 * Description: The bands of Pele's layered layout along the flow: each rank's height and the gap under it.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 23/11/2026
 */

/// Where each rank's band starts and ends along the flow, and the gaps between them: a usual gap, a smaller one next to
/// a rank of border ports, one that grows where edges run far across, half a marker's room moved from one side of a
/// rank of labels to the other, and room for the tracks or levels the edges' pieces need.
struct LayeredFlatBands {
    var gapUnder: [Double]
    var bandTop: [Double]
    var bandBottom: [Double]
    /// The rank the pieces leaving each rank arrive at, past ranks of bends only.
    var below: [Int]
    var pieces: LayeredEdgePieces?
    var trackCount: [Int]
    /// The ranks between two ranks of nodes, which hold labels and bends only.
    var isBetween: [Bool]
    let margin: Double
    let leastPitch: Double
    let mostPitch: Double
    var height: Double = 0

    init(layout: LayeredFlatLayout, graph: LayeredFlatGraph, across: [Double], emptyRanks: [Bool]?, pieces: LayeredEdgePieces?) {
        let maximumRank = graph.maximumRank
        let options = layout.options
        let step = Double(layout.step)
        self.pieces = pieces
        bandTop = [Double](repeating: 0, count: maximumRank + 1)
        bandBottom = [Double](repeating: 0, count: maximumRank + 1)
        below = [Int](repeating: 0, count: maximumRank + 1)
        trackCount = [Int](repeating: 0, count: maximumRank + 1)
        margin = options.runsOnTracks ? LayeredFlatConstants.trackMargin : LayeredFlatConstants.levelMargin
        leastPitch = options.runsOnTracks ? LayeredFlatConstants.trackPitch : LayeredFlatConstants.levelPitch
        mostPitch = options.runsOnTracks ? LayeredFlatConstants.trackSpread : LayeredFlatConstants.levelPitch
        // Ranks that hold only border ports or their pass-through bends need little room of their own.
        let startRanks = Self.holdsOnly(.startPort, rank: 0, graph: graph) ? layout.step : 0
        let endRanks = Self.holdsOnly(.endPort, rank: maximumRank, graph: graph) ? layout.step : 0
        // The longest way across that any edge travels in the gap below each rank.
        var run = [Double](repeating: 0, count: maximumRank + 1)
        for segment in 0..<graph.segmentCount {
            let distance = abs(across[graph.segmentFrom[segment]] + graph.segmentFromOffset[segment] - across[graph.segmentTo[segment]] - graph.segmentToOffset[segment])
            run[graph.vertexRank[graph.segmentFrom[segment]]] = max(run[graph.vertexRank[graph.segmentFrom[segment]]], distance)
        }
        gapUnder = [Double](repeating: 0, count: maximumRank + 1)
        for rank in 0..<maximumRank {
            let usual = (rank < startRanks || rank >= maximumRank - endRanks ? options.portSeparation : options.rankSeparation) / step
            gapUnder[rank] = pieces != nil ? usual
                : max(usual, min(LayeredFlatConstants.maximumGapFactor * options.rankSeparation / step, run[rank] * LayeredFlatConstants.minimumSlope))
        }
        isBetween = [Bool](repeating: true, count: maximumRank + 1)
        for node in 0..<graph.nodeCount { isBetween[graph.vertexRank[node]] = false }
        moveHeadRoom(headings: layout.labelHeadings, options: options)
        if pieces != nil { growForPieces(options: options, emptyRanks: emptyRanks) }
    }

    private static func holdsOnly(_ kind: LayeredVertexKind, rank: Int, graph: LayeredFlatGraph) -> Bool {
        var found = false
        for index in graph.rankStart[rank]..<graph.rankStart[rank + 1] {
            let vertexKind = graph.vertexKind[graph.order[index]]
            if vertexKind == kind { found = true } else if vertexKind != .bend { return false }
        }
        return found
    }

    /// A rank of labels whose edges all head one way sits half a marker's room nearer their tails, so that each label is
    /// midway along the line that shows.
    private mutating func moveHeadRoom(headings: [UInt8], options: LayeredFlatOptions) {
        let maximumRank = gapUnder.count - 1
        guard maximumRank > 1 else { return }
        for rank in 1..<maximumRank {
            if options.runsOnTracks || !isBetween[rank] || (headings[rank] != 1 && headings[rank] != 2) { continue }
            let shift = min(options.headRoom / 2, gapUnder[headings[rank] == 1 ? rank - 1 : rank] / 2)
            gapUnder[rank - 1] += headings[rank] == 1 ? -shift : shift
            gapUnder[rank] += headings[rank] == 1 ? shift : -shift
        }
    }

    /// The gaps grown to hold their tracks or levels, kept `margin` from the ranks and `leastPitch` apart, or to the
    /// height that lets crossing curves cross at a clear angle.
    private mutating func growForPieces(options: LayeredFlatOptions, emptyRanks: [Bool]?) {
        guard var pieces else { return }
        let maximumRank = gapUnder.count - 1
        var room = [Double](repeating: 0, count: maximumRank + 1)
        for rank in 0..<maximumRank where !(emptyRanks?[rank] ?? false) {
            var next = rank + 1
            room[rank] = gapUnder[rank]
            while next < maximumRank && (emptyRanks?[next] ?? false) {
                room[rank] += gapUnder[next]
                next += 1
            }
            below[rank] = next
        }
        pieces.isWide = (0..<pieces.count).map { piece in abs(pieces.from[piece] - pieces.to[piece]) > LayeredFlatConstants.levelWideFactor * room[pieces.rank[piece]] }
        var tracks = LayeredFlatTracks(pieces: pieces, isCurved: !options.runsOnTracks, room: room, rankCount: maximumRank + 1)
        tracks.assign()
        self.pieces = tracks.pieces
        trackCount = tracks.trackCount
        for rank in 0..<maximumRank {
            if trackCount[rank] > 0 {
                gapUnder[rank] += max(0, 2 * margin + Double(trackCount[rank] - 1) * leastPitch - room[rank])
            } else if tracks.tallGap[rank] > 0 {
                gapUnder[rank] += max(0, min(LayeredFlatConstants.maximumGapFactor * options.rankSeparation, tracks.tallGap[rank]) - room[rank])
            }
        }
    }

    /// Each rank's band as tall as its tallest vertex, one after the other with their gaps.
    mutating func size(layout: LayeredFlatLayout, graph: LayeredFlatGraph) {
        var along: Double = 0
        for rank in 0...graph.maximumRank {
            var tallest: Double = 0
            for index in graph.rankStart[rank]..<graph.rankStart[rank + 1] { tallest = max(tallest, layout.vertexHeight[graph.order[index]]) }
            bandTop[rank] = along
            bandBottom[rank] = along + tallest
            along += tallest + gapUnder[rank]
        }
        height = along
    }

    /// Where a piece runs across its gap, or would on another track of its group: the tracks sit in the middle of the
    /// gap, the first at the top.
    func trackAlong(_ piece: Int, onTrack: Int? = nil, runsOnTracks: Bool) -> Double {
        guard let pieces else { return 0 }
        let rank = pieces.rank[piece]
        let top = bandBottom[rank]
        let bottom = bandTop[below[rank]]
        let count = runsOnTracks ? trackCount[rank] : pieces.levels[piece]
        let pitch = count > 1 ? min(mostPitch, (bottom - top - 2 * margin) / Double(count - 1)) : 0
        return (top + bottom) / 2 + (Double(onTrack ?? pieces.track[piece]) - Double(count - 1) / 2) * pitch
    }

    /// The part of its rank that an edge runs straight through at a bend: a bare bend beside labels keeps to the middle
    /// half, which leaves the curves either side more room and keeps them clear of the labels' corners.
    func inset(of vertex: Int, graph: LayeredFlatGraph, runsOnTracks: Bool) -> Double {
        let rank = graph.vertexRank[vertex]
        return graph.vertexKind[vertex] == .bend && isBetween[rank] && !runsOnTracks ? (bandBottom[rank] - bandTop[rank]) / 4 : 0
    }
}
