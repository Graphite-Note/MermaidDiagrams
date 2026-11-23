/**
 * File: JavaScriptNumberShortestDigitsTests.swift
 * -----------------------------------------------
 * Layer: Tests
 * Description: Checks that the shortest digits of a double, read from its description's bytes in one pass, are those
 *              the description gives split at its exponent and point, on whole numbers, powers of ten and two, tiny and
 *              huge values and random doubles of every exponent.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 23/11/2026
 */

@testable import MermaidDiagrams
import XCTest

final class JavaScriptNumberShortestDigitsTests: XCTestCase {
    func testTheDigitsAreTheDescriptionsSplitAtItsExponentAndPoint() {
        var values: [Double] = [5e-324, Double.leastNormalMagnitude, Double.greatestFiniteMagnitude, 0.1, 0.000001, 1e-7, 1e21, 1.2345678901234568e20,
                                1.5, 100, 1500, 0.00125, 9_007_199_254_740_992]
        values += (-30...30).map { exponent in pow(10, Double(exponent)) }
        values += (-1_074...1_023).filter { exponent in exponent % 7 == 0 }.map { exponent in pow(2, Double(exponent)) }
        var state: UInt64 = 0x0123_4567_89AB_CDEF
        for _ in 0..<5_000 {
            state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            let value = Double(bitPattern: state >> 1)
            if value.isFinite, value > 0 { values.append(value) }
        }
        for value in values {
            let read = JavaScriptNumberText.shortestDigits(of: value)
            let expected = Self.digitsSplitFromTheDescription(of: value)
            XCTAssertEqual(read.digits, expected.digits, "\(value)")
            XCTAssertEqual(read.pointPosition, expected.pointPosition, "\(value)")
        }
    }

    /// The reading the package had before: the description split at `e`, then at the point, zeros trimmed at both ends.
    private static func digitsSplitFromTheDescription(of magnitude: Double) -> (digits: String, pointPosition: Int) {
        let written = magnitude.description
        let parts = written.split(separator: "e", maxSplits: 1)
        let exponent = parts.count == 2 ? Int(parts[1]) ?? 0 : 0
        let mantissa = parts[0].split(separator: ".", maxSplits: 1)
        let integerDigits = mantissa[0]
        let allDigits = Substring(integerDigits + (mantissa.count == 2 ? mantissa[1] : ""))
        let leadingZeroCount = allDigits.prefix { character in character == "0" }.count
        let significant = allDigits.dropFirst(leadingZeroCount)
        let trimmed = significant.prefix(significant.count - significant.reversed().prefix { character in character == "0" }.count)
        return (String(trimmed), integerDigits.count + exponent - leadingZeroCount)
    }
}
