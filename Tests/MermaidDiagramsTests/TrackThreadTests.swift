/**
 * File: TrackThreadTests.swift
 * ----------------------------
 * Layer: Tests
 * Description: Twelve threads prepare the sequence, user journey, timeline, Gantt, kanban, railroad and event modeling
 *              corpora at once, with journeys of many actors and event models of many frames whose short lists turn into
 *              tables and kanban cards whose metadata is read on bytes and by the YAML reader, regular and narrow: every
 *              outcome is the one prepared alone.
 *
 * Authors: Bahey Shalash
 * Version: 0.2
 * Date: 25/11/2026
 */

import XCTest
@testable import MermaidDiagrams
@testable import MermaidDiagramsBenchmark

final class TrackThreadTests: XCTestCase {
    private static let corpusNames = ["sequence-docs", "journey-docs", "timeline-docs", "gantt-docs", "kanban-docs", "railroad-docs", "eventmodeling-docs"]

    func testTracksPreparedOnManyThreadsAtOnceAreThosePreparedAlone() throws {
        let typography = DiagramSceneSamples.typography
        var sources: [String] = []
        for name in Self.corpusNames { sources += try PeleResults.sources(ofCorpus: name) }
        // Past the short lists' lengths: twenty actors, forty frames in a dozen namespaces, thirty participants.
        sources.append("journey\nsection S\n" + (0..<40).map { index in "t\(index): \(index % 5 + 1): A\(index % 20), B\(index % 7)" }.joined(separator: "\n"))
        sources.append("eventmodeling\n" + (1...40).map { frame in "tf \(frame) \(["ui", "cmd", "evt", "rmo"][frame % 4]) N\(frame % 12).E\(frame)" }
            .joined(separator: "\n"))
        sources.append("sequenceDiagram\n" + (0..<90).map { index in "P\(index % 30)->>P\((index * 7) % 30): wrap: m\(index)" }.joined(separator: "\n"))
        // Kanban metadata read on its bytes and by the whole YAML reader, cards of both side by side.
        sources.append("kanban\n  c[C]\n" + (0..<30).map { index in
            index % 3 == 0 ? "    k\(index)[K]@{\n      ticket: T-\(index)\n      priority: Low\n    }"
                : "    k\(index)[K]@{ ticket: T-\(index), assigned: 'a\(index)', priority: \(index % 2 == 0 ? "High" : "[Low]") }"
        }.joined(separator: "\n"))
        XCTAssertGreaterThan(sources.count, 90)
        let widths: [CGFloat] = [280, 390]
        let expected = sources.map { source in OutputDigest.Outcome(source: source, typography: typography, narrowColumnWidths: widths).summaryLine }
        let shared = TrackSharedInputs(sources: sources, expected: expected, typography: typography, widths: widths)
        let tally = TrackThreadTally()
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
private final class TrackSharedInputs: @unchecked Sendable {
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
private final class TrackThreadTally: @unchecked Sendable {
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
