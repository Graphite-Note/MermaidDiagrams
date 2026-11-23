/**
 * File: LayeredFlatTrackLaying.swift
 * ----------------------------------
 * Layer: Core
 * Description: Lays the pieces of one gap of Pele's layered layout on tracks, and finds the curves that need levels.
 *
 * Authors: Bahey Shalash
 * Version: 0.2
 * Date: 23/11/2026
 */

extension LayeredFlatTracks {
    /// Gives the pieces of one gap their tracks, each the number its group takes, counting from the group's first in
    /// curves; returns the number of tracks. The pieces reaching furthest go first, so that those of one fan nest.
    mutating func lay(_ list: inout [Int]) -> Int {
        let low = low, high = high
        list.sortStably { first, second in
            let reach = (high[second] - low[second]) - (high[first] - low[first])
            if reach != 0 { return reach }
            return low[first] != low[second] ? low[first] - low[second] : Double(first - second)
        }
        let count = list.count
        var groups = LayeredUnionFind(count: count)
        let isWeighed = count <= LayeredFlatConstants.maximumWeighedPieces
        let pairs = isWeighed ? nearPairs(list) : []
        var clashes = [[Int]](repeating: [], count: isWeighed ? count : 0)
        var above = [[Int]](repeating: [], count: isWeighed ? count : 0)
        var sequence = Array(0..<count)
        if isWeighed {
            for pair in stride(from: 0, to: pairs.count, by: 2) where clash(list[pairs[pair]], list[pairs[pair + 1]]) {
                clashes[pairs[pair]].append(pairs[pair + 1])
                clashes[pairs[pair + 1]].append(pairs[pair])
            }
            sequence = weighedSequence(list, pairs: pairs, groups: &groups, above: &above)
        }
        let rows = placeOnTracks(list, sequence: sequence, above: above, clashes: clashes, isWeighed: isWeighed)
        var firstTrack = [Int](repeating: rows, count: count)
        var lastTrack = [Int](repeating: -1, count: count)
        for index in 0..<count {
            let root = groups.find(index)
            firstTrack[root] = min(firstTrack[root], pieces.track[list[index]])
            lastTrack[root] = max(lastTrack[root], pieces.track[list[index]])
        }
        for index in 0..<count {
            let root = groups.find(index)
            pieces.levels[list[index]] = lastTrack[root] - firstTrack[root] + 1
            if isCurved { pieces.track[list[index]] -= firstTrack[root] }
        }
        return rows
    }

    /// Which pieces should be above which, so that they cross less, the pieces that could meet joined into groups, and
    /// the order that follows as many of those wishes as it can.
    private func weighedSequence(_ list: [Int], pairs: [Int], groups: inout LayeredUnionFind, above: inout [[Int]]) -> [Int] {
        var after = [[Int]](repeating: [], count: list.count)
        var waiting = [Int](repeating: 0, count: list.count)
        for pair in stride(from: 0, to: pairs.count, by: 2) {
            let first = pairs[pair], second = pairs[pair + 1]
            if !meet(list[first], list[second]) { continue }
            groups.join(first, into: second)
            let firstAbove = crossings(list[first], list[second])
            let secondAbove = crossings(list[second], list[first])
            if firstAbove == secondAbove { continue }
            let upper = firstAbove < secondAbove ? first : second
            let lowerPiece = firstAbove < secondAbove ? second : first
            above[lowerPiece].append(upper)
            after[upper].append(lowerPiece)
            waiting[lowerPiece] += 1
        }
        return Self.sequence(count: list.count, waiting: waiting, after: after)
    }

    /// The order that follows as many of the wishes as it can: a piece once all that should be above it are placed, and
    /// when none is free, the one with the fewest still waiting.
    private static func sequence(count: Int, waiting: [Int], after: [[Int]]) -> [Int] {
        var waiting = waiting
        var isPlaced = [Bool](repeating: false, count: count)
        var sequence: [Int] = []
        for _ in 0..<count {
            var pick = -1
            for index in 0..<count where !isPlaced[index] {
                if pick < 0 || waiting[index] < waiting[pick] { pick = index }
                if waiting[index] == 0 { break }
            }
            isPlaced[pick] = true
            sequence.append(pick)
            for next in after[pick] { waiting[next] -= 1 }
        }
        return sequence
    }

