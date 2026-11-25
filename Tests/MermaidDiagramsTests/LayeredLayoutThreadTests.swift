/**
 * File: LayeredLayoutThreadTests.swift
 * ------------------------------------
 * Layer: Tests
 * Description: The layered layouts' per-thread scratch arena holds up when many threads prepare diagrams at once, as
 *              Graphite does: every diagram that lays out in layers, prepared on twelve threads together with its
 *              narrow scenes, gives the output it gives prepared alone on one thread.
 *
 * Authors: Bahey Shalash
 * Version: 0.3
 * Date: 25/11/2026
 */

import CoreGraphics
import Foundation
import XCTest
@testable import MermaidDiagrams
@testable import MermaidDiagramsBenchmark

final class LayeredLayoutThreadTests: XCTestCase {
    /// The documentation corpora of every type whose layout runs on the arena, flat and in clusters, and C4's, whose
    /// reading interns its names in a table of its own and whose scene records into the thread's lanes.
    private static let corpusNames = ["flowchart-docs", "state-docs", "class-docs", "er-docs", "requirement-docs", "usecase-docs", "agentflow-docs",
                                      "swimlane-docs", "c4-docs"]

    /// Twelve threads prepare the same inputs at once, each starting at another input, regular and at two narrow
    /// widths (a narrow fitting lays the diagram out again inside the preparation): every SVG, narrow SVG and spoken
    /// text is the one prepared alone, before the threads start.
    func testDiagramsPreparedOnManyThreadsAtOnceAreThosePreparedAlone() throws {
        let typography = DiagramSceneSamples.typography
        var sources: [String] = []
        for name in Self.corpusNames { sources += try PeleResults.sources(ofCorpus: name) }
        // Pele's generated tree and mesh of 50 nodes, whose layouts grow the arena past its first chunks.
        sources += PeleResults.generatedBenchmarkInputs.filter { input in input.name.contains("50 nodes") }.map(\.source)
        // Pele's tree of 500 nodes, whose layout takes the arena past what it keeps between two uses, so that each thread
        // trims its chunks while the others lay out.
        sources += PeleResults.generatedBenchmarkInputs.filter { input in input.name == "tree: 500 nodes" }.map(\.source)
        XCTAssertGreaterThan(sources.count, 250)
        let widths: [CGFloat] = [280, 390]
        let expected = sources.map { source in OutputDigest.Outcome(source: source, typography: typography, narrowColumnWidths: widths).summaryLine }
        let shared = SharedInputs(sources: sources, expected: expected, typography: typography, widths: widths)
        let tally = LayeredThreadTally()
        DispatchQueue.concurrentPerform(iterations: 12) { thread in
            let count = shared.sources.count
            for step in 0..<count {
                let index = (thread &* 53 &+ step) % count
                let outcome = OutputDigest.Outcome(source: shared.sources[index], typography: shared.typography, narrowColumnWidths: shared.widths)
                tally.record(outcome.summaryLine == shared.expected[index])
            }
        }
        XCTAssertEqual(tally.matchCount, 12 * sources.count)
        XCTAssertEqual(tally.differenceCount, 0)
    }
}

/// The inputs and expected outcomes the threads share; read only once made.
private final class SharedInputs: @unchecked Sendable {
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

/// How many outcomes the threads found alike and different, counted under a lock.
private final class LayeredThreadTally: @unchecked Sendable {
    private let lock = NSLock()
    private var matches = 0
    private var differences = 0

    func record(_ isMatch: Bool) {
        lock.lock()
        if isMatch { matches += 1 } else { differences += 1 }
        lock.unlock()
    }

    var matchCount: Int { lock.withLock { matches } }
    var differenceCount: Int { lock.withLock { differences } }
}
