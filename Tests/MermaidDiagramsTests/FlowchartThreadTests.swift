/**
 * File: FlowchartThreadTests.swift
 * --------------------------------
 * Layer: Tests
 * Description: Flowcharts, swimlanes and agent flows prepared on twelve threads at once, regular and narrow, give every
 *              SVG, narrow SVG and spoken text they give prepared alone: their layouts keep texts placed in the
 *              storages of the thread that measured them (DiagramPlacedTextStorages) and records in one block made per
 *              layout, which other threads then read.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 26/11/2026
 */

import CoreGraphics
import Foundation
import XCTest
@testable import MermaidDiagrams
@testable import MermaidDiagramsBenchmark

final class FlowchartThreadTests: XCTestCase {
    func testFlowchartsPreparedOnManyThreadsAtOnceAreThosePreparedAlone() throws {
        let typography = DiagramSceneSamples.typography
        var sources: [String] = []
        for (name, corpus) in try OutputDigest.corpora() where name.contains("flowchart") || name.contains("swimlane") || name.contains("agentflow") {
            sources += corpus + corpus.map(GraphTextMutations.ascii)
        }
        // Random flowcharts with styles, icons and loops, and generated ones whose long texts are written in storages of
        // their own between short ones, so that a layout keeps texts of several storages.
        var texts = FlowchartRandomTexts(seed: 0x7_4EAD)
        sources += (0..<60).map { index in texts.text(statementCount: 4 + index % 30) }
        let longText = String(repeating: "word ", count: 1_000)
        var alternating = "flowchart LR\n"
        for index in 0..<16 { alternating += index % 2 == 0 ? "  n\(index)[\"\(longText)\(index)\"] -->|\(longText)| n\(index + 1)\n" : "  n\(index) -->|s| n\(index + 1)\n" }
        sources.append(alternating)
        sources.append(FlowchartCorpus.tree(nodeCount: 200))
        XCTAssertGreaterThan(sources.count, 250)
        let widths: [CGFloat] = [280, 390]
        let expected = sources.map { source in OutputDigest.Outcome(source: source, typography: typography, narrowColumnWidths: widths).summaryLine }
        let shared = FlowchartThreadSharedInputs(sources: sources, expected: expected, typography: typography, widths: widths)
        let differences = ThreadSafeCount()
        let matches = ThreadSafeCount()
        DispatchQueue.concurrentPerform(iterations: 12) { thread in
            let count = shared.sources.count
            for step in 0..<count {
                let index = (thread &* 23 &+ step) % count
                let outcome = OutputDigest.Outcome(source: shared.sources[index], typography: shared.typography, narrowColumnWidths: shared.widths)
                if outcome.summaryLine == shared.expected[index] { matches.add() } else { differences.add() }
            }
        }
        XCTAssertEqual(matches.value, 12 * sources.count)
        XCTAssertEqual(differences.value, 0)
    }
}

/// The inputs and expected outcomes the threads share; read only once made.
private final class FlowchartThreadSharedInputs: @unchecked Sendable {
    let sources: [String]
    let expected: [String]
    let typography: DiagramTypography
    let widths: [CGFloat]

    init(sources: [String], expected: [String], typography: DiagramTypography, widths: [CGFloat]) {
        self.sources = sources
        self.expected = expected
        self.typography = typography
        self.widths = widths
    }
}
