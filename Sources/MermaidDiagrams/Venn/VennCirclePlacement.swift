/**
 * File: VennCirclePlacement.swift
 * -------------------------------
 * Layer: Core
 * Description: Places one circle per set of a Venn diagram as Pele's layout.ts does: areas in proportion to the sets'
 *              sizes, each pair as far apart as its overlap asks, two and three sets exactly, more by relaxing a ring.
 *
 * Authors: Bahey Shalash
 * Version: 0.2
 * Date: 23/11/2026
 */

import Foundation

/// Places one circle per set, with areas in proportion to the sets' sizes and each pair as far apart as its overlap
/// asks: one, two and three sets exactly, more by relaxing a ring of circles (a grid past 64) toward those distances, in
/// as many rounds as keep the work near three million pair steps. Lengths are in units of the square root of a size.
struct VennCirclePlacement {
    private(set) var circles: [VennCircle] = []
    /// The circles' places by identifier.
    private(set) var indexByIdentifier: [String: Int] = [:]
    /// The radius of a circle of the largest size, which the minimum radius and the gaps are fractions of.
    private(set) var widestRadius: Double = 0
    /// How far apart each pair given an overlap should be, by `first * count + second` with `first < second`.
    private var wantedDistances: [Int: Double] = [:]

    /// The default size of a set.
    static let defaultSize: Double = 10
    /// The smallest radius, as a share of the widest: a set too small to hold its name still shows.
    static let smallestRadiusShare = 0.3
    /// The gap between circles that do not overlap, as a share of the widest radius.
    static let gapShare = 0.15
    /// How far into the overlap of three sets their shared region must reach, as a share of the widest radius.
    static let tripleOverlapShare = 0.12
    /// How much the triangle of three sets shrinks at each attempt to make them share a region, and how many attempts.
    static let tripleShrinkFactor = 0.94
    static let tripleAttemptCount = 40
    /// Up to this many circles start on a ring; more start on a grid.
    static let largestRing = 64
    static let mostRelaxationRounds = 300
    /// The pair steps the relaxation may take over all its rounds.
    static let relaxationPairStepBudget = 3_000_000.0
    /// Up to this many circles, the relaxation reads the wanted distances from a table of every pair instead of looking
    /// each up by its key: 4,096 pairs at most.
    static let largestDistanceTable = 64

    /// Places the circles of `subsets`. The pairwise overlaps they state and imply, and the distances found for them, are
    /// at most `limits.maximumLayoutPointCount`, else the diagram is refused before any is made.
    init(subsets: [VennSubset], limits: MermaidDiagramLimits) throws(VennLayoutError) {
        makeCircles(subsets)
        let count = circles.count
        guard count >= 2 else { return }
        let needsDistances = count <= 3 || Self.relaxationRounds(circleCount: count) > 0
        if needsDistances { try findWantedDistances(subsets, limits: limits) }
        switch count {
        case 2: circles[1].x = distance(0, 1)
        case 3: placeTriangle(hasTripleOverlap: subsets.contains { subset in Set(subset.sets).count == 3 })
        default: relax()
        }
    }

    /// One circle per identifier in the order the subsets first name them, a set's own size over the default.
    private mutating func makeCircles(_ subsets: [VennSubset]) {
        var identifiers: [String] = []
        var sizes: [String: Double] = [:]
        for subset in subsets {
            for identifier in subset.sets where sizes[identifier] == nil {
                sizes[identifier] = Self.defaultSize
                identifiers.append(identifier)
            }
        }
        for subset in subsets where subset.sets.count == 1 { sizes[subset.sets[0]] = subset.size }
        var largest = 0.0
        for identifier in identifiers {
            if let size = sizes[identifier], size.isFinite, size > largest { largest = size }
        }
        if largest == 0 { largest = Self.defaultSize }
        widestRadius = sqrt(largest / Double.pi)
        for identifier in identifiers {
            let size = sizes[identifier] ?? Self.defaultSize
            let radius = size.isFinite && size > 0 ? sqrt(size / Double.pi) : 0
            indexByIdentifier[identifier] = circles.count
            circles.append(VennCircle(identifier: identifier, x: 0, y: 0, radius: max(radius, widestRadius * Self.smallestRadiusShare)))
        }
    }

    /// The overlap each pair is given, a later one replacing an earlier, turned into the distance between their centers.
    private mutating func findWantedDistances(_ subsets: [VennSubset], limits: MermaidDiagramLimits) throws(VennLayoutError) {
        let impliedPairCount = subsets.reduce(0) { count, subset in
            subset.sets.count >= 3 ? count + subset.sets.count * (subset.sets.count - 1) / 2 : count
        }
        guard impliedPairCount + subsets.count <= limits.maximumLayoutPointCount else {
            throw .tooManyOverlaps(limit: limits.maximumLayoutPointCount)
        }
        let count = circles.count
        var overlaps: [Int: Double] = [:]
        for subset in VennCircleGeometry.withPairwiseSubsets(subsets) where subset.sets.count == 2 {
            guard let first = indexByIdentifier[subset.sets[0]], let second = indexByIdentifier[subset.sets[1]], first != second else { continue }
            overlaps[min(first, second) * count + max(first, second)] = subset.size
        }
        for (key, area) in overlaps {
            wantedDistances[key] = VennCircleGeometry.distanceForOverlap(circles[key / count].radius, circles[key % count].radius, area: area)
        }
    }

