/**
 * File: LayeredFlatTrackLaying.swift
 * ----------------------------------
 * Layer: Core
 * Description: Lays the pieces of one gap of Pele's layered layout on tracks, and finds the curves that need levels.
 *
 * Authors: Bahey Shalash
 * Version: 0.3
 * Date: 23/11/2026
 */

extension LayeredFlatTracks {
    /// Gives the pieces of one gap their tracks, each the number its group takes, counting from the group's first in
    /// curves; returns the number of tracks. The pieces reaching furthest go first, so that those of one fan nest.
    mutating func lay(_ list: inout [Int]) -> Int {
        // No piece takes no track; one piece takes the first, a group of its own one track high.
        if list.isEmpty { return 0 }
        if list.count == 1 {
            pieces.track[list[0]] = 0
            pieces.levels[list[0]] = 1
            return 1
        }
        let low = low, high = high
        var spare = workspace.emptyIntegers(capacity: 0)
        list.sortStably(spare: &spare) { first, second in
            let reach = (high[second] - low[second]) - (high[first] - low[first])
            if reach != 0 { return reach < 0 }
            return (low[first] != low[second] ? low[first] - low[second] : Double(first - second)) < 0
        }
        workspace.recycle(consume spare)
        let count = list.count
        var groups = LayeredUnionFind(count: count, workspace: workspace)
        let rows: Int
        if count <= LayeredFlatConstants.maximumWeighedPieces {
            rows = layWeighed(list, groups: &groups)
        } else {
            var sequence = workspace.emptyIntegers(capacity: count)
            sequence.append(contentsOf: 0..<count)
            rows = placeOnTracks(list, sequence: sequence)
            workspace.recycle(consume sequence)
        }
        writeLevels(of: list, groups: &groups, rows: rows)
        groups.recycle(into: workspace)
        return rows
    }

    /// The tracks of a gap few enough to weigh which piece goes above which; returns the number of tracks.
    private mutating func layWeighed(_ list: [Int], groups: inout LayeredUnionFind) -> Int {
        let pairs = nearPairs(list)
        // Each pair that clashes is a link both ways, in the order of the pairs.
        var keys = workspace.emptyIntegers(capacity: 0)
        var values = workspace.emptyIntegers(capacity: 0)
        for pair in stride(from: 0, to: pairs.count, by: 2) where clash(list[pairs[pair]], list[pairs[pair + 1]]) {
            keys.append(pairs[pair])
            values.append(pairs[pair + 1])
            keys.append(pairs[pair + 1])
            values.append(pairs[pair])
        }
        let clashes = LayeredLinkLists(count: list.count, keys: keys, values: values, workspace: workspace)
        workspace.recycle(consume keys)
        workspace.recycle(consume values)
        var sequence = workspace.emptyIntegers(capacity: list.count)
        let above = weighedSequence(list, pairs: pairs, groups: &groups, into: &sequence)
        workspace.recycle(consume pairs)
        let rows = placeOnWeighedTracks(list, sequence: sequence, above: above, clashes: clashes)
        above.recycle(into: workspace)
        clashes.recycle(into: workspace)
        workspace.recycle(consume sequence)
        return rows
    }

    /// Each piece's group's number of tracks, and in curves each track counted from its group's first.
    private mutating func writeLevels(of list: [Int], groups: inout LayeredUnionFind, rows: Int) {
        let count = list.count
        var firstTrack = workspace.integers(count: count, repeating: rows)
        var lastTrack = workspace.integers(count: count, repeating: -1)
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
        workspace.recycle(consume firstTrack)
        workspace.recycle(consume lastTrack)
    }

    /// Which pieces should be above which, so that they cross less, the pieces that could meet joined into groups, and
    /// the order that follows as many of those wishes as it can, written to `sequence`. Returns, for each piece, those
    /// that should be above it.
    private func weighedSequence(_ list: [Int], pairs: [Int], groups: inout LayeredUnionFind, into sequence: inout [Int]) -> LayeredLinkLists {
        // Each wish as a piece that should be below and the one that should be above it, in the order of the pairs.
        var lowerPieces = workspace.emptyIntegers(capacity: 0)
        var upperPieces = workspace.emptyIntegers(capacity: 0)
        var waiting = workspace.integers(count: list.count, repeating: 0)
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
        let above = LayeredLinkLists(count: list.count, keys: lowerPieces, values: upperPieces, workspace: workspace)
        let after = LayeredLinkLists(count: list.count, keys: upperPieces, values: lowerPieces, workspace: workspace)
        workspace.recycle(consume lowerPieces)
        workspace.recycle(consume upperPieces)
        Self.sequence(count: list.count, waiting: &waiting, after: after, into: &sequence, workspace: workspace)
        workspace.recycle(consume waiting)
        after.recycle(into: workspace)
        return above
    }

    /// The order that follows as many of the wishes as it can: a piece once all that should be above it are placed, and
    /// when none is free, the one with the fewest still waiting.
    private static func sequence(count: Int, waiting: inout [Int], after: LayeredLinkLists, into sequence: inout [Int],
                                 workspace: LayeredFlatWorkspace) {
        var isPlaced = workspace.flags(count: count, repeating: false)
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
        workspace.recycle(consume isPlaced)
    }

    /// Each piece of a weighed gap on the first track below those that should be above it that no piece it clashes
    /// with has taken. Every piece starts without a track, so the piece placed k-th takes a track no higher than k: the
    /// tracks taken are marked in one list of flags as long as the list, instead of a set.
    private mutating func placeOnWeighedTracks(_ list: [Int], sequence: [Int], above: LayeredLinkLists, clashes: LayeredLinkLists) -> Int {
        var isTaken = workspace.flags(count: list.count + 1, repeating: false)
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
        workspace.recycle(consume isTaken)
        return rows
    }

    /// Each piece of a gap of too many pieces to weigh on the first track where it clashes with none already there.
    private mutating func placeOnTracks(_ list: [Int], sequence: [Int]) -> Int {
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
    mutating func assignLevels(rank: Int, all: [Int]) {
        // A lone piece has none to be told apart from: it turns onto no level and leaves the gap as it is.
        if all.count < 2 { return }
        let pairs = nearPairs(all)
        defer {
            for piece in all {
                isLevel[piece] = false
                isBeside[piece] = false
            }
            workspace.recycle(pairs)
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
        var members = workspace.emptyIntegers(capacity: all.count)
        for piece in all where isLevel[piece] || (!pieces.isWide[piece] && isBeside[piece]) { members.append(piece) }
        _ = lay(&members)
        var most: Int?
        for piece in members { most = max(most ?? pieces.levels[piece], pieces.levels[piece]) }
        trackCount[rank] = most ?? 0
        workspace.recycle(consume members)
    }

    /// Marks in `isLevel` the pieces that turn onto levels: first those that run far across and have another such
    /// piece to be told apart from, then any two that would pass too near each other as plain curves. Returns how many.
    private mutating func markLevelPieces(rank: Int, all: [Int], pairs: [Int]) -> Int {
        var far = workspace.emptyIntegers(capacity: all.count)
        for piece in all where pieces.isWide[piece] { far.append(piece) }
        defer { workspace.recycle(far) }
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

    /// The groups of `count` indices, each its own, in a list of `workspace`.
    init(count: Int, workspace: LayeredFlatWorkspace) {
        parent = workspace.emptyIntegers(capacity: count)
        parent.append(contentsOf: 0..<count)
    }

    /// Gives the list back to `workspace`.
    consuming func recycle(into workspace: LayeredFlatWorkspace) { workspace.recycle(parent) }

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