    private mutating func placeOnTracks(_ list: [Int], sequence: [Int], above: [[Int]], clashes: [[Int]], isWeighed: Bool) -> Int {
        var taken = Set<Int>()
        var onTrack: [[Int]] = []
        var rows = 0
        for at in sequence {
            let piece = list[at]
            var track = 0
            for index in (isWeighed ? above[at] : []) where pieces.track[list[index]] >= track { track = pieces.track[list[index]] + 1 }
            if isWeighed {
                taken.removeAll(keepingCapacity: true)
                for index in clashes[at] { taken.insert(pieces.track[list[index]]) }
                while taken.contains(track) { track += 1 }
            } else {
                while track < onTrack.count && onTrack[track].contains(where: { other in clash(piece, other) }) { track += 1 }
                while onTrack.count <= track { onTrack.append([]) }
                onTrack[track].append(piece)
            }
            pieces.track[piece] = track
            rows = max(rows, track + 1)
        }
        return rows
    }

    /// The levels of one gap of curves: the pieces that turn onto levels, with the short pieces that could cross them,
    /// unless the curves mostly cross each other, when the gap grows instead.
    mutating func assignLevels(rank: Int, all: [Int]) {
        let pairs = nearPairs(all)
        defer {
            for piece in all {
                isLevel[piece] = false
                isBeside[piece] = false
            }
        }
        if markLevelPieces(rank: rank, all: all, pairs: pairs) == 0 { return }
        var crossing = 0
        var alongside = 0
        for pair in stride(from: 0, to: pairs.count, by: 2) {
            let first = all[pairs[pair]], second = all[pairs[pair + 1]]
            if isLevel[first] && isLevel[second] {
                if !overlap(first, second) { continue }
                if runsRight(first) != runsRight(second) { crossing += 1 } else if !areMates(first, second) { alongside += 1 }
            } else if (isLevel[first] || isLevel[second]) && meet(first, second) {
                isBeside[first] = true
                isBeside[second] = true
            }
        }
        if crossing > alongside {
            for piece in all where (high[piece] - low[piece]) * LayeredFlatConstants.crossedSlope > tallGap[rank] {
                tallGap[rank] = (high[piece] - low[piece]) * LayeredFlatConstants.crossedSlope
            }
            return
        }
        var members = all.filter { piece in isLevel[piece] || (!pieces.isWide[piece] && isBeside[piece]) }
        _ = lay(&members)
        trackCount[rank] = members.map { piece in pieces.levels[piece] }.max() ?? 0
    }

    /// Marks in `isLevel` the pieces that turn onto levels: first those that run far across and have another such
    /// piece to be told apart from, then any two that would pass too near each other as plain curves. Returns how many.
    private mutating func markLevelPieces(rank: Int, all: [Int], pairs: [Int]) -> Int {
        var far = all.filter { piece in pieces.isWide[piece] }
        _ = lay(&far)
        var levelCount = 0
        func mark(_ piece: Int) {
            if isLevel[piece] { return }
            isLevel[piece] = true
            levelCount += 1
        }
        for piece in far where pieces.levels[piece] > 1 { mark(piece) }
        for pair in stride(from: 0, to: pairs.count, by: 2) {
            let first = all[pairs[pair]], second = all[pairs[pair + 1]]
            if (isLevel[first] && isLevel[second]) || !clash(first, second) || runsRight(first) != runsRight(second) { continue }
            let limit = pieces.isWide[first] || pieces.isWide[second] ? LayeredFlatConstants.levelClear : LayeredFlatConstants.levelTouch
            if passNear(first, second, height: room[rank], limit: limit) {
                mark(first)
                mark(second)
            }
        }
        for piece in far {
            pieces.track[piece] = -1
            pieces.levels[piece] = 0
        }
        return levelCount
    }

    private func runsRight(_ piece: Int) -> Bool { pieces.from[piece] < pieces.to[piece] }
}

/// Groups joined by a union of their roots, with path halving (Pele's `group` and `find` in `assignTracks`).
struct LayeredUnionFind {
    private var parent: [Int]

    init(count: Int) { parent = Array(0..<count) }

    mutating func find(_ index: Int) -> Int {
        var index = index
        while parent[index] != index {
            parent[index] = parent[parent[index]]
            index = parent[index]
        }
        return index
    }

    /// Puts the group of `first` under the root of `second`'s.
    mutating func join(_ first: Int, into second: Int) {
        let firstRoot = find(first)
        let secondRoot = find(second)
        parent[firstRoot] = secondRoot
    }
}
