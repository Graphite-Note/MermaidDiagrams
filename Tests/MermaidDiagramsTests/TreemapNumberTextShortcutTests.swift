/**
 * File: TreemapNumberTextShortcutTests.swift
 * ------------------------------------------
 * Layer: Tests
 * Description: Checks that a treemap's numbers written from their shortest digits are the numbers written from their
 *              exact decimal values, on whole numbers, short decimals, powers of two and random doubles.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 23/11/2026
 */

@testable import MermaidDiagrams
import XCTest

final class TreemapNumberTextShortcutTests: XCTestCase {
    /// A fixed set of doubles: whole numbers, short decimals, halves, powers of two and of ten, tiny and huge values, and
    /// random doubles of every exponent from a seeded generator.
    private static let values: [Double] = {
        var values: [Double] = [0.5, 1.5, 2.5, 0.125, 0.005, 1.005, 2.675, 1e-7, 123_456_789.125, 9.995, 0.045, 1e20, 4.35, 0.1, 0.2, 0.3]
        values += (0...200).map(Double.init)
        values += (-60...70).map { exponent in pow(2, Double(exponent)) }
        values += (-20...20).map { exponent in pow(10, Double(exponent)) }
        values += (1...400).map { step in Double(step) * 0.01 }
        values += (1...200).map { step in Double(step) * 0.125 + 1_000 }
        var generator = SeededGenerator(state: 0x9E37_79B9_7F4A_7C15)
        for _ in 0..<3_000 {
            let mantissa = Double(generator.next() % (1 << 52)) / Double(1 << 52) + 1
            let exponent = Int(generator.next() % 80) - 40
            values.append(mantissa * pow(2, Double(exponent)))
        }
        for _ in 0..<1_000 { values.append(Double(generator.next() % 1_000_000) / 100) }
        return values.filter { value in value > 0 && value < 1e21 }
    }()

    func testFixedFromShortestDigitsIsTheExactRounding() {
        for value in Self.values {
            for digits in 0...12 {
                XCTAssertEqual(TreemapNumberText.fixed(value, digits: digits), TreemapNumberText.exactlyRoundedFixed(value, digits: digits),
                               "\(value) to \(digits) decimals")
            }
        }
    }

    func testSignificantFromShortestDigitsIsTheExactRounding() {
        for value in Self.values {
            for digits in 1...17 {
                XCTAssertEqual(TreemapNumberText.significant(value, digits: digits), TreemapNumberText.exactlyRoundedSignificant(value, digits: digits),
                               "\(value) to \(digits) digits")
            }
        }
    }
}

/// SplitMix64: the same doubles on every run.
private struct SeededGenerator {
    var state: UInt64

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var mixed = state
        mixed = (mixed ^ (mixed >> 30)) &* 0xBF58_476D_1CE4_E5B9
        mixed = (mixed ^ (mixed >> 27)) &* 0x94D0_49BB_1331_11EB
        return mixed ^ (mixed >> 31)
    }
}
