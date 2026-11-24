/**
 * File: LayeredFlatTracks.swift
 * -----------------------------
 * Layer: Core
 * Description: Gives the pieces of edges that cross one gap of Pele's layered layout their tracks or levels.
 *
 * Authors: Bahey Shalash
 * Version: 0.4
 * Date: 24/11/2026
 */

/// The pieces of edges that each cross one gap (Pele's `Pieces`): where they leave the rank above and reach the one
/// below, the rank above, the bend they end at (-1 at the edge's last node), their track (-1 for none), how many
/// tracks their group takes (0 for none), and whether they run far across.
struct LayeredEdgePieces {
    var from: ScratchList<Double>
    var to: ScratchList<Double>
    var rank: ScratchList<Int>
    var lower: ScratchList<Int>
    var track = ScratchSpan<Int>.empty
    var levels = ScratchSpan<Int>.empty
    var isWide = ScratchSpan<Bool>.empty

    var count: Int { from.count }
}

/// Pele's `assignTracks` (layout/layered.ts): two pieces of a gap share a track only where they cannot be mistaken
/// for each other, and which of two goes above is whichever makes them cross less. With curves, only the pieces that
/// would run along or too near another turn onto levels; a gap whose curves mostly cross gets taller instead.
struct LayeredFlatTracks {
    var pieces: LayeredEdgePieces
    let isCurved: Bool
    let room: ScratchSpan<Double>
    let trackCount: ScratchSpan<Int>
    let tallGap: ScratchSpan<Double>
    /// Each piece's least and greatest position across.
    let low: ScratchSpan<Double>
    let high: ScratchSpan<Double>
    /// The pieces of the gap being given levels that turn onto levels, and those beside them; cleared after each gap.
    let isLevel: ScratchSpan<Bool>
    let isBeside: ScratchSpan<Bool>
    let arena: DiagramScratchArena

    /// The pieces' tracks and levels, the track counts and the tall gaps are taken from `arena` first, for the caller to
    /// read once the tracks are assigned.
    init(pieces: LayeredEdgePieces, isCurved: Bool, room: ScratchSpan<Double>, rankCount: Int, arena: DiagramScratchArena) {
        self.pieces = pieces
        self.isCurved = isCurved
        self.room = room
        self.arena = arena
        trackCount = arena.span(count: rankCount, repeating: 0)
        tallGap = arena.span(count: rankCount, repeating: 0.0)
        self.pieces.track = arena.span(count: pieces.count, repeating: -1)
        self.pieces.levels = arena.span(count: pieces.count, repeating: 0)
        let low: ScratchSpan<Double> = arena.uninitializedSpan(count: pieces.count)
        let high: ScratchSpan<Double> = arena.uninitializedSpan(count: pieces.count)
        for piece in 0..<pieces.count {
            low[piece] = min(pieces.from[piece], pieces.to[piece])
            high[piece] = max(pieces.from[piece], pieces.to[piece])
        }
        self.low = low
        self.high = high
        isLevel = arena.span(count: isCurved ? pieces.count : 0, repeating: false)
        isBeside = arena.span(count: isCurved ? pieces.count : 0, repeating: false)
    }

    func isWithin(_ at: Double, _ piece: Int) -> Int {
        at >= low[piece] - LayeredFlatConstants.inLine && at <= high[piece] + LayeredFlatConstants.inLine ? 1 : 0
    }

    func areMates(_ first: Int, _ second: Int) -> Bool {
        abs(pieces.from[first] - pieces.from[second]) < LayeredFlatConstants.inLine || abs(pieces.to[first] - pieces.to[second]) < LayeredFlatConstants.inLine
    }

    func overlap(_ first: Int, _ second: Int) -> Bool {
        low[first] < high[second] - LayeredFlatConstants.inLine && low[second] < high[first] - LayeredFlatConstants.inLine
    }

    /// Whether two pieces need tracks of their own.
    func clash(_ first: Int, _ second: Int) -> Bool { overlap(first, second) && !areMates(first, second) }

    /// Whether one of two pieces could cross the other, depending on which is above.
    func meet(_ first: Int, _ second: Int) -> Bool {
        overlap(first, second)
            || isWithin(pieces.to[first], second) + isWithin(pieces.from[second], first) + isWithin(pieces.to[second], first) + isWithin(pieces.from[first], second) > 0
    }

    /// How often two pieces cross with `first` on the higher track.
    func crossings(_ first: Int, _ second: Int) -> Int { isWithin(pieces.to[first], second) + isWithin(pieces.from[second], first) }

    /// Pairs of list indices, smaller first, that may meet or clash: those whose spans across come within reach. In a
    /// list of the arena.
    func nearPairs(_ list: ScratchSpan<Int>) -> ScratchList<Int> {
        // The pairs grow as they are found, so nothing taken before them is given back here.
        var pairs = arena.list(capacity: 2 * list.count, of: Int.self)
        let byLow: ScratchSpan<Int> = arena.uninitializedSpan(count: list.count)
        for index in list.indices { byLow[index] = index }
        let low = low, high = high
        byLow.sortStably(in: arena) { first, second in low[list[first]] - low[list[second]] < 0 }
        for position in byLow.indices {
            let first = byLow[position]
            let reach = high[list[first]] + 4 * LayeredFlatConstants.inLine
            var next = position + 1
            while next < byLow.count && low[list[byLow[next]]] <= reach {
                let second = byLow[next]
                pairs.append(min(first, second))
                pairs.append(max(first, second))
                next += 1
            }
        }
        return pairs
    }

    /// Gives every piece that does not run straight down a track across its gap (or a level), and counts the tracks.
    mutating func assign() {
        let mark = arena.mark()
        defer { arena.release(to: mark) }
        // The pieces of each gap in the order they come, one gap after another, and the gaps in the order their first
        // pieces come.
        let rankCount = trackCount.count
        let rankStart = arena.span(count: rankCount + 1, repeating: 0)
        for piece in 0..<pieces.count where abs(pieces.from[piece] - pieces.to[piece]) >= LayeredFlatConstants.inLine {
            rankStart[pieces.rank[piece] + 1] += 1
        }
        for rank in 0..<rankCount { rankStart[rank + 1] += rankStart[rank] }
        let rankPieces = arena.span(count: rankStart[rankCount], repeating: 0)
        let fill = arena.copy(of: rankStart.part(0..<rankCount))
        var rankOrder = arena.list(capacity: rankCount, of: Int.self)
        for piece in 0..<pieces.count where abs(pieces.from[piece] - pieces.to[piece]) >= LayeredFlatConstants.inLine {
            let rank = pieces.rank[piece]
            if fill[rank] == rankStart[rank] { rankOrder.append(rank) }
            rankPieces[fill[rank]] = piece
            fill[rank] += 1
        }
        var all = arena.list(capacity: rankPieces.count, of: Int.self)
        for rank in rankOrder {
            all.removeAll()
            all.append(contentsOf: rankPieces.part(rankStart[rank]..<rankStart[rank + 1]))
            if !isCurved {
                trackCount[rank] = lay(all.elements)
                continue
            }
            if all.count > LayeredFlatConstants.maximumWeighedPieces { continue }
            assignLevels(rank: rank, all: all.elements)
        }
    }
}
