/**
 * File: ChartThreadTests.swift
 * ----------------------------
 * Layer: Tests
 * Description: Charts, block diagrams, Ishikawa diagrams and Wardley maps prepared on many threads at once are those
 *              prepared alone: each thread reads a block diagram in its own scratch arena, keeps each Ishikawa diagram's
 *              and quadrant chart's ranges of its own text, and records every scene into its own lanes.
 *
 * Authors: Bahey Shalash
 * Version: 0.2
 * Date: 25/11/2026
 */

import Foundation
import XCTest
@testable import MermaidDiagrams
@testable import MermaidDiagramsBenchmark

final class ChartThreadTests: XCTestCase {
    private static let corpusNames = ["block-docs", "pie-docs", "radar-docs", "quadrant-docs", "xychart-docs", "sankey-docs", "treemap-docs",
                                      "packet-docs", "venn-docs", "ishikawa-docs", "wardley-docs"]

    /// Twelve threads prepare the same inputs at once, each starting at another input, regular and at two narrow widths:
    /// every SVG, narrow SVG and spoken text is the one prepared alone, before the threads start.
    func testChartsPreparedOnManyThreadsAtOnceAreThosePreparedAlone() throws {
        let typography = DiagramSceneSamples.typography
        var sources: [String] = []
        for name in Self.corpusNames { sources += try PeleResults.sources(ofCorpus: name) }
        // A block diagram large enough to grow the thread's arena past its first chunk while the others read.
        sources.append("block\ncolumns 6\n" + (0..<600).map { index in "b\(index)[\"block \(index)\"] space:\(index % 3)" }.joined(separator: "\n"))
        XCTAssertGreaterThan(sources.count, 70)
        let widths: [CGFloat] = [280, 390]
        let expected = sources.map { source in OutputDigest.Outcome(source: source, typography: typography, narrowColumnWidths: widths).summaryLine }
        let shared = ChartSharedInputs(sources: sources, expected: expected, typography: typography, widths: widths)
        let tally = ChartThreadTally()
        DispatchQueue.concurrentPerform(iterations: 12) { thread in
            let count = shared.sources.count
            for step in 0..<count {
                let index = (thread &* 17 &+ step) % count
                let outcome = OutputDigest.Outcome(source: shared.sources[index], typography: shared.typography, narrowColumnWidths: shared.widths)
                tally.record(outcome.summaryLine == shared.expected[index])
            }
        }
        XCTAssertEqual(tally.matchCount, 12 * sources.count)
        XCTAssertEqual(tally.differenceCount, 0)
    }
}

/// The inputs and expected outcomes the threads share; read only once made.
private final class ChartSharedInputs: @unchecked Sendable {
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
private final class ChartThreadTally: @unchecked Sendable {
    private let lock = NSLock()
    private var matches = 0
    private var differences = 0

    func record(_ isMatch: Bool) {
        lock.lock()
        if isMatch { matches += 1 } else { differences += 1 }
        lock.unlock()
    }

    var matchCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return matches
    }

    var differenceCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return differences
    }
}
