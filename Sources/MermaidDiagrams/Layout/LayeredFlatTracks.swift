/**
 * File: LayeredFlatTracks.swift
 * -----------------------------
 * Layer: Core
 * Description: Gives the pieces of edges that cross one gap of Pele's layered layout their tracks or levels.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 23/11/2026
 */

/// The pieces of edges that each cross one gap (Pele's `Pieces`): where they leave the rank above and reach the one
/// below, the rank above, the bend they end at (-1 at the edge's last node), their track (-1 for none), how many
/// tracks their group takes (0 for none), and whether they run far across.
struct LayeredEdgePieces {
    var from: [Double] = []
    var to: [Double] = []
    var rank: [Int] = []
    var lower: [Int] = []
    var track: [Int] = []
    var levels: [Int] = []
    var isWide: [Bool] = []

    var count: Int { from.count }
}

/// Pele's `assignTracks` (layout/layered.ts): two pieces of a gap share a track only where they cannot be mistaken
/// for each other, and which of two goes above is whichever makes them cross less. With curves, only the pieces that
/// would run along or too near another turn onto levels; a gap whose curves mostly cross gets taller instead.
struct LayeredFlatTracks {
    var pieces: LayeredEdgePieces
    let isCurved: Bool
    let room: [Double]
    var trackCount: [Int]
    var tallGap: [Double]
    /// Each piece's least and greatest position across.
    let low: [Double]
    let high: [Double]

    init(pieces: LayeredEdgePieces, isCurved: Bool, room: [Double], rankCount: Int) {
        self.pieces = pieces
        self.isCurved = isCurved
        self.room = room
        trackCount = [Int](repeating: 0, count: rankCount)
        tallGap = [Double](repeating: 0, count: rankCount)
        low = pieces.from.indices.map { piece in min(pieces.from[piece], pieces.to[piece]) }
        high = pieces.from.indices.map { piece in max(pieces.from[piece], pieces.to[piece]) }
        self.pieces.track = [Int](repeating: -1, count: pieces.count)
        self.pieces.levels = [Int](repeating: 0, count: pieces.count)
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

    /// Pairs of list indices, smaller first, that may meet or clash: those whose spans across come within reach.
    func nearPairs(_ list: [Int]) -> [Int] {
        var byLow = Array(list.indices)
        byLow.sortStably { first, second in low[list[first]] - low[list[second]] }
        var pairs: [Int] = []
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
        var byRank: [Int: [Int]] = [:]
        var rankOrder: [Int] = []
        for piece in 0..<pieces.count where abs(pieces.from[piece] - pieces.to[piece]) >= LayeredFlatConstants.inLine {
            if byRank[pieces.rank[piece]] == nil { rankOrder.append(pieces.rank[piece]) }
            byRank[pieces.rank[piece], default: []].append(piece)
        }
        for rank in rankOrder {
            let all = byRank[rank] ?? []
            if !isCurved {
                var list = all
                trackCount[rank] = lay(&list)
                continue
            }
            if all.count > LayeredFlatConstants.maximumWeighedPieces { continue }
            assignLevels(rank: rank, all: all)
        }
    }
}
