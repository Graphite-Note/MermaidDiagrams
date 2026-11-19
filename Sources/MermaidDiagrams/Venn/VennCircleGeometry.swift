/**
 * File: VennCircleGeometry.swift
 * ------------------------------
 * Layer: Core
 * Description: The geometry of a Venn diagram's circles, Pele's: the area two circles share, the distance that gives an
 *              overlap its area, and the pairwise overlaps an overlap of three or more sets implies.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 19/11/2026
 */

import Foundation

/// A circle of a Venn diagram, in the layout's units until it is scaled and placed.
struct VennCircle: Equatable {
    let identifier: String
    var x: Double
    var y: Double
    var radius: Double
}

/// The area two circles share, how far apart they sit for an overlap, and the overlaps a diagram implies.
enum VennCircleGeometry {
    /// Bisection steps toward a distance: past 48, a double's halving changes nothing.
    static let bisectionStepCount = 48

    /// The area two circles of radii `first` and `second` share when their centers are `distance` apart.
    static func lensArea(_ first: Double, _ second: Double, distance: Double) -> Double {
        if distance >= first + second { return 0 }
        let smaller = min(first, second)
        if distance <= abs(first - second) { return Double.pi * smaller * smaller }
        let firstSegment = first * first * acos((distance * distance + first * first - second * second) / (2 * distance * first))
        let secondSegment = second * second * acos((distance * distance + second * second - first * first) / (2 * distance * second))
        let product = (-distance + first + second) * (distance + first - second) * (distance - first + second) * (distance + first + second)
        return firstSegment + secondSegment - 0.5 * sqrt(max(product, 0))
    }

    /// How far apart two circles sit for their overlap to have `area`: the area falls as the distance grows, so bisection
    /// finds it. No overlap (or one not a positive number) keeps them touching; one as large as the smaller circle puts
    /// it inside the other.
    static func distanceForOverlap(_ first: Double, _ second: Double, area: Double) -> Double {
        var low = abs(first - second)
        var high = first + second
        if !(area > 0) { return high }
        if area >= Double.pi * pow(min(first, second), 2) { return low }
        for _ in 0..<bisectionStepCount {
            let middle = (low + high) / 2
            if lensArea(first, second, distance: middle) > area { low = middle } else { high = middle }
        }
        return (low + high) / 2
    }

    /// For every overlap of three or more sets, the pairwise overlaps it implies that the diagram does not state, a quarter
    /// of the smaller set each (2.5 when a size is unknown), so that the circles are drawn overlapping; `subsets` itself
    /// when there is nothing to add.
    static func withPairwiseSubsets(_ subsets: [VennSubset]) -> [VennSubset] {
        var present: Set<[String]> = []
        var sizes: [String: Double] = [:]
        for subset in subsets {
            present.insert(subset.sets.sorted(by: PlaneMapText.isOrderedBeforeByCodeUnits))
            if subset.sets.count == 1 { sizes[subset.sets[0]] = subset.size }
        }
        var added: [VennSubset] = []
        for subset in subsets where subset.sets.count >= 3 {
            let members = subset.sets.sorted(by: PlaneMapText.isOrderedBeforeByCodeUnits)
            for first in 0..<(members.count - 1) {
                for second in (first + 1)..<members.count {
                    let pair = [members[first], members[second]]
                    guard present.insert(pair).inserted else { continue }
                    let size = sizes[pair[0]].flatMap { firstSize in sizes[pair[1]].map { secondSize in min(firstSize, secondSize) / 4 } }
                    added.append(VennSubset(sets: pair, size: size ?? defaultImpliedOverlap, label: ""))
                }
            }
        }
        return added.isEmpty ? subsets : subsets + added
    }

    /// A quarter of a set of the default size, 10.
    static let defaultImpliedOverlap = 2.5
}
