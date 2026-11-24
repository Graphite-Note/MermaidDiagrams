/**
 * File: DiagramTextThreadTests.swift
 * ----------------------------------
 * Layer: Tests
 * Description: The per-thread text storages hold up when many threads prepare diagrams at once, as Graphite does:
 *              every diagram of the types that do not lay out in layers, read on one thread and prepared on twelve
 *              others while that thread writes on, or read and prepared on each of them, gives the SVG, narrow SVG and
 *              spoken text it gives prepared alone.
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

final class DiagramTextThreadTests: XCTestCase {
    /// The documentation corpora of the types `LayeredLayoutThreadTests` leaves out, most of them heavy in text.
    private static let corpusNames = ["timeline-docs", "mindmap-docs", "c4-docs", "kanban-docs", "sequence-docs", "journey-docs", "xychart-docs",
                                      "block-docs", "treemap-docs", "gantt-docs", "git-docs", "pie-docs", "quadrant-docs", "ishikawa-docs",
                                      "wardley-docs", "eventmodeling-docs", "swimlane-docs", "treeview-docs", "architecture-docs", "cynefin-docs",
                                      "railroad-docs", "venn-docs", "sankey-docs", "packet-docs", "radar-docs", "info-docs"]
    private static let narrowWidth: CGFloat = 280

    /// What a prepared diagram gives: its SVG, its narrow scene's SVG and everything its accessibility says, the summary
    /// made on the thread that reads it.
    private static func outcome(of prepared: PreparedMermaidDiagram) -> String {
        let accessibility = prepared.accessibility
        let narrow = prepared.narrowScene.map { scene in DiagramSVGWriter().document(of: scene, diagramType: prepared.kind.peleName) } ?? "-"
        let spoken = [accessibility.title ?? "-", accessibility.description ?? "-", accessibility.summary.joined(separator: "\u{1}"),
                      accessibility.label, accessibility.value]
        return [prepared.svgDocument(), narrow, spoken.joined(separator: "\u{2}")].map(FowlerNollVoDigest.of).joined(separator: " ")
    }

    private static func prepared(_ diagram: MermaidDiagram, typography: DiagramTypography) -> String {
        do {
            return outcome(of: try MermaidDiagramPreparation.prepare(diagram, typography: typography, narrowestColumnWidth: narrowWidth,
                                                                    now: GanttChartCorpus.now, timeZone: GanttChartCorpus.timeZone))
        } catch {
            return "refused \(error)"
        }
    }

    private static func prepared(source: String, typography: DiagramTypography) -> String {
        do {
            return outcome(of: try MermaidDiagramPreparation.prepare(source: source, typography: typography, narrowestColumnWidth: narrowWidth,
                                                                    now: GanttChartCorpus.now, timeZone: GanttChartCorpus.timeZone))
        } catch {
            return "refused \(error)"
        }
    }

    /// Twelve threads prepare the diagrams this thread read, whose labels lie in this thread's storages, while this
    /// thread, one of the twelve, writes on into them; and each also reads and prepares the same sources itself, each
    /// thread starting at another input: every outcome is the one prepared alone before the threads start.
    func testDiagramsReadOnOneThreadAndPreparedOnManyAreThosePreparedAlone() throws {
        let typography = DiagramSceneSamples.typography
        var sources: [String] = []
        for name in Self.corpusNames { sources += try PeleResults.sources(ofCorpus: name) }
        XCTAssertGreaterThan(sources.count, 250)
        let diagrams = sources.map { source in try? MermaidDiagramReader.read(source, limits: .standard) }
        let expected = sources.map { source in Self.prepared(source: source, typography: typography) }
        for (index, diagram) in diagrams.enumerated() {
            guard let diagram else { continue }
            XCTAssertEqual(Self.prepared(diagram, typography: typography), expected[index], "input \(index) read then prepared")
        }
        let shared = SharedTextInputs(sources: sources, diagrams: diagrams, expected: expected, typography: typography)
        let tally = TextThreadTally()
        DispatchQueue.concurrentPerform(iterations: 12) { thread in
            let count = shared.sources.count
            for step in 0..<count {
                let index = (thread &* 37 &+ step) % count
                if let diagram = shared.diagrams[index] {
                    tally.record(Self.prepared(diagram, typography: shared.typography) == shared.expected[index])
                }
                tally.record(Self.prepared(source: shared.sources[index], typography: shared.typography) == shared.expected[index])
            }
        }
        XCTAssertGreaterThan(tally.matchCount, 12 * sources.count)
        XCTAssertEqual(tally.differenceCount, 0)
    }
}

/// The inputs, diagrams and expected outcomes the threads share; read only once made.
private final class SharedTextInputs: @unchecked Sendable {
    let sources: [String]
    let diagrams: [MermaidDiagram?]
    let expected: [String]
    let typography: DiagramTypography

    init(sources: [String], diagrams: [MermaidDiagram?], expected: [String], typography: DiagramTypography) {
        self.sources = sources
        self.diagrams = diagrams
        self.expected = expected
        self.typography = typography
    }
}

/// How many outcomes the threads found alike and different, counted under a lock.
private final class TextThreadTally: @unchecked Sendable {
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
