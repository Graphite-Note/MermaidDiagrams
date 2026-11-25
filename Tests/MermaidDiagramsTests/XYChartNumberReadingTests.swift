/**
 * File: XYChartNumberReadingTests.swift
 * -------------------------------------
 * Layer: Tests
 * Description: An XY chart's numbers read on their bytes are, bit for bit, the doubles their text reads as: every
 *              number of the corpora's XY charts and 200,000 random numbers of every length, sign and fraction, those
 *              past the exact fast path read through their text.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 24/11/2026
 */

import XCTest
@testable import MermaidDiagrams

final class XYChartNumberReadingTests: XCTestCase {
    private func assertReadAsText(_ text: String, file: StaticString = #filePath, line: UInt = #line) {
        let bytes = Array(text.utf8)
        let read = XYChartNumberReading.number(in: bytes, from: 0, to: bytes.count)
        XCTAssertEqual(read?.bitPattern, Double(text)?.bitPattern, text, file: file, line: line)
    }

    func testRandomNumbersAreReadAsTheirText() {
        var state: UInt64 = 0x0A11_C4A7
        func next(_ bound: Int) -> Int {
            state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            return Int((state >> 33) % UInt64(bound))
        }
        func digits(_ count: Int) -> String { String((0..<count).map { _ in Character(String(next(10))) }) }
        for _ in 0..<200_000 {
            let sign = ["", "", "-", "+"][next(4)]
            let whole = next(6) == 0 ? "" : digits(1 + next(24))
            let fraction = whole.isEmpty || next(2) == 0 ? "." + digits(1 + next(26)) : ""
            assertReadAsText(sign + whole + fraction)
        }
        for text in ["0", "-0", "+0", "-0.0", ".5", "-.5", "9007199254740992", "9007199254740993", "900719925474099.1", "0.0000000000000000000001",
                     "0.00000000000000000000001", "1" + String(repeating: "0", count: 30), "123456789012345678901234567890.5"] {
            assertReadAsText(text)
        }
    }

    func testTheCorporaNumbersAreReadAsTheirText() throws {
        var compared = 0
        for source in try ChartReadingEquivalence.corpusSources(keywords: ["xychart", "xychart-beta"]) {
            var scalars = source.unicodeScalars.makeIterator()
            var number = ""
            while let scalar = scalars.next() {
                if CharacterSet.decimalDigits.contains(scalar) && scalar.isASCII || (scalar == "." && !number.isEmpty) || (scalar == "-" && number.isEmpty) {
                    number.unicodeScalars.append(scalar)
                    continue
                }
                if number.contains(where: \.isNumber) {
                    assertReadAsText(number)
                    compared += 1
                }
                number = ""
            }
        }
        XCTAssertGreaterThan(compared, 50)
    }
}
