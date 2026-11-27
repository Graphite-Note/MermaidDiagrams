/**
 * File: GraphFamilyThreadTests.swift
 * ----------------------------------
 * Layer: Tests
 * Description: State, class, entity relationship and requirement diagrams prepared on twelve threads at once are those
 *              prepared alone: each reading borrows its text's bytes and interns its names in its own table, and the
 *              label decoder's Markdown pass keeps no state between threads.
 *
 * Authors: Bahey Shalash
 * Version: 0.3
 * Date: 26/11/2026
 */

import Foundation
import XCTest
@testable import MermaidDiagrams
@testable import MermaidDiagramsBenchmark

final class GraphFamilyThreadTests: XCTestCase {
    private static let corpusNames = ["state-docs", "class-docs", "er-docs", "requirement-docs"]

    /// Twelve threads prepare the same inputs at once, each starting at another input, regular and at two narrow widths:
    /// every SVG, narrow SVG and spoken text is the one prepared alone, before the threads start. The inputs are the
    /// four corpora, each also kept to ASCII (the readers' byte paths) and with a name beyond ASCII (their String
    /// paths), a state machine large enough to grow its name table, and random and generated requirement and entity
    /// relationship diagrams.
    func testGraphDiagramsPreparedOnManyThreadsAtOnceAreThosePreparedAlone() throws {
        let typography = DiagramSceneSamples.typography
        var sources: [String] = []
        for name in Self.corpusNames {
            let corpus = try PeleResults.sources(ofCorpus: name)
            sources += corpus + corpus.map(GraphTextMutations.ascii) + corpus.map { source in source + "\n%% \u{E9}" }
        }
        sources.append(StateDiagramCorpus.machine(stateCount: 300, extraTransitionCount: 150))
        // Random requirement diagrams, whose names and values take the flat Markdown measuring (underscores inside words
        // among them), and generated ones with many boxes, whose layouts keep many measured texts.
        var requirementTexts = RequirementRandomTexts(seed: 0x7E_4D)
        sources += (0..<60).map { _ in requirementTexts.text(statementCount: 22) }
        sources.append(RequirementCorpus.generated(requirementCount: 40, direction: "LR"))
        // Random entity relationship diagrams, groups, loops and attribute rows among them, whose readings and layouts work
        // in each thread's lists and arena, and a schema large enough to grow them.
        var entityRelationshipTexts = EntityRelationshipRandomTexts(seed: 0xE2_7D)
        sources += (0..<60).map { _ in entityRelationshipTexts.text(statementCount: 22) }
        sources.append(EntityRelationshipCorpus.schema(entityCount: 120))
        XCTAssertGreaterThan(sources.count, 370)
        let widths: [CGFloat] = [280, 390]
        let expected = sources.map { source in OutputDigest.Outcome(source: source, typography: typography, narrowColumnWidths: widths).summaryLine }
        let shared = GraphThreadSharedInputs(sources: sources, expected: expected, typography: typography, widths: widths)
        let differences = ThreadSafeCount()
        let matches = ThreadSafeCount()
        DispatchQueue.concurrentPerform(iterations: 12) { thread in
            let count = shared.sources.count
            for step in 0..<count {
                let index = (thread &* 17 &+ step) % count
                let outcome = OutputDigest.Outcome(source: shared.sources[index], typography: shared.typography, narrowColumnWidths: shared.widths)
                if outcome.summaryLine == shared.expected[index] { matches.add() } else { differences.add() }
            }
        }
        XCTAssertEqual(matches.value, 12 * sources.count)
        XCTAssertEqual(differences.value, 0)
    }
}

/// The inputs and expected outcomes the threads share; read only once made.
private final class GraphThreadSharedInputs: @unchecked Sendable {
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
