/**
 * File: VennPlacementReferences.swift
 * -----------------------------------
 * Layer: Tests
 * Description: VennRegionSpot's search and VennCirclePlacement as they were at 0.6.1, kept as the references the faster
 *              ones must match number for number (TypeLayoutEquivalenceTests).
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 23/11/2026
 */

import Foundation
@testable import MermaidDiagrams

/// The search of 0.6.1 unchanged but for its comments: the circles read by index for every point, the walk's directions
/// found by their cosine and sine at every step.
enum VennRegionSpotReference {

    static let gridSteps = VennRegionSpot.gridSteps
    static let walkRoundCount = VennRegionSpot.walkRoundCount
    static let smallestStepShare = VennRegionSpot.smallestStepShare
    static let tieShare = VennRegionSpot.tieShare

    static func find(in circles: [VennCircle], inside: [Int], outside: [Int]) -> VennRegionSpot {
        if inside.count == 1, outside.isEmpty {
            let circle = circles[inside[0]]
            return VennRegionSpot(x: circle.x, y: circle.y, margin: circle.radius)
        }
        var middleX = 0.0
        var middleY = 0.0
        var smallest = circles[inside[0]]
        for index in inside {
            let circle = circles[index]
            middleX += circle.x / Double(inside.count)
            middleY += circle.y / Double(inside.count)
            if circle.radius < smallest.radius { smallest = circle }
        }
        let radius = smallest.radius
        var search = Search(circles: circles, inside: inside, outside: outside, middleX: middleX, middleY: middleY, radius: radius)
        for gridY in -gridSteps...gridSteps {
            for gridX in -gridSteps...gridSteps where gridX * gridX + gridY * gridY <= gridSteps * gridSteps {
                _ = search.consider(smallest.x + Double(gridX) * radius / Double(gridSteps), smallest.y + Double(gridY) * radius / Double(gridSteps))
            }
        }
        var step = radius / Double(gridSteps)
        var round = 0
        while round < walkRoundCount && step > radius * smallestStepShare {
            var moved = false
            for direction in 0..<8 {
                let angle = Double(direction) * 2 * Double.pi / 8
                if search.consider(search.best.x + cos(angle) * step, search.best.y + sin(angle) * step) { moved = true }
            }
            if !moved { step /= 2 }
            round += 1
        }
        return search.best
    }

    private struct Search {
        let circles: [VennCircle]
        let inside: [Int]
        let outside: [Int]
        let middleX: Double
        let middleY: Double
        let radius: Double
        var best: VennRegionSpot
        var distanceFromMiddle = 0.0

        init(circles: [VennCircle], inside: [Int], outside: [Int], middleX: Double, middleY: Double, radius: Double) {
            self.circles = circles
            self.inside = inside
            self.outside = outside
            self.middleX = middleX
            self.middleY = middleY
            self.radius = radius
            best = VennRegionSpot(x: middleX, y: middleY, margin: 0)
            best.margin = margin(atX: middleX, y: middleY, floor: -.infinity)
        }

        mutating func consider(_ x: Double, _ y: Double) -> Bool {
            let tolerance = radius * VennRegionSpot.tieShare
            let room = margin(atX: x, y: y, floor: best.margin - tolerance)
            guard room > best.margin - tolerance else { return false }
            let distance = hypot(x - middleX, y - middleY)
            guard room > best.margin + tolerance || distance < distanceFromMiddle - tolerance else { return false }
            best = VennRegionSpot(x: x, y: y, margin: room)
            distanceFromMiddle = distance
            return true
        }

        func margin(atX x: Double, y: Double, floor: Double) -> Double {
            var best = Double.infinity
            for index in inside {
                let circle = circles[index]
                let room = circle.radius - Self.distance(x - circle.x, y - circle.y)
                if room < best {
                    if room < floor { return room }
                    best = room
                }
            }
            for index in outside {
                let circle = circles[index]
                let room = Self.distance(x - circle.x, y - circle.y) - circle.radius
                if room < best {
                    if room < floor { return room }
                    best = room
                }
            }
            return best
        }

        private static func distance(_ across: Double, _ down: Double) -> Double {
            (across * across + down * down).squareRoot()
        }
    }
}


/// The placement of 0.6.1 unchanged but for its comments: the wanted distances looked up by key in every round, the
/// moves made anew for each round.
struct VennCirclePlacementReference {
    private(set) var circles: [VennCircle] = []
    private(set) var indexByIdentifier: [String: Int] = [:]
    private(set) var widestRadius: Double = 0
    private var wantedDistances: [Int: Double] = [:]

    static let defaultSize: Double = 10
    static let smallestRadiusShare = 0.3
    static let gapShare = 0.15
    static let tripleOverlapShare = 0.12
    static let tripleShrinkFactor = 0.94
    static let tripleAttemptCount = 40
    static let largestRing = 64
    static let mostRelaxationRounds = 300
    static let relaxationPairStepBudget = 3_000_000.0

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
            if !hasTripleOverlap || VennRegionSpotReference.find(in: circles, inside: [0, 1, 2], outside: []).margin > widestRadius * Self.tripleOverlapShare {
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
        for _ in 0..<Self.relaxationRounds(circleCount: count) { relaxOnce() }
    }

    private mutating func relaxOnce() {
        let count = circles.count
        var moveX = [Double](repeating: 0, count: count)
        var moveY = [Double](repeating: 0, count: count)
        var pulls = [Int](repeating: 0, count: count)
        for first in 0..<count {
            for second in (first + 1)..<count {
                let overlap = wantedDistances[first * count + second]
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
                moveX[first] += unitX * move
                moveY[first] += unitY * move
                moveX[second] -= unitX * move
                moveY[second] -= unitY * move
                pulls[first] += 1
                pulls[second] += 1
            }
        }
        for index in 0..<count where pulls[index] > 0 {
            circles[index].x += moveX[index] / Double(pulls[index])
            circles[index].y += moveY[index] / Double(pulls[index])
        }
    }
}
