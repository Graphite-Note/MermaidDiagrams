/**
 * File: FlowchartLayoutEquivalenceTests.swift
 * -------------------------------------------
 * Layer: Tests
 * Description: Every flowchart of every corpus, Pele's examples, trees, meshes, groups and random flowcharts laid out by
 *              the flowchart layout and by the 0.7.0 engine kept as the reference, with Pele's gaps, its tight gaps and
 *              fitted to each narrow column, alike to the bit.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 24/11/2026
 */

import CoreGraphics
import XCTest
@testable import MermaidDiagrams
@testable import MermaidDiagramsBenchmark

final class FlowchartLayoutEquivalenceTests: XCTestCase {
    private static var typography: DiagramTypography { DiagramSceneSamples.typography }

    /// Every flowchart the corpora hold (each digest input read as a flowchart, Pele's documentation examples), laid
    /// out every way Graphite lays one out.
    func testEveryFlowchartOfTheCorporaMatchesTheReferenceBitForBit() throws {
        var sources = try OutputDigest.corpora().flatMap(\.sources)
        sources += try FlowchartCorpus.documentationExamples()
        var flowchartCount = 0
        var mismatches = 0
        for source in sources {
            guard case .flowchart(let diagram)? = try? MermaidDiagramReader.read(source, limits: .standard) else { continue }
            flowchartCount += 1
            if let difference = Self.firstDifference(diagram, limits: .standard) {
                mismatches += 1
                if mismatches <= 5 { XCTFail("\(difference) differs for:\n\(source.prefix(400))") }
            }
        }
        XCTAssertGreaterThan(flowchartCount, 280)
        XCTAssertEqual(mismatches, 0)
    }

    /// Pele's generated trees and meshes, and groups side by side, each way.
    func testTreesMeshesAndGroupsMatchTheReferenceBitForBit() throws {
        let sources = [FlowchartCorpus.tree(nodeCount: 50), FlowchartCorpus.mesh(nodeCount: 50, extraEdgeCount: 20), FlowchartCorpus.tree(nodeCount: 500),
                       FlowchartCorpus.mesh(nodeCount: 200, extraEdgeCount: 80), FlowchartCorpus.groups(pairCount: 6, nodesPerGroup: 4),
                       FlowchartCorpus.groups(pairCount: 30, nodesPerGroup: 3), FlowchartCorpus.sevenNodeFlowchart, FlowchartCorpus.fourteenShapesInARow]
        for source in sources {
            let diagram = try FlowchartReading.flowchart(source)
            XCTAssertNil(Self.firstDifference(diagram, limits: .standard), String(source.prefix(200)))
        }
    }

    /// Random flowcharts: groups inside groups, links of every kind, labels, loops, collapsed groups, icons, styles.
    func testRandomFlowchartsMatchTheReferenceBitForBit() {
        var texts = FlowchartRandomTexts(seed: 0xF10_C4A7)
        var flowchartCount = 0
        for index in 0..<1_000 {
            let source = texts.text(statementCount: 24)
            guard case .flowchart(let diagram)? = try? MermaidDiagramReader.read(source, limits: .standard) else { continue }
            flowchartCount += 1
            if let difference = Self.firstDifference(diagram, limits: .standard) { XCTFail("random flowchart \(index): \(difference) differs for:\n\(source)") }
        }
        XCTAssertGreaterThan(flowchartCount, 380)
    }

    /// Budgets of layout points too small for some of the corpora's flowcharts: both refuse the same ones alike.
    func testSmallLayoutBudgetsAreRefusedAlike() throws {
        var limits = MermaidDiagramLimits.standard
        for budget in [1, 3, 8, 20] {
            limits.maximumLayoutPointCount = budget
            for source in try FlowchartCorpus.documentationExamples() {
                guard case .flowchart(let diagram)? = try? MermaidDiagramReader.read(source, limits: .standard) else { continue }
                XCTAssertNil(Self.firstDifference(diagram, limits: limits), "budget \(budget):\n\(source.prefix(300))")
            }
        }
    }

    /// The first way of laying `diagram` out whose layout differs from the reference's, or nil.
    static func firstDifference(_ diagram: FlowchartDiagram, limits: MermaidDiagramLimits) -> String? {
        let typography = Self.typography
        for spacing in [DiagramSpacing.standard, .compact] {
            let laidOut = FlowchartLayoutBits { try FlowchartLayoutEngine.layout(diagram, typography: typography, limits: limits, spacing: spacing) }
            let reference = FlowchartLayoutBits { try ReferenceFlowchartLayoutEngine.layout(diagram, typography: typography, limits: limits, spacing: spacing) }
            if laidOut != reference { return "the layout with \(spacing) gaps" }
        }
        for width in OutputDigest.narrowColumnWidths {
            let laidOut = FlowchartLayoutBits { try FlowchartLayoutEngine.layout(diagram, typography: typography, limits: limits, availableWidth: width) }
            let reference = FlowchartLayoutBits {
                try ReferenceFlowchartLayoutEngine.layout(diagram, typography: typography, limits: limits, availableWidth: width)
            }
            if laidOut != reference { return "the layout \(width) points wide" }
        }
        return nil
    }
}
