/**
 * File: MermaidConfigurationThreadTests.swift
 * -------------------------------------------
 * Layer: Tests
 * Description: Front matter read in place into a tree, directives read once per reading and kept on the reading's own
 *              cursor, theme colors and styles hold up when many threads prepare diagrams at once, as Graphite does:
 *              every configured or styled input, prepared on twelve threads together, gives the output it gives
 *              prepared alone on one thread.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 24/11/2026
 */

import CoreGraphics
import Foundation
import XCTest
@testable import MermaidDiagrams
@testable import MermaidDiagramsBenchmark

final class MermaidConfigurationThreadTests: XCTestCase {
    func testConfiguredDiagramsPreparedOnManyThreadsAtOnceAreThosePreparedAlone() throws {
        let typography = DiagramSceneSamples.typography
        let sources = try PeleResults.sources(ofCorpus: "configured-docs") + PeleResults.sources(ofCorpus: "directive-docs")
        XCTAssertGreaterThan(sources.count, 200)
        let widths: [CGFloat] = [280]
        let expected = sources.map { source in OutputDigest.Outcome(source: source, typography: typography, narrowColumnWidths: widths).summaryLine }
        let shared = ConfiguredInputs(sources: sources, expected: expected, typography: typography, widths: widths)
        let tally = ConfigurationThreadTally()
        DispatchQueue.concurrentPerform(iterations: 12) { thread in
            let count = shared.sources.count
            for step in 0..<count {
                let index = (thread &* 31 &+ step) % count
                let outcome = OutputDigest.Outcome(source: shared.sources[index], typography: shared.typography, narrowColumnWidths: shared.widths)
                tally.record(outcome.summaryLine == shared.expected[index])
            }
        }
        XCTAssertEqual(tally.matchCount, 12 * sources.count)
        XCTAssertEqual(tally.differenceCount, 0)
    }
}

/// The inputs and expected outcomes the threads share; read only once made.
private final class ConfiguredInputs: @unchecked Sendable {
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
private final class ConfigurationThreadTally: @unchecked Sendable {
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
