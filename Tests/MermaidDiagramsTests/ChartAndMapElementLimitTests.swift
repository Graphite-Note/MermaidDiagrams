/**
 * File: ChartAndMapElementLimitTests.swift
 * ----------------------------------------
 * Layer: Tests
 * Description: The charts' and the maps' preparations record their scenes under the limits they are given: a diagram
 *              whose one lane holds more elements than small limits allow is refused as having too many path elements,
 *              instead of being drawn with the lane emptied, and the same diagram prepared under the standard limits is
 *              drawn whole. Packet fields and XY chart bars stand for the charts, mindmap node outlines for the maps.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 25/11/2026
 */

import XCTest
@testable import MermaidDiagrams

final class ChartAndMapElementLimitTests: XCTestCase {
    private let typography = DiagramTypography(font: DiagramFont(postScriptName: nil, size: 16))
    /// Room to read the large diagrams below, which the standard limits refuse by their size.
    private let readingLimits = MermaidDiagramLimits(maximumSourceBytes: 1_000_000, maximumNodeCount: 100_000, maximumEdgeCount: 100_000,
                                                     maximumLayoutPointCount: 1_000_000)
    /// Limits whose element limit is the smallest a lane has (2¹⁶ elements), the drawing side left large enough.
    private let smallLimits = MermaidDiagramLimits(maximumSourceBytes: 1_000_000, maximumNodeCount: 1, maximumEdgeCount: 1, maximumLayoutPointCount: 1,
                                                   maximumDrawingSideLength: 1_000_000)
    /// The standard limits with the drawing side left large enough.
    private let wideStandardLimits = MermaidDiagramLimits(maximumSourceBytes: 1_000_000, maximumNodeCount: 5_000, maximumEdgeCount: 5_000,
                                                          maximumLayoutPointCount: 50_000, maximumDrawingSideLength: 1_000_000)

    /// Reads `source` under the reading limits, then prepares it under the small limits, expecting a refusal for too
    /// many path elements, and under the standard ones, expecting a whole scene.
    private func assertRefusedOnlyUnderSmallLimits(_ source: String, file: StaticString = #filePath, line: UInt = #line) throws {
        let diagram = try MermaidDiagramReader.read(source, limits: readingLimits)
        let limit = DiagramSceneWorkspace.elementLimit(for: smallLimits)
        XCTAssertEqual(limit, 1 << 16, file: file, line: line)
        XCTAssertThrowsError(try MermaidDiagramPreparation.prepare(diagram, typography: typography, limits: smallLimits, narrowestColumnWidth: nil),
                             file: file, line: line) { error in
            XCTAssertEqual(error as? MermaidDiagramPreparationFailure, .tooManyPathElements(limit: limit), file: file, line: line)
        }
        let prepared = try MermaidDiagramPreparation.prepare(diagram, typography: typography, limits: wideStandardLimits, narrowestColumnWidth: nil)
        XCTAssertNil(prepared.scene.exceededPathElementLimit, file: file, line: line)
    }

    /// Every field's box is one lane of rounded rectangles: 7,000 of them hold about 70,000 elements.
    func testAPacketPastTheElementLimitIsRefusedUnderTheLimitsItIsPreparedWith() throws {
        let fields = (0..<7_000).map { bit in "\(bit)-\(bit): \"f\"" }.joined(separator: "\n")
        try assertRefusedOnlyUnderSmallLimits("packet\n" + fields)
    }

    /// A bar series is one lane of rectangles: 14,000 of them hold about 70,000 elements.
    func testAnXYChartPastTheElementLimitIsRefusedUnderTheLimitsItIsPreparedWith() throws {
        let values = (0..<14_000).map { index in String(index % 7) }.joined(separator: ",")
        try assertRefusedOnlyUnderSmallLimits("xychart-beta\nbar [" + values + "]")
    }

    /// A branch's node outlines are one lane: 7,000 nodes under one category hold about 70,000 elements.
    func testAMindmapPastTheElementLimitIsRefusedUnderTheLimitsItIsPreparedWith() throws {
        let leaves = (0..<7_000).map { index in "      [n\(index)]" }.joined(separator: "\n")
        try assertRefusedOnlyUnderSmallLimits("mindmap\n  root\n    [branch]\n" + leaves)
    }
}
