/**
 * File: ChartDecimalTextTests.swift
 * ---------------------------------
 * Layer: Tests
 * Description: A short decimal number read on its bytes is the value Swift's Double reads from its text, bit for bit,
 *              on hundreds of thousands of random numbers and on the edges of the fast path.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 25/11/2026
 */

import XCTest
@testable import MermaidDiagrams

final class ChartDecimalTextTests: XCTestCase {
    private func assertReadAsDoubleReadsIt(_ text: String, file: StaticString = #filePath, line: UInt = #line) {
        let bytes = Array(text.utf8)
        guard let value = ChartDecimalText.value(of: bytes, from: 0, to: bytes.count) else { return }
        XCTAssertEqual(value.bitPattern, Double(text)?.bitPattern, text, file: file, line: line)
    }

    func testRandomDecimalsAreReadAsDoubleReadsThem() {
        var random = MapReadingMutations(seed: 0xDEC_0001, tokens: [])
        var readCount = 0
        for _ in 0..<300_000 {
            let integerDigits = (0..<(1 + random.below(10))).map { _ in String(random.below(10)) }.joined()
            let fractionDigits = (0..<random.below(14)).map { _ in String(random.below(10)) }.joined()
            let text = (random.below(4) == 0 ? "-" : "") + integerDigits + (fractionDigits.isEmpty ? "" : "." + fractionDigits)
            if ChartDecimalText.value(of: Array(text.utf8), from: 0, to: text.utf8.count) != nil { readCount += 1 }
            assertReadAsDoubleReadsIt(text)
        }
        XCTAssertGreaterThan(readCount, 200_000)
    }

    /// The edges: 2^53 and past it, 22 fraction digits and 23, 19 digits and 20, negative zero, and texts that are not such
    /// numbers, which are left to Double.
    func testTheFastPathsEdgesAreReadAsDoubleReadsThemOrLeft() {
        let edges = ["9007199254740991", "9007199254740992", "9007199254740993", "0.9007199254740991", "1.0000000000000000000000",
                     "0.0000000000000000000001", "0.00000000000000000000001", "1234567890123456789", "12345678901234567890", "-0", "-0.0",
                     "0", "0.1", "0.3", "123.456", "1e5", "1.", ".5", "-", "", "1.2.3", "+1", "0x10", " 1"]
        for edge in edges { assertReadAsDoubleReadsIt(edge) }
        XCTAssertNil(ChartDecimalText.value(of: Array("9007199254740993".utf8), from: 0, to: 16))
        XCTAssertNil(ChartDecimalText.value(of: Array("1.".utf8), from: 0, to: 2))
        XCTAssertNil(ChartDecimalText.value(of: Array("1e5".utf8), from: 0, to: 3))
        XCTAssertEqual(ChartDecimalText.value(of: Array("-0".utf8), from: 0, to: 2)?.sign, .minus)
    }
}
