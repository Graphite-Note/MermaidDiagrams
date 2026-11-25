/**
 * File: UseCaseTextMeasurersTests.swift
 * -------------------------------------
 * Layer: Tests
 * Description: A use case diagram whose styles set many font sizes, bold and italic, is laid out as the 0.7.0 engine
 *              lays it out, its measurers each made once whether found in the short list or by their hash.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 25/11/2026
 */

import CoreGraphics
import XCTest
@testable import MermaidDiagrams
@testable import MermaidDiagramsBenchmark

final class UseCaseTextMeasurersTests: XCTestCase {
    /// Use cases each in a font size of its own, some bold or italic, related in a chain.
    private func manySizedSource(useCaseCount: Int) -> String {
        var lines = ["usecase-beta", "actor Person"]
        for index in 0..<useCaseCount {
            lines.append("U\(index)(\"case \(index)\")")
            let weight = index % 3 == 0 ? ",font-weight:bold" : index % 3 == 1 ? ",font-style:italic" : ""
            lines.append("style U\(index) font-size:\(10 + Double(index) / 4)px\(weight)")
        }
        lines.append("Person --> U0")
        for index in 1..<useCaseCount { lines.append("U\(index - 1) --> U\(index)") }
        return lines.joined(separator: "\n")
    }

    func testManyFontSizesAreLaidOutAsTheReferenceLaysThemOut() throws {
        for useCaseCount in [3, 12, 60] {
            let source = manySizedSource(useCaseCount: useCaseCount)
            guard case .useCase(let diagram) = try MermaidDiagramReader.read(source, limits: .standard) else { return XCTFail("not a use case diagram") }
            XCTAssertNil(UseCaseLayoutEquivalenceTests.firstDifference(diagram, limits: .standard), "\(useCaseCount) use cases")
        }
    }

    /// Each size, weight and slant is made once, past the short list too, and found again by its hash.
    func testEachMeasurerIsMadeOnce() {
        var makings: [String] = []
        var measurers = UseCaseTextMeasurers(font: DiagramSceneSamples.typography.font) { size, isBold, isItalic in
            makings.append("\(size) \(isBold) \(isItalic)")
            return DiagramSceneSamples.typography.measurer(size: size, isBold: isBold, isItalic: isItalic)
        }
        let sizes = (0..<40).map { index in CGFloat(10 + index) }
        for _ in 0..<3 {
            for size in sizes {
                _ = measurers.measurer(size: size)
                _ = measurers.measurer(size: size, isBold: true)
                _ = measurers.measurer(size: size, isItalic: true)
            }
        }
        XCTAssertGreaterThan(sizes.count * 3, UseCaseTextMeasurers<CoreTextDiagramTextMeasurer>.listedMeasurerCount)
        XCTAssertEqual(makings.count, sizes.count * 3)
        XCTAssertEqual(Set(makings).count, sizes.count * 3)
        XCTAssertEqual(measurers.madeCount, sizes.count * 3)
    }
}