    private var gap: Double { widestRadius * Self.gapShare }

    private func distance(_ first: Int, _ second: Int) -> Double {
        wantedDistances[first * circles.count + second] ?? circles[first].radius + circles[second].radius + gap
    }

    /// Two sets side by side and the third below, the corners of a triangle whose sides are the three distances; an overlap
    /// of all three has to exist, so the triangle shrinks until their shared region is deep enough.
    private mutating func placeTriangle(hasTripleOverlap: Bool) {
        var firstToSecond = distance(0, 1)
        var firstToThird = distance(0, 2)
        var secondToThird = distance(1, 2)
        for _ in 0..<Self.tripleAttemptCount {
            let across = firstToSecond > 0
                ? (firstToSecond * firstToSecond + firstToThird * firstToThird - secondToThird * secondToThird) / (2 * firstToSecond) : 0
            circles[1].x = firstToSecond
            circles[2].x = max(-firstToThird, min(firstToThird, across))
            circles[2].y = sqrt(max(firstToThird * firstToThird - across * across, 0))
            if !hasTripleOverlap || VennRegionSpot.find(in: circles, inside: [0, 1, 2], outside: []).margin > widestRadius * Self.tripleOverlapShare {
                break
            }
            firstToSecond *= Self.tripleShrinkFactor
            firstToThird *= Self.tripleShrinkFactor
            secondToThird *= Self.tripleShrinkFactor
        }
    }

    static func relaxationRounds(circleCount: Int) -> Int {
        Int(min(Double(mostRelaxationRounds), (relaxationPairStepBudget / Double(circleCount * circleCount)).rounded(.down)))
    }

    /// The circles on a ring (a grid past 64), then moved toward their distances: each pair that overlaps, or that sits
    /// closer than its gap, moves half the difference, each circle by the mean of its moves.
    private mutating func relax() {
        let count = circles.count
        var total = 0.0
        for circle in circles { total += 2 * circle.radius + gap }
        if count <= Self.largestRing {
            let ring = total / (2 * Double.pi)
            for index in circles.indices {
                let angle = Double(index) * 2 * Double.pi / Double(count) - Double.pi / 2
                circles[index].x = cos(angle) * ring
                circles[index].y = sin(angle) * ring
            }
        } else {
            let columns = Int(sqrt(Double(count)).rounded(.up))
            let cell = 2 * widestRadius + gap
            for index in circles.indices {
                circles[index].x = Double(index % columns) * cell
                circles[index].y = Double(index / columns) * cell
            }
        }
        let rounds = Self.relaxationRounds(circleCount: count)
        guard rounds > 0 else { return }
        var moves = Moves(count: count)
        var table: [Double?] = []
        if count <= Self.largestDistanceTable {
            table = [Double?](repeating: nil, count: count * count)
            for (key, distance) in wantedDistances { table[key] = distance }
        }
        for _ in 0..<rounds { relaxOnce(&moves, table: table) }
    }

    /// Each circle's moves in a round, added up, and how many pairs moved it: made once, cleared each round.
    private struct Moves {
        var moveX: [Double]
        var moveY: [Double]
        var pulls: [Int]

        init(count: Int) {
            moveX = [Double](repeating: 0, count: count)
            moveY = [Double](repeating: 0, count: count)
            pulls = [Int](repeating: 0, count: count)
        }

        mutating func clear() {
            for index in pulls.indices {
                moveX[index] = 0
                moveY[index] = 0
                pulls[index] = 0
            }
        }
    }

    /// One round: `table` holds the wanted distance of each pair by its key, else is empty and `wantedDistances` does.
    private mutating func relaxOnce(_ moves: inout Moves, table: [Double?]) {
        let count = circles.count
        moves.clear()
        for first in 0..<count {
            for second in (first + 1)..<count {
                let key = first * count + second
                let overlap = table.isEmpty ? wantedDistances[key] : table[key]
                let apart = circles[first].radius + circles[second].radius + gap
                var unitX = circles[second].x - circles[first].x
                var unitY = circles[second].y - circles[first].y
                var length = hypot(unitX, unitY)
                if overlap == nil && length >= apart { continue }
                if length < 1e-9 {
                    unitX = cos(Double(first + second))
                    unitY = sin(Double(first + second))
                    length = 1
                }
                let move = (length - (overlap ?? apart)) / 2 / length
                moves.moveX[first] += unitX * move
                moves.moveY[first] += unitY * move
                moves.moveX[second] -= unitX * move
                moves.moveY[second] -= unitY * move
                moves.pulls[first] += 1
                moves.pulls[second] += 1
            }
        }
        for index in 0..<count where moves.pulls[index] > 0 {
            circles[index].x += moves.moveX[index] / Double(moves.pulls[index])
            circles[index].y += moves.moveY[index] / Double(moves.pulls[index])
        }
    }
}
