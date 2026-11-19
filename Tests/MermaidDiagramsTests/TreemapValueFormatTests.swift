/**
 * File: TreemapValueFormatTests.swift
 * -----------------------------------
 * Layer: Tests
 * Description: Writing a treemap's values by a d3-format specifier as Pele's format does, and JavaScript's rounding of numbers.
 *
 * Authors: Bahey Shalash
 * Version: 0.2
 * Date: 19/11/2026
 */

import XCTest
@testable import MermaidDiagrams

final class TreemapValueFormatTests: XCTestCase {
    private func written(_ specifier: String, _ value: Double) -> String { TreemapValueFormat(specifier: specifier).text(value) }

    func testTheSpecifiersMermaidDocumentsAreWrittenAsPeleWritesThem() {
        XCTAssertEqual(written(",", 1_234_567.5), "1,234,567.5")
        XCTAssertEqual(written(",", 0.35), "0.35")
        XCTAssertEqual(written("$", 1_234), "$1234")
        XCTAssertEqual(written(".1f", 12), "12.0")
        XCTAssertEqual(written(".1%", 0.357), "35.7%")
        XCTAssertEqual(written("$0,0", 700_000), "$700,000")
        XCTAssertEqual(written("$.2f", 5), "$5.00")
        XCTAssertEqual(written("$,.2f", 1_234.5), "$1,234.50")
        XCTAssertEqual(written("$.1%", 0.25), "$25.0%")
        XCTAssertEqual(written("d", 12.6), "13")
        XCTAssertEqual(written("+,", 1_000), "+1,000")
        XCTAssertEqual(written(".3~f", 1.5), "1.5")
    }

    func testWhatItDoesNotKnowFallsBackToThousandsSeparatorsAndAnEmptyOneHasNone() {
        XCTAssertEqual(written("not a format", 1_234), "1,234")
        XCTAssertEqual(written("", 1_234), "1234")
        XCTAssertEqual(written(".999f", 1), "1." + String(repeating: "0", count: 20))
        // The precision is read as a number, its leading zeros aside: `.007f` asks for 7 decimals, as `Number("007")` is 7.
        XCTAssertEqual(written(".007f", 1), "1.0000000")
        XCTAssertEqual(written(".000f", 1.5), "2")
        XCTAssertEqual(written(".0000000000000000000000003f", 1), "1.000")
        XCTAssertEqual(written(String(repeating: "0", count: 50_000) + "x", 1_234), "1234")
    }

    func testSignsExponentsAndDroppedZerosAreWritten() {
        XCTAssertEqual(written(",", -1_234.5), "-1,234.5")
        XCTAssertEqual(written("+", -3), "-3")
        XCTAssertEqual(written(".2e", 12_345), "1.23e+4")
        XCTAssertEqual(written(".0e", 0), "0e+0")
        XCTAssertEqual(written(".2~f", 2), "2")
        XCTAssertEqual(written(".3~f", 100), "100")
        XCTAssertEqual(written(",.2~f", 1_000.10), "1,000.1")
        XCTAssertEqual(written(".3", 1.23456), "1.23")
        XCTAssertEqual(written("x", 1), "1")
        XCTAssertEqual(written(",", 1e21), "1e+21")
        XCTAssertEqual(written(",", 0), "0")
        XCTAssertEqual(written(",", .infinity), "Infinity")
    }

    func testRoundingGoesUpOnTheExactValueOfADoubleLikeJavaScripts() {
        XCTAssertEqual(TreemapNumberText.fixed(2.5, digits: 0), "3", "C's printf gives 2")
        XCTAssertEqual(TreemapNumberText.fixed(0.125, digits: 2), "0.13")
        XCTAssertEqual(TreemapNumberText.fixed(1.005, digits: 2), "1.00", "1.005 is a little less than that as a double")
        XCTAssertEqual(TreemapNumberText.fixed(0.006, digits: 2), "0.01")
        XCTAssertEqual(TreemapNumberText.fixed(0.0004, digits: 2), "0.00")
        XCTAssertEqual(TreemapNumberText.fixed(9.995, digits: 2), "9.99", "9.995 is a little less than that")
        XCTAssertEqual(TreemapNumberText.fixed(999.5, digits: 0), "1000")
        XCTAssertEqual(TreemapNumberText.fixed(0, digits: 3), "0.000")
        XCTAssertEqual(TreemapNumberText.exponential(15, digits: 0), "2e+1")
        XCTAssertEqual(TreemapNumberText.exponential(9.96, digits: 1), "1.0e+1")
        XCTAssertEqual(TreemapNumberText.significant(1_234_567.55, digits: 12), 1_234_567.55)
        XCTAssertEqual(TreemapNumberText.significant(0.123456, digits: 3), 0.123)
        XCTAssertEqual(TreemapNumberText.significant(99.96, digits: 3), 100)
    }
}
