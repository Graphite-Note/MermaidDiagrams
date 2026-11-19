/**
 * File: EventModelCorpusTests.swift
 * ---------------------------------
 * Layer: Tests
 * Description: Mermaid's event model documentation examples read, laid out across and down a column with their boxes
 *              apart and on the page, and prepared with a narrow scene where they are wider than a column.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 19/11/2026
 */

import XCTest
@testable import MermaidDiagrams
@testable import MermaidDiagramsBenchmark

final class EventModelCorpusTests: XCTestCase {
    private let typography = DiagramTypography(font: DiagramFont(postScriptName: nil, size: 16))

    func testEveryDocumentationExampleIsReadAndLaidOutAcrossAndDownWithItsBoxesApart() throws {
        let examples = try EventModelCorpus.documentationExamples()
        XCTAssertEqual(examples.count, 12)
        for example in examples {
            let diagram = try EventModelReading.diagram(example)
            XCTAssertFalse(diagram.frames.isEmpty, example)
            let across = EventModelLayoutEngine.layout(diagram, typography: typography)
            Self.assertBoxesApart(across, diagram: diagram)
            let down = EventModelLayoutEngine.layout(diagram, typography: typography, columnWidth: 280)
            Self.assertBoxesApart(down, diagram: diagram)
            XCTAssertEqual(across.relations.count, down.relations.count, example)
        }
    }

    func testAnExampleWiderThanTheColumnIsPreparedWithANarrowerSceneDownIt() throws {
        var narrowCount = 0
        for example in try EventModelCorpus.documentationExamples() {
            let prepared = try MermaidDiagramPreparation.prepare(source: example, typography: typography)
            XCTAssertEqual(prepared.kind, .eventModel)
            if let narrow = prepared.narrowScene {
                XCTAssertLessThan(narrow.size.width, prepared.scene.size.width)
                narrowCount += 1
            } else {
                XCTAssertLessThanOrEqual(prepared.scene.size.width, PreparedMermaidDiagram.standardNarrowestColumnWidth, example)
            }
        }
        XCTAssertEqual(narrowCount, 12, "Every example runs across more than 280 points")
    }

    /// No two boxes overlap, nor two cards, and everything is on the page; across, each box is inside its lane's band.
    static func assertBoxesApart(_ layout: EventModelLayout, diagram: EventModelDiagram, file: StaticString = #filePath, line: UInt = #line) {
        let page = CGRect(origin: .zero, size: layout.size).insetBy(dx: -0.001, dy: -0.001)
        let boxes = layout.frames.map(\.frame) + layout.cards.map(\.frame)
        for box in boxes { XCTAssertTrue(page.contains(box), "\(box) on \(layout.size)", file: file, line: line) }
        let byTop = boxes.sorted { first, second in first.minY < second.minY }
        for (index, box) in byTop.enumerated() {
            for other in byTop[(index + 1)...] {
                if other.minY >= box.maxY { break }
                XCTAssertFalse(box.insetBy(dx: 0.5, dy: 0.5).intersects(other.insetBy(dx: 0.5, dy: 0.5)), "\(box) and \(other)", file: file, line: line)
            }
        }
        guard !layout.runsDown else { return }
        for (frame, laidOut) in zip(diagram.frames, layout.frames) {
            XCTAssertTrue(layout.laneBands[frame.laneIndex].contains(laidOut.frame), file: file, line: line)
        }
    }
}
