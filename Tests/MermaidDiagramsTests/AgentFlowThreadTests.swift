/**
 * File: AgentFlowThreadTests.swift
 * --------------------------------
 * Layer: Tests
 * Description: Agent flows prepared on twelve threads at once are those prepared alone: the reader's tokens, lists, pair
 *              counts and graph work and the layout's cluster graph live in each thread's scratch arena, and the shape
 *              table and the pair counts' basis are made once for every thread.
 *
 * Authors: Bahey Shalash
 * Version: 0.2
 * Date: 26/11/2026
 */

import Foundation
import XCTest
@testable import MermaidDiagrams
@testable import MermaidDiagramsBenchmark

final class AgentFlowThreadTests: XCTestCase {
    /// Twelve threads prepare the same agent flows at once, each starting at another input, regular and at two narrow
    /// widths: every SVG, narrow SVG and spoken text is the one prepared alone, before the threads start. The inputs are
    /// the documentation examples and Pele's reference inputs, each also kept to ASCII (the reader's byte paths) and with
    /// names beyond ASCII that the grammar reads (its String paths: the Kelvin sign and `K` one node), the hostile
    /// layouts, and texts whose many edges grow the pair counts.
    func testAgentFlowsPreparedOnManyThreadsAtOnceAreThosePreparedAlone() throws {
        let typography = DiagramSceneSamples.typography
        var sources: [String] = []
        for name in ["agentflow-docs", "agentflow-reference"] {
            let corpus = try PeleResults.sources(ofCorpus: name)
            sources += corpus + corpus.map(GraphTextMutations.ascii) + corpus.map { source in source + "\n  x\u{212A} --> xK\n  y\u{E9} --> xK" }
        }
        sources += AgentFlowHostileTexts.all
        sources.append("agentflow-beta\n" + (0..<300).map { index in "  n\(index % 23) --> n\(index % 17)" }.joined(separator: "\n"))
        XCTAssertGreaterThan(sources.count, 700)
        let widths: [CGFloat] = [280, 390]
        let expected = sources.map { source in OutputDigest.Outcome(source: source, typography: typography, narrowColumnWidths: widths).summaryLine }
        let shared = AgentFlowThreadSharedInputs(sources: sources, expected: expected, typography: typography, widths: widths)
        let differences = ThreadSafeCount()
        let matches = ThreadSafeCount()
        DispatchQueue.concurrentPerform(iterations: 12) { thread in
            let count = shared.sources.count
            for step in 0..<count {
                let index = (thread &* 31 &+ step) % count
                let outcome = OutputDigest.Outcome(source: shared.sources[index], typography: shared.typography, narrowColumnWidths: shared.widths)
                if outcome.summaryLine == shared.expected[index] { matches.add() } else { differences.add() }
            }
        }
        XCTAssertEqual(matches.value, 12 * sources.count)
        XCTAssertEqual(differences.value, 0)
    }
}

/// The inputs and expected outcomes the threads share; read only once made.
private final class AgentFlowThreadSharedInputs: @unchecked Sendable {
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
