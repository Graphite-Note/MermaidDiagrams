/**
 * File: LayeredFlatTrackLaying.swift
 * ----------------------------------
 * Layer: Core
 * Description: Lays the pieces of one gap of Pele's layered layout on tracks, and finds the curves that need levels.
 *
 * Authors: Bahey Shalash
 * Version: 0.5
 * Date: 25/11/2026
 */

extension LayeredFlatTracks {
    /// Gives the pieces of one gap their tracks, each the number its group takes, counting from the group's first in
    /// curves; returns the number of tracks. The pieces reaching furthest go first, so that those of one fan nest: `list`
    /// is sorted so in place.
    func lay(_ list: ScratchSpan<Int>) -> Int {
        // No piece takes no track; one piece takes the first, a group of its own one track high.
        if list.isEmpty { return 0 }
        if list.count == 1 {
            pieces.track[list[0]] = 0
            pieces.levels[list[0]] = 1
            return 1
        }
        let mark = arena.mark()
        defer { arena.release(to: mark) }
        let low = low, high = high
        list.sortStably(in: arena) { first, second in
            let reach = (high[second] - low[second]) - (high[first] - low[first])
            if reach != 0 { return reach < 0 }
            return (low[first] != low[second] ? low[first] - low[second] : Double(first - second)) < 0
        }
        let count = list.count
        var groups = LayeredSpanUnionFind(count: count, arena: arena)
        let rows: Int
        if count <= LayeredFlatConstants.maximumWeighedPieces {
            rows = layWeighed(list, groups: &groups)
        } else {
            let sequence: ScratchSpan<Int> = arena.uninitializedSpan(count: count)
            for index in 0..<count { sequence[index] = index }
            rows = placeOnTracks(list, sequence: sequence)
        }
        writeLevels(of: list, groups: &groups, rows: rows)
        return rows
    }

    /// The tracks of a gap few enough to weigh which piece goes above which; returns the number of tracks.
    private func layWeighed(_ list: ScratchSpan<Int>, groups: inout LayeredSpanUnionFind) -> Int {
        let pairs = nearPairs(list).elements
        // Each pair that clashes is a link both ways, in the order of the pairs.
        var keys = arena.list(capacity: pairs.count, of: Int.self)
        var values = arena.list(capacity: pairs.count, of: Int.self)
        for pair in stride(from: 0, to: pairs.count, by: 2) where clash(list[pairs[pair]], list[pairs[pair + 1]]) {
            keys.append(pairs[pair])
            values.append(pairs[pair + 1])
            keys.append(pairs[pair + 1])
            values.append(pairs[pair])
        }
        let clashes = LayeredLinkLists(count: list.count, keys: keys.elements, values: values.elements, arena: arena)
        var sequence = arena.list(capacity: list.count, of: Int.self)
        let above = weighedSequence(list, pairs: pairs, groups: &groups, into: &sequence)
        return placeOnWeighedTracks(list, sequence: sequence.elements, above: above, clashes: clashes)
    }

    /// Each piece's group's number of tracks, and in curves each track counted from its group's first.
    private func writeLevels(of list: ScratchSpan<Int>, groups: inout LayeredSpanUnionFind, rows: Int) {
        let count = list.count
        let firstTrack = arena.span(count: count, repeating: rows)
        let lastTrack = arena.span(count: count, repeating: -1)
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
    }

    /// Which pieces should be above which, so that they cross less, the pieces that could meet joined into groups, and
    /// the order that follows as many of those wishes as it can, written to `sequence`. Returns, for each piece, those
    /// that should be above it.
    private func weighedSequence(_ list: ScratchSpan<Int>, pairs: ScratchSpan<Int>, groups: inout LayeredSpanUnionFind,
                                 into sequence: inout ScratchList<Int>) -> LayeredLinkLists {
        // Each wish as a piece that should be below and the one that should be above it, in the order of the pairs.
        var lowerPieces = arena.list(capacity: pairs.count / 2, of: Int.self)
        var upperPieces = arena.list(capacity: pairs.count / 2, of: Int.self)
        let waiting = arena.span(count: list.count, repeating: 0)
        for pair in stride(from: 0, to: pairs.count, by: 2) {
            let first = pairs[pair], second = pairs[pair + 1]
            if !meet(list[first], list[second]) { continue }
            groups.join(first, into: second)
            let firstAbove = crossings(list[first], list[second])
            let secondAbove = crossings(list[second], list[first])
            if firstAbove == secondAbove { continue }
            lowerPieces.append(firstAbove < secondAbove ? second : first)
            upperPieces.append(firstAbove < secondAbove ? first : second)
            waiting[firstAbove < secondAbove ? second : first] += 1
        }
        let above = LayeredLinkLists(count: list.count, keys: lowerPieces.elements, values: upperPieces.elements, arena: arena)
        let after = LayeredLinkLists(count: list.count, keys: upperPieces.elements, values: lowerPieces.elements, arena: arena)
        Self.sequence(count: list.count, waiting: waiting, after: after, into: &sequence, arena: arena)
        return above
    }

