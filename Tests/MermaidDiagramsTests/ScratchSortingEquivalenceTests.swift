/**
 * File: ScratchSortingEquivalenceTests.swift
 * ------------------------------------------
 * Layer: Tests
 * Description: The stable sort on scratch spans orders exactly as the array's stable sort does, with comparisons that
 *              tie, that are NaN, and on every length either side of the switch from insertion to merging.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 24/11/2026
 */

import XCTest
@testable import MermaidDiagrams

final class ScratchSortingEquivalenceTests: XCTestCase {
    /// Random keys with ties and NaNs, sorted on a span and in an array by the same comparison, end in the same order,
    /// for lengths from 0 to 140, the whole span and a part of it.
    func testSpanSortOrdersAsTheArraySortDoes() {
        var generator = ScratchSortingGenerator(seed: 0x5EED_50A7)
        let arena = DiagramScratchArena()
        defer { arena.deallocate() }
        for length in 0...140 {
            for _ in 0..<4 {
                let keys = (0..<length).map { _ -> Double in
                    let draw = Int.random(in: 0..<10, using: &generator)
                    return draw == 0 ? .nan : Double(Int.random(in: 0..<(length / 3 + 2), using: &generator))
                }
                var expected = Array(0..<length)
                var spare: [Int] = []
                expected.sortStably(spare: &spare) { first, second in keys[first] - keys[second] < 0 }
                let span = arena.span(count: length, repeating: 0)
                for index in 0..<length { span[index] = index }
                span.sortStably(in: arena) { first, second in keys[first] - keys[second] < 0 }
                XCTAssertEqual(Array(span), expected, "length \(length)")
                let mark = arena.mark()
                let padded = arena.span(count: length + 6, repeating: -1)
                for index in 0..<length { padded[index + 3] = index }
                padded.sortStably(3..<(length + 3), in: arena) { first, second in keys[first] - keys[second] < 0 }
                XCTAssertEqual(Array(padded[3..<(length + 3)]), expected, "part of length \(length)")
                XCTAssertEqual(Array(padded[0..<3]) + Array(padded[(length + 3)...]), [-1, -1, -1, -1, -1, -1])
                arena.release(to: mark)
            }
        }
    }

    /// A comparison that is always NaN keeps every order as it is, as the array's does.
    func testAComparisonThatIsAlwaysNaNKeepsTheOrder() {
        let arena = DiagramScratchArena()
        defer { arena.deallocate() }
        let span = arena.span(count: 50, repeating: 0)
        for index in 0..<50 { span[index] = 49 - index }
        let difference = Double.nan
        span.sortStably(in: arena) { _, _ in difference < 0 }
        XCTAssertEqual(Array(span), Array((0..<50).reversed()))
    }
}

/// SplitMix64, so that the random keys are the same on every run.
private struct ScratchSortingGenerator: RandomNumberGenerator {
    var state: UInt64

    init(seed: UInt64) { state = seed }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var mixed = state
        mixed = (mixed ^ (mixed >> 30)) &* 0xBF58_476D_1CE4_E5B9
        mixed = (mixed ^ (mixed >> 27)) &* 0x94D0_49BB_1331_11EB
        return mixed ^ (mixed >> 31)
    }
}
