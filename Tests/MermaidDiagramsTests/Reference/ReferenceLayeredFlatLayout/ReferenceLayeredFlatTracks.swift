/**
 * File: ReferenceLayeredFlatTracks.swift
 * --------------------------------------
 * Layer: Tests
 * Description: The 0.7.0 layered layout kept as the reference the span layout is checked against: gives the pieces of
 *              edges that cross one gap of Pele's layered layout their tracks or levels.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 24/11/2026
 */

@testable import MermaidDiagrams

/// The pieces of edges that each cross one gap (Pele's `Pieces`): where they leave the rank above and reach the one
/// below, the rank above, the bend they end at (-1 at the edge's last node), their track (-1 for none), how many
/// tracks their group takes (0 for none), and whether they run far across.
struct ReferenceLayeredEdgePieces {
    var from: [Double] = []
    var to: [Double] = []
    var rank: [Int] = []
    var lower: [Int] = []
    var track: [Int] = []
    var levels: [Int] = []
    var isWide: [Bool] = []

    var count: Int { from.count }

    /// Gives the lists back to `workspace`.
    consuming func recycle(into workspace: ReferenceLayeredFlatWorkspace) {
        workspace.recycle(from)
        workspace.recycle(to)
        workspace.recycle(rank)
        workspace.recycle(lower)
        workspace.recycle(track)
        workspace.recycle(levels)
        workspace.recycle(isWide)
    }
}

/// Pele's `assignTracks` (layout/layered.ts): two pieces of a gap share a track only where they cannot be mistaken
/// for each other, and which of two goes above is whichever makes them cross less. With curves, only the pieces that
/// would run along or too near another turn onto levels; a gap whose curves mostly cross gets taller instead.
struct ReferenceLayeredFlatTracks {
    var pieces: ReferenceLayeredEdgePieces
    let isCurved: Bool
    let room: [Double]
    var trackCount: [Int]
    var tallGap: [Double]
    /// Each piece's least and greatest position across.
    let low: [Double]
    let high: [Double]
    /// The pieces of the gap being given levels that turn onto levels, and those beside them; cleared after each gap.
    var isLevel: [Bool]
    var isBeside: [Bool]
    let workspace: ReferenceLayeredFlatWorkspace

    init(pieces: ReferenceLayeredEdgePieces, isCurved: Bool, room: [Double], rankCount: Int, workspace: ReferenceLayeredFlatWorkspace) {
        self.pieces = pieces
        self.isCurved = isCurved
        self.room = room
        self.workspace = workspace
        trackCount = workspace.integers(count: rankCount, repeating: 0)
        tallGap = workspace.numbers(count: rankCount, repeating: 0)
        var low = workspace.emptyNumbers(capacity: pieces.count)
        var high = workspace.emptyNumbers(capacity: pieces.count)
        for piece in 0..<pieces.count {
            low.append(min(pieces.from[piece], pieces.to[piece]))
            high.append(max(pieces.from[piece], pieces.to[piece]))
        }
        self.low = low
        self.high = high
        self.pieces.track = workspace.integers(count: pieces.count, repeating: -1)
        self.pieces.levels = workspace.integers(count: pieces.count, repeating: 0)
        isLevel = workspace.flags(count: isCurved ? pieces.count : 0, repeating: false)
        isBeside = workspace.flags(count: isCurved ? pieces.count : 0, repeating: false)
    }

    /// Gives the lists only the tracks' own work reads back to the workspace; the pieces, the track counts and the tall
    /// gaps are the caller's.
    consuming func recycle() {
        workspace.recycle(low)
        workspace.recycle(high)
        workspace.recycle(isLevel)
        workspace.recycle(isBeside)
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
    /// list of the workspace.
    func nearPairs(_ list: [Int]) -> [Int] {
        var byLow = workspace.emptyIntegers(capacity: list.count)
        byLow.append(contentsOf: list.indices)
        var spare = workspace.emptyIntegers(capacity: 0)
        byLow.sortStably(spare: &spare) { first, second in low[list[first]] - low[list[second]] < 0 }
        workspace.recycle(consume spare)
        defer { workspace.recycle(byLow) }
        var pairs = workspace.emptyIntegers(capacity: 0)
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
        // The pieces of each gap in the order they come, one gap after another, and the gaps in the order their first
        // pieces come.
        let rankCount = trackCount.count
        var rankStart = workspace.integers(count: rankCount + 1, repeating: 0)
        for piece in 0..<pieces.count where abs(pieces.from[piece] - pieces.to[piece]) >= LayeredFlatConstants.inLine {
            rankStart[pieces.rank[piece] + 1] += 1
        }
        for rank in 0..<rankCount { rankStart[rank + 1] += rankStart[rank] }
        var rankPieces = workspace.integers(count: rankStart[rankCount], repeating: 0)
        var fill = workspace.emptyIntegers(capacity: rankCount)
        fill.append(contentsOf: rankStart[0..<rankCount])
        var rankOrder = workspace.emptyIntegers(capacity: 0)
        for piece in 0..<pieces.count where abs(pieces.from[piece] - pieces.to[piece]) >= LayeredFlatConstants.inLine {
            let rank = pieces.rank[piece]
            if fill[rank] == rankStart[rank] { rankOrder.append(rank) }
            rankPieces[fill[rank]] = piece
            fill[rank] += 1
        }
        var all = workspace.emptyIntegers(capacity: 0)
        for rank in rankOrder {
            all.removeAll(keepingCapacity: true)
            all.append(contentsOf: rankPieces[rankStart[rank]..<rankStart[rank + 1]])
            if !isCurved {
                trackCount[rank] = lay(&all)
                continue
            }
            if all.count > LayeredFlatConstants.maximumWeighedPieces { continue }
            assignLevels(rank: rank, all: all)
        }
        workspace.recycle(consume rankStart)
        workspace.recycle(consume rankPieces)
        workspace.recycle(consume fill)
        workspace.recycle(consume rankOrder)
        workspace.recycle(consume all)
    }
}
