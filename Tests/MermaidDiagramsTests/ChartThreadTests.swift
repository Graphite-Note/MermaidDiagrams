/**
 * File: ChartThreadTests.swift
 * ----------------------------
 * Layer: Tests
 * Description: Charts, block diagrams, Ishikawa diagrams and Wardley maps prepared on many threads at once are those
 *              prepared alone: each thread reads a block diagram in its own scratch arena, keeps each Ishikawa diagram's
 *              and quadrant chart's ranges of its own text, finds each Sankey diagram's names in its own table, makes
 *              its own radar entry lists and Git commit ids, and records every scene into its own lanes.
 *
 * Authors: Bahey Shalash
 * Version: 0.3
 * Date: 25/11/2026
 */

import Foundation
import XCTest
@testable import MermaidDiagrams
@testable import MermaidDiagramsBenchmark

final class ChartThreadTests: XCTestCase {
    private static let corpusNames = ["block-docs", "pie-docs", "radar-docs", "quadrant-docs", "xychart-docs", "sankey-docs", "treemap-docs",
                                      "packet-docs", "venn-docs", "ishikawa-docs", "wardley-docs", "git-docs"]

    /// Twelve threads prepare the same inputs at once, each starting at another input, regular and at two narrow widths:
    /// every SVG, narrow SVG and spoken text is the one prepared alone, before the threads start.
    func testChartsPreparedOnManyThreadsAtOnceAreThosePreparedAlone() throws {
        let typography = DiagramSceneSamples.typography
        var sources: [String] = []
        for name in Self.corpusNames { sources += try PeleResults.sources(ofCorpus: name) }
        // A block diagram large enough to grow the thread's arena past its first chunk while the others read.
        sources.append("block\ncolumns 6\n" + (0..<600).map { index in "b\(index)[\"block \(index)\"] space:\(index % 3)" }.joined(separator: "\n"))
        // Sankey diagrams whose names grow the name table past its first slots, in ASCII and beyond it.
        sources.append("sankey\n" + (0..<80).map { index in "node \(index),node \((index * 7 + 1) % 80),\(index + 1)" }.joined(separator: "\n"))
        sources.append("sankey\n" + (0..<40).map { index in "nœud \(index),\"nœud \(index + 1)\",\(index + 1)" }.joined(separator: "\n"))
        // A radar chart whose curves name more entries than are searched, and a Git graph of made-up ids on many branches.
        sources.append("radar-beta\naxis " + (0..<20).map { index in "a\(index)" }.joined(separator: ", ") + "\ncurve c{"
            + (0..<20).map { index in "a\(19 - index): \(index % 7).5" }.joined(separator: ", ") + "}")
        sources.append("gitGraph\n" + (0..<30).map { index in "branch b\(index)\ncommit\ncommit tag: \"t\(index)\"\n" }.joined())
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
