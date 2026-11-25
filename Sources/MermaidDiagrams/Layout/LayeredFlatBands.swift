/**
 * File: LayeredFlatBands.swift
 * ----------------------------
 * Layer: Core
 * Description: The bands of Pele's layered layout along the flow: each rank's height and the gap under it.
 *
 * Authors: Bahey Shalash
 * Version: 0.5
 * Date: 25/11/2026
 */

/// Where each rank's band starts and ends along the flow, and the gaps between them: a usual gap, a smaller one next to
/// a rank of border ports, one that grows where edges run far across, half a marker's room moved from one side of a
/// rank of labels to the other, and room for the tracks or levels the edges' pieces need.
struct LayeredFlatBands {
    let gapUnder: ScratchSpan<Double>
    let bandTop: ScratchSpan<Double>
    let bandBottom: ScratchSpan<Double>
    /// The rank the pieces leaving each rank arrive at, past ranks of bends only.
    let below: ScratchSpan<Int>
    var pieces: LayeredEdgePieces?
    var trackCount: ScratchSpan<Int>
    /// The ranks between two ranks of nodes, which hold labels and bends only.
    let isBetween: ScratchSpan<Bool>
    let margin: Double
    let leastPitch: Double
    let mostPitch: Double
    var height: Double = 0

    /// The bands of a layout with `options` and `rankStep` (its `step`) and the headings of its ranks of labels
    /// (`labelHeadings`): the layout's own values, handed over one by one so that the layout is not copied whole.
    init(graph: LayeredFlatGraph, across: ScratchSpan<Double>, emptyRanks: ScratchSpan<Bool>?, pieces: LayeredEdgePieces?,
         options: LayeredFlatOptions, rankStep: Int, labelHeadings: ScratchSpan<UInt8>, arena: DiagramScratchArena) {
        let maximumRank = graph.maximumRank
        let step = Double(rankStep)
        self.pieces = pieces
        bandTop = arena.span(count: maximumRank + 1, repeating: 0.0)
        bandBottom = arena.span(count: maximumRank + 1, repeating: 0.0)
        below = arena.span(count: maximumRank + 1, repeating: 0)
        trackCount = arena.span(count: maximumRank + 1, repeating: 0)
        margin = options.runsOnTracks ? LayeredFlatConstants.trackMargin : LayeredFlatConstants.levelMargin
        leastPitch = options.runsOnTracks ? LayeredFlatConstants.trackPitch : LayeredFlatConstants.levelPitch
        mostPitch = options.runsOnTracks ? LayeredFlatConstants.trackSpread : LayeredFlatConstants.levelPitch
        // Ranks that hold only border ports or their pass-through bends need little room of their own.
        let startRanks = Self.holdsOnly(.startPort, rank: 0, graph: graph) ? rankStep : 0
        let endRanks = Self.holdsOnly(.endPort, rank: maximumRank, graph: graph) ? rankStep : 0
        gapUnder = arena.span(count: maximumRank + 1, repeating: 0.0)
        isBetween = arena.span(count: maximumRank + 1, repeating: true)
        let mark = arena.mark()
        // The longest way across that any edge travels in the gap below each rank.
        let run = arena.span(count: maximumRank + 1, repeating: 0.0)
        for segment in 0..<graph.segmentCount {
            let distance = abs(across[graph.segmentFrom[segment]] + graph.segmentFromOffset[segment] - across[graph.segmentTo[segment]] - graph.segmentToOffset[segment])
            run[graph.vertexRank[graph.segmentFrom[segment]]] = max(run[graph.vertexRank[graph.segmentFrom[segment]]], distance)
        }
        for rank in 0..<maximumRank {
            let usual = (rank < startRanks || rank >= maximumRank - endRanks ? options.portSeparation : options.rankSeparation) / step
            gapUnder[rank] = pieces != nil ? usual
                : max(usual, min(LayeredFlatConstants.maximumGapFactor * options.rankSeparation / step, run[rank] * LayeredFlatConstants.minimumSlope))
        }
        arena.release(to: mark)
        for node in 0..<graph.nodeCount { isBetween[graph.vertexRank[node]] = false }
        moveHeadRoom(headings: labelHeadings, options: options)
        if pieces != nil { growForPieces(options: options, emptyRanks: emptyRanks, arena: arena) }
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
    private func moveHeadRoom(headings: ScratchSpan<UInt8>, options: LayeredFlatOptions) {
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
    private mutating func growForPieces(options: LayeredFlatOptions, emptyRanks: ScratchSpan<Bool>?, arena: DiagramScratchArena) {
        guard var pieces = pieces.take() else { return }
        let maximumRank = gapUnder.count - 1
        let room = roomBelow(emptyRanks: emptyRanks, arena: arena)
        let isWide = arena.span(count: pieces.count, repeating: false)
        for piece in 0..<pieces.count {
            isWide[piece] = abs(pieces.from[piece] - pieces.to[piece]) > LayeredFlatConstants.levelWideFactor * room[pieces.rank[piece]]
        }
        pieces.isWide = isWide
        // Only a piece that runs across its gap takes a track or a level: where none does, no track is given and no gap
        // grows, as the tracks would find.
        var runsAcross = false
        for piece in 0..<pieces.count where abs(pieces.from[piece] - pieces.to[piece]) >= LayeredFlatConstants.inLine {
            runsAcross = true
            break
        }
        if !runsAcross {
            pieces.track = arena.span(count: pieces.count, repeating: -1)
            pieces.levels = arena.span(count: pieces.count, repeating: 0)
            self.pieces = pieces
            return
        }
        let tracks = LayeredFlatTracks(pieces: pieces, isCurved: !options.runsOnTracks, room: room, rankCount: maximumRank + 1, arena: arena)
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

    /// The room the pieces leaving each rank have, down to the next rank that holds more than bends, which `below`
    /// records; in a span of the arena.
    private func roomBelow(emptyRanks: ScratchSpan<Bool>?, arena: DiagramScratchArena) -> ScratchSpan<Double> {
        let maximumRank = gapUnder.count - 1
        let room = arena.span(count: maximumRank + 1, repeating: 0.0)
        for rank in 0..<maximumRank where !(emptyRanks?[rank] ?? false) {
            var next = rank + 1
            room[rank] = gapUnder[rank]
            while next < maximumRank && (emptyRanks?[next] ?? false) {
                room[rank] += gapUnder[next]
                next += 1
            }
            below[rank] = next
        }
        return room
    }

    /// Each rank's band as tall as its tallest vertex (`vertexHeight`), one after the other with their gaps.
    mutating func size(graph: LayeredFlatGraph, vertexHeight: ScratchSpan<Double>) {
        var along: Double = 0
        for rank in 0...graph.maximumRank {
            var tallest: Double = 0
            for index in graph.rankStart[rank]..<graph.rankStart[rank + 1] { tallest = max(tallest, vertexHeight[graph.order[index]]) }
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
