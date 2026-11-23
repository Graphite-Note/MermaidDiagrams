/**
 * File: LayeredSortingEquivalenceTests.swift
 * ------------------------------------------
 * Layer: Tests
 * Description: The layered layout's own sorts give the orders of the sorts they replaced: the stable sort with a reused
 *              spare list as JavaScript's sort, and the middle two of four positions as Array.sorted() gives them.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 23/11/2026
 */

import XCTest
@testable import MermaidDiagrams

final class LayeredSortingEquivalenceTests: XCTestCase {
    /// Every length on either side of the insertion sort's limit and well past it, with keys that tie often, sorted
    /// through a spare list kept from the longer lists before it: the order is the stable order of the keys.
    func testSortWithReusedSpareIsStableAndMatchesKeyOrder() {
        var generator = LayeredSortingGenerator(seed: 0x5EED_1A7E)
        var spare: [Int] = []
        for length in [0, 1, 2, 3, 15, 16, 17, 31, 32, 33, 64, 100, 257, 40, 5, 300, 17] {
            for distinctKeys in [1, 3, length + 1] {
                let keys = (0..<length).map { _ in Double(Int.random(in: 0..<max(1, distinctKeys), using: &generator)) }
                var sorted = Array(0..<length)
                sorted.sortStably(spare: &spare) { first, second in keys[first] - keys[second] < 0 }
                let expected = (0..<length).sorted { first, second in (keys[first], first) < (keys[second], second) }
                XCTAssertEqual(sorted, expected, "length \(length), \(distinctKeys) keys")
                var sortedWithoutSpare = Array(0..<length)
                sortedWithoutSpare.sortStably { first, second in keys[first] - keys[second] }
                XCTAssertEqual(sortedWithoutSpare, expected, "length \(length), \(distinctKeys) keys, no spare")
            }
        }
    }

    /// A comparison that is NaN is a tie, as in JavaScript: the elements keep their order, short or long.
    func testComparisonThatIsNotANumberKeepsTheOrder() {
        for length in [5, 16, 17, 90] {
            var elements = Array((0..<length).reversed())
            elements.sortStably { _, _ in .nan }
            XCTAssertEqual(elements, Array((0..<length).reversed()))
        }
    }

    /// The balanced position of a vertex is the mean of the middle two of its four positions: they are exactly those
    /// `Array.sorted()` puts second and third, for every arrangement of ties, zeros of either sign, infinities and NaN.
    func testMiddleTwoMatchesSortedArrayBitForBit() {
        let values: [Double] = [-1, -0.0, 0.0, 1, 2.5, .infinity, -.infinity, .nan]
        for first in values {
            for second in values {
                for third in values {
                    for fourth in values {
                        let sorted = [first, second, third, fourth].sorted()
                        let middle = LayeredFlatPositioning.middleTwo(first, second, third, fourth)
                        XCTAssertEqual(middle.second.bitPattern, sorted[1].bitPattern, "\([first, second, third, fourth])")
                        XCTAssertEqual(middle.third.bitPattern, sorted[2].bitPattern, "\([first, second, third, fourth])")
                    }
                }
            }
        }
    }
}

/// SplitMix64: the same values on every run.
private struct LayeredSortingGenerator: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var mixed = state
        mixed = (mixed ^ (mixed >> 30)) &* 0xBF58_476D_1CE4_E5B9
        mixed = (mixed ^ (mixed >> 27)) &* 0x94D0_49BB_1331_11EB
        return mixed ^ (mixed >> 31)
    }
}
