/**
 * File: FlowchartSpecDifferentialTests.swift
 * ------------------------------------------
 * Layer: Tests
 * Description: Reads every text Mermaid 12.1.0's flowchart parser specs parse (Pele's ports in tests/compat/flowchart)
 *              and compares the flowchart with what Pele's flowchart database made of it.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 19/11/2026
 */

import XCTest
@testable import MermaidDiagrams
@testable import MermaidDiagramsBenchmark

/// `scripts/pele/compat-recorder.ts` runs Pele's ports of Mermaid's flowchart specs (flow-arrows, flow-comments,
/// flow-direction, flow-edges, flow-interactions, flow-lines, flow-md-string, flow-node-data, flow-singlenode, flow-style,
/// flow-text, flow-vertice-chaining, flow, flowDb and subgraph; flow-huge is skipped there as in Pele) and records each
/// text they parse with Pele's result (`pele-flowchart-compat.json`). Pele passes these specs, so its result stands for
/// what they assert; a text whose reading differs must be listed in PeleKnownDifferences.md with why.
final class FlowchartSpecDifferentialTests: XCTestCase {
    func testEverySpecTextIsReadAsPeleReadsItOrListed() throws {
        let known = try PeleKnownDifferenceList()
        let texts = try PeleResults.flowchartSpecTexts()
        XCTAssertGreaterThan(texts.count, 900)
        var agreeing = 0
        for (index, text) in texts.enumerated() {
            let found = FlowchartSpecComparison.differences(text)
            if found.isEmpty { agreeing += 1 }
            XCTAssertEqual(Set(found), known.specTexts[index] ?? [], "\(index) (\(text.spec), \(text.test)): \(text.source.debugDescription)")
        }
        XCTAssertGreaterThan(agreeing, 860)
    }

    func testEverySpecFileIsRecorded() throws {
        let specs = Set(try PeleResults.flowchartSpecTexts().map(\.spec))
        XCTAssertEqual(specs, ["flow-arrows.spec.js", "flow-comments.spec.js", "flow-direction.spec.js", "flow-edges.spec.js", "flow-interactions.spec.js",
                               "flow-lines.spec.js", "flow-md-string.spec.js", "flow-node-data.spec.js", "flow-singlenode.spec.js", "flow-style.spec.js",
                               "flow-text.spec.js", "flow-vertice-chaining.spec.js", "flow.spec.js", "flowDb.spec.ts", "subgraph.spec.js"])
    }
}
