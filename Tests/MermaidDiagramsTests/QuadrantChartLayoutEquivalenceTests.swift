/**
 * File: QuadrantChartLayoutEquivalenceTests.swift
 * -----------------------------------------------
 * Layer: Tests
 * Description: The quadrant chart layout, its point texts placed against boxes whose edges are read once, gives
 *              exactly the layout 0.7.0 gave, at Graphite's narrow widths too, on every corpus and spec text and their
 *              changes, random charts of crowded, styled, classed and labelled points, and charts past the 300 points
 *              whose texts are not kept apart.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 26/11/2026
 */

import XCTest
@testable import MermaidDiagrams

final class QuadrantChartLayoutEquivalenceTests: XCTestCase {
    private static let widths: [CGFloat?] = [nil, 600, 390, 280]

    @discardableResult
    private func assertLaidOutAsTheReference(_ source: String, file: StaticString = #filePath, line: UInt = #line) -> Bool {
        guard source.utf8.count <= MermaidDiagramLimits.standard.maximumSourceBytes,
              case .quadrantChart(let chart)? = try? MermaidDiagramReader.read(source, limits: .standard) else { return false }
        let typography = DiagramSceneSamples.typography
        for width in Self.widths {
            let laidOut = QuadrantChartLayoutEngine.layout(chart, typography: typography, availableWidth: width)
            let expected = ReferenceQuadrantChartLayoutEngine.layout(chart, quadrantText: typography.nodeText, axisText: typography.edgeText,
                                                                     pointText: typography.axisText, titleText: typography.boldNodeText,
                                                                     font: typography.font, availableWidth: width,
                                                                     sizedText: { size, isBold in typography.measurer(ofSize: size, isBold: isBold) })
            XCTAssertEqual(laidOut, expected, "\(String(describing: width)): \(source)", file: file, line: line)
        }
        return true
    }

    func testEveryTextAndItsChangesAreLaidOutAsTheFrozenEngineLaysThemOut() throws {
        let tokens = ["Point A: [0.3, 0.6]\n", "B: [0.31, 0.61] radius: 12\n", "C:::cls: [0.5, 0.5]\n", "classDef cls color: #f00, stroke-width: 3px\n",
                      "quadrant-1 Grow\n", "x-axis Low --> High\n", "y-axis Bottom\n", "title T\n", "\"quoted **label**\": [0.9, 0.1]\n", "\n"]
        let texts = MapReadingEquivalence.texts(readAs: .quadrantChart, among: try MapReadingEquivalence.everyText(), mutationCount: 200, tokens: tokens,
                                                seed: 0x0_0AD_1A70)
        var comparedCount = 0
        for text in texts where assertLaidOutAsTheReference(text) { comparedCount += 1 }
        XCTAssertGreaterThan(comparedCount, 200)
    }

    func testRandomCrowdedChartsAreLaidOutAsTheFrozenEngineLaysThemOut() {
        for text in Self.randomCharts(count: 400, seed: 0x0_0AD_1A71, largestPointCount: 40) { assertLaidOutAsTheReference(text) }
    }

    /// Past 300 points no text is kept apart from the others; just under, every one is.
    func testChartsAroundTheCarefulLimitAreLaidOutAsTheFrozenEngineLaysThemOut() {
        for count in [299, 300, 301, 420] {
            var text = "quadrantChart\nquadrant-1 One\nquadrant-2 Two\n"
            for index in 0..<count { text += "P\(index): [0.\(String(format: "%02d", index % 97 + 1)), 0.\(String(format: "%02d", (index * 37) % 97 + 1))]\n" }
            XCTAssertTrue(assertLaidOutAsTheReference(text), "\(count) points")
        }
    }

    /// Random charts: titles, axes and quadrants' texts or none, points crowded together or spread, with labels long and
    /// empty, styles (radius, color, stroke color and width) and classes.
    private static func randomCharts(count: Int, seed: UInt64, largestPointCount: Int) -> [String] {
        var random = MapReadingMutations(seed: seed, tokens: [])
        let labels = ["A", "Point", "A much longer point label that wraps", "\"\"", "é café", "x<br>y", "\"**bold**\"", "dup", "dup"]
        let styles = ["", "", " radius: 2", " radius: 30", " color: #ff0000", " stroke-color: #00f, stroke-width: 4px", " radius: 0"]
        return (0..<count).map { index in
            var text = "quadrantChart\n"
            if random.below(2) == 0 { text += "title Chart \(index)\n" }
            if random.below(2) == 0 { text += "x-axis Low --> High\n" } else if random.below(2) == 0 { text += "x-axis Only low\n" }
            if random.below(2) == 0 { text += "y-axis Bottom --> Top\n" }
            for quadrant in 1...4 where random.below(3) != 0 { text += "quadrant-\(quadrant) Quadrant \(quadrant)\n" }
            if random.below(3) == 0 { text += "classDef hot color: #f60, radius: 9\n" }
            let isCrowded = random.below(2) == 0
            for _ in 0..<random.below(largestPointCount) {
                let x = isCrowded ? 0.45 + Double(random.below(10)) / 100 : Double(random.below(101)) / 100
                let y = isCrowded ? 0.45 + Double(random.below(10)) / 100 : Double(random.below(101)) / 100
                let label = labels[random.below(labels.count)]
                let className = random.below(4) == 0 ? ":::hot" : ""
                text += "\(label)\(className): [\(x), \(y)]\(styles[random.below(styles.count)])\n"
            }
            return text
        }
    }
}
