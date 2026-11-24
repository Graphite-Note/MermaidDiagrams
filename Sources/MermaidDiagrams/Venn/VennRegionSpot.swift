/**
 * File: VennRegionSpot.swift
 * --------------------------
 * Layer: Core
 * Description: Where a Venn diagram's region holds its text, as Pele's findSpot finds it: the point inside the region's
 *              circles and outside the others farthest from their outlines, by a grid of samples and an uphill walk.
 *
 * Authors: Bahey Shalash
 * Version: 0.2
 * Date: 23/11/2026
 */

import Foundation

/// The roomiest point of a region and how far it is from the nearest outline it must stay within or without. A margin
/// of 0 or less means the circles as placed leave the region empty.
struct VennRegionSpot: Equatable {
    var x: Double
    var y: Double
    var margin: Double

    /// The samples across the smallest circle's radius, each way from its center.
    static let gridSteps = 10
    /// The most rounds of the walk uphill from the best sample: eight steps a round, halving the step when none helps.
    static let walkRoundCount = 40
    /// The walk stops once its step is this share of the radius.
    static let smallestStepShare = 1e-6
    /// Margins this share of the radius apart are equal, and the point nearer the middle wins.
    static let tieShare = 1e-9
    /// The walk's eight directions, the cosine and sine of each eighth of a turn, found once for every walk.
    private static let walkDirections: [(across: Double, down: Double)] = (0..<8).map { direction in
        let angle = Double(direction) * 2 * Double.pi / 8
        return (cos(angle), sin(angle))
    }

    /// Samples the smallest of `inside` on a grid, then walks uphill from the best sample. Ties go to the point nearest the
    /// middle of the region's circles, so that a symmetric arrangement gets symmetric labels.
    static func find(in circles: [VennCircle], inside: [Int], outside: [Int]) -> VennRegionSpot {
        // A circle alone: no point is farther from its outline than its center, where the search starts.
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
            let y = smallest.y + Double(gridY) * radius / Double(gridSteps)
            for gridX in -gridSteps...gridSteps where gridX * gridX + gridY * gridY <= gridSteps * gridSteps {
                _ = search.consider(smallest.x + Double(gridX) * radius / Double(gridSteps), y)
            }
        }
        var step = radius / Double(gridSteps)
        var round = 0
        while round < walkRoundCount && step > radius * smallestStepShare {
            var moved = false
            for direction in walkDirections {
                if search.consider(search.best.x + direction.across * step, search.best.y + direction.down * step) { moved = true }
            }
            if !moved { step /= 2 }
            round += 1
        }
        return search.best
    }

    /// The search's best point so far and its distance from the middle.
    private struct Search {
        /// The circles the point must stay within, then those it must stay out of: their centers and radii alone, in
        /// one list, so that weighing a point reads no identifiers.
        private let rings: [(x: Double, y: Double, radius: Double)]
        private let insideCount: Int
        let middleX: Double
        let middleY: Double
        let radius: Double
        /// Margins this close are equal.
        private let tolerance: Double
        var best: VennRegionSpot
        var distanceFromMiddle = 0.0

        init(circles: [VennCircle], inside: [Int], outside: [Int], middleX: Double, middleY: Double, radius: Double) {
            var rings: [(x: Double, y: Double, radius: Double)] = []
            rings.reserveCapacity(inside.count + outside.count)
            for index in inside { rings.append((circles[index].x, circles[index].y, circles[index].radius)) }
            for index in outside { rings.append((circles[index].x, circles[index].y, circles[index].radius)) }
            self.rings = rings
            insideCount = inside.count
            self.middleX = middleX
            self.middleY = middleY
            self.radius = radius
            tolerance = radius * VennRegionSpot.tieShare
            best = VennRegionSpot(x: middleX, y: middleY, margin: 0)
            best.margin = margin(atX: middleX, y: middleY, floor: -.infinity)
        }

        /// Takes the point when it has more room, or as much and is nearer the middle.
        mutating func consider(_ x: Double, _ y: Double) -> Bool {
            let room = margin(atX: x, y: y, floor: best.margin - tolerance)
            guard room > best.margin - tolerance else { return false }
            let distance = hypot(x - middleX, y - middleY)
            guard room > best.margin + tolerance || distance < distanceFromMiddle - tolerance else { return false }
            best = VennRegionSpot(x: x, y: y, margin: room)
            distanceFromMiddle = distance
            return true
        }

        /// How far the point is from the nearest outline it must stay within or without; some value below `floor` as
        /// soon as it cannot reach `floor`.
        func margin(atX x: Double, y: Double, floor: Double) -> Double {
            var best = Double.infinity
            for position in 0..<insideCount {
                let circle = rings[position]
                let room = circle.radius - Self.distance(x - circle.x, y - circle.y)
                if room < best {
                    if room < floor { return room }
                    best = room
                }
            }
            for position in insideCount..<rings.count {
                let circle = rings[position]
                let room = Self.distance(x - circle.x, y - circle.y) - circle.radius
                if room < best {
                    if room < floor { return room }
                    best = room
                }
            }
            return best
        }

        /// The length of a vector as Pele computes it here, the square root of the sum of the squares.
        private static func distance(_ across: Double, _ down: Double) -> Double {
            (across * across + down * down).squareRoot()
        }
    }
}