    /// The order that follows as many of the wishes as it can: a piece once all that should be above it are placed, and
    /// when none is free, the one with the fewest still waiting.
    private static func sequence(count: Int, waiting: ScratchSpan<Int>, after: LayeredLinkLists, into sequence: inout ScratchList<Int>,
                                 arena: DiagramScratchArena) {
        let isPlaced = arena.span(count: count, repeating: false)
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
    }

    /// Each piece of a weighed gap on the first track below those that should be above it that no piece it clashes
    /// with has taken. Every piece starts without a track, so the piece placed k-th takes a track no higher than k: the
    /// tracks taken are marked in one span of flags as long as the list, instead of a set.
    private func placeOnWeighedTracks(_ list: ScratchSpan<Int>, sequence: ScratchSpan<Int>, above: LayeredLinkLists,
                                               clashes: LayeredLinkLists) -> Int {
        let isTaken = arena.span(count: list.count + 1, repeating: false)
        var rows = 0
        for at in sequence {
            let piece = list[at]
            var track = 0
            for index in above[at] where pieces.track[list[index]] >= track { track = pieces.track[list[index]] + 1 }
            for index in clashes[at] where isTaken.indices.contains(pieces.track[list[index]]) { isTaken[pieces.track[list[index]]] = true }
            while track < isTaken.count && isTaken[track] { track += 1 }
            for index in clashes[at] where isTaken.indices.contains(pieces.track[list[index]]) { isTaken[pieces.track[list[index]]] = false }
            pieces.track[piece] = track
            rows = max(rows, track + 1)
        }
        return rows
    }

    /// Each piece of a gap of too many pieces to weigh on the first track where it clashes with none already there.
    private func placeOnTracks(_ list: ScratchSpan<Int>, sequence: ScratchSpan<Int>) -> Int {
        // Only gaps of more than `maximumWeighedPieces` pieces come here: the tracks' own lists are arrays.
        var onTrack: [[Int]] = []
        var rows = 0
        for at in sequence {
            let piece = list[at]
            var track = 0
            while track < onTrack.count && onTrack[track].contains(where: { other in clash(piece, other) }) { track += 1 }
            while onTrack.count <= track { onTrack.append([]) }
            onTrack[track].append(piece)
            pieces.track[piece] = track
            rows = max(rows, track + 1)
        }
        return rows
    }

    /// The levels of one gap of curves: the pieces that turn onto levels, with the short pieces that could cross them,
    /// unless the curves mostly cross each other, when the gap grows instead.
    func assignLevels(rank: Int, all: ScratchSpan<Int>) {
        // A lone piece has none to be told apart from: it turns onto no level and leaves the gap as it is.
        if all.count < 2 { return }
        let mark = arena.mark()
        defer {
            for piece in all {
                isLevel[piece] = false
                isBeside[piece] = false
            }
            arena.release(to: mark)
        }
        let pairs = nearPairs(all).elements
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
        var members = arena.list(capacity: all.count, of: Int.self)
        for piece in all where isLevel[piece] || (!pieces.isWide[piece] && isBeside[piece]) { members.append(piece) }
        _ = lay(members.elements)
        var most: Int?
        for piece in members { most = max(most ?? pieces.levels[piece], pieces.levels[piece]) }
        trackCount[rank] = most ?? 0
    }

    /// Marks in `isLevel` the pieces that turn onto levels: first those that run far across and have another such
    /// piece to be told apart from, then any two that would pass too near each other as plain curves. Returns how many.
    private func markLevelPieces(rank: Int, all: ScratchSpan<Int>, pairs: ScratchSpan<Int>) -> Int {
        var far = arena.list(capacity: all.count, of: Int.self)
        for piece in all where pieces.isWide[piece] { far.append(piece) }
        _ = lay(far.elements)
        var levelCount = 0
        let isLevel = isLevel
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

/// `LayeredUnionFind` with its parents in a span of a scratch arena.
struct LayeredSpanUnionFind {
    private let parent: ScratchSpan<Int>

    /// The groups of `count` indices, each its own.
    init(count: Int, arena: DiagramScratchArena) {
        parent = arena.uninitializedSpan(count: count)
        for index in 0..<count { parent[index] = index }
    }

    func find(_ index: Int) -> Int {
        var index = index
        while parent[index] != index {
            parent[index] = parent[parent[index]]
            index = parent[index]
        }
        return index
    }

    /// Puts the group of `first` under the root of `second`'s.
    func join(_ first: Int, into second: Int) {
        let firstRoot = find(first)
        let secondRoot = find(second)
        parent[firstRoot] = secondRoot
    }
}
