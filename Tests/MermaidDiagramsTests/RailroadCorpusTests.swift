/**
 * File: RailroadCorpusTests.swift
 * -------------------------------
 * Layer: Tests
 * Description: Mermaid's railroad documentation examples, in the four notations, read and laid out with their boxes
 *              apart and on the page, regular and tight, and the benchmark's generated grammars.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 19/11/2026
 */

import XCTest
@testable import MermaidDiagrams
@testable import MermaidDiagramsBenchmark

final class RailroadCorpusTests: XCTestCase {
    private let typography = DiagramTypography(font: DiagramFont(postScriptName: nil, size: 16))

    func testEveryDocumentationExampleIsReadInItsNotationAndLaidOutWithItsBoxesApart() throws {
        let examples = try RailroadCorpus.documentationExamples()
        XCTAssertEqual(examples.count, 14)
        var notations: [RailroadNotation: Int] = [:]
        for example in examples {
            let diagram = try RailroadReading.diagram(example)
            notations[diagram.notation, default: 0] += 1
            XCTAssertFalse(diagram.rules.isEmpty, example)
            for layout in [RailroadLayoutEngine.layout(diagram, typography: typography),
                           RailroadLayoutEngine.layout(diagram, typography: typography, columnWidth: 280)] {
                XCTAssertEqual(layout.rules.count, diagram.rules.count)
                Self.assertBoxesApart(layout)
            }
        }
        XCTAssertEqual(Set(notations.keys), Set(RailroadNotation.allCases), "\(notations)")
    }

    func testTheGeneratedGrammarsAreLaidOutWithTheirBoxesApart() throws {
        for ruleCount in [12, 200] {
            let diagram = try RailroadReading.diagram(RailroadCorpus.generated(ruleCount: ruleCount))
            XCTAssertEqual(diagram.rules.count, ruleCount)
            Self.assertBoxesApart(RailroadLayoutEngine.layout(diagram, typography: typography))
        }
    }

    /// No two boxes of the diagram overlap, every box and track point is on the page, and each rule's track starts at
    /// its first dot and ends at its last.
    static func assertBoxesApart(_ layout: RailroadLayout, file: StaticString = #filePath, line: UInt = #line) {
        let page = CGRect(origin: .zero, size: layout.size).insetBy(dx: -0.001, dy: -0.001)
        let boxes = layout.rules.flatMap(\.boxes).map(\.frame).sorted { first, second in first.minY < second.minY }
        for (index, box) in boxes.enumerated() {
            XCTAssertTrue(page.contains(box), "\(box) on \(layout.size)", file: file, line: line)
            for other in boxes[(index + 1)...] {
                if other.minY >= box.maxY { break }
                XCTAssertFalse(box.insetBy(dx: 0.5, dy: 0.5).intersects(other.insetBy(dx: 0.5, dy: 0.5)), "\(box) and \(other)", file: file, line: line)
            }
        }
        for rule in layout.rules {
            let points = rule.track.flatMap { path in [path.start] + path.segments.map { segment in
                switch segment {
                case .line(let end), .curve(let end, _, _): end
                }
            } }
            XCTAssertTrue(points.allSatisfy { point in page.contains(point) }, file: file, line: line)
            guard let first = rule.markerCenters.first, let last = rule.markerCenters.last else { continue }
            XCTAssertEqual(points.map(\.x).min() ?? 0, first.x + layout.markerRadius, accuracy: 0.001, file: file, line: line)
            XCTAssertEqual(points.map(\.x).max() ?? 0, last.x - layout.markerRadius, accuracy: 0.001, file: file, line: line)
        }
    }
}
