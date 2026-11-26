/**
 * File: StateClassReadingThreadTests.swift
 * ----------------------------------------
 * Layer: Tests
 * Description: State and class diagrams read and prepared on twelve threads at once are those prepared alone, while
 *              each thread's reading lists (GraphDiagramReadingScratch) are filled and emptied by readings of every
 *              size, ASCII and not, some of which throw.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 26/11/2026
 */

import Foundation
import XCTest
@testable import MermaidDiagrams
@testable import MermaidDiagramsBenchmark

final class StateClassReadingThreadTests: XCTestCase {
    /// Twelve threads each read and prepare every input, starting at another one: the corpora's state and class diagrams,
    /// kept to ASCII and with a name beyond ASCII, random ones with descriptions, members and annotations written out of
    /// order, a state machine and a class hierarchy large enough to grow the lists past their first room, and texts that
    /// throw while read. Each outcome is the one prepared alone, before the threads start.
    func testStateAndClassDiagramsReadOnManyThreadsAtOnceAreThoseReadAlone() throws {
        let typography = DiagramSceneSamples.typography
        var sources: [String] = []
        for name in ["state-docs", "class-docs"] {
            let corpus = try PeleResults.sources(ofCorpus: name)
            sources += corpus + corpus.map(GraphTextMutations.ascii) + corpus.map { source in source + "\n%% \u{E9}" }
        }
        var stateTexts = StateRandomTexts(seed: 0x57A7E)
        var classTexts = ClassRandomTexts(seed: 0xC1A55)
        sources += (0..<80).map { _ in stateTexts.text(statementCount: 24) } + (0..<80).map { _ in classTexts.text(statementCount: 24) }
        sources.append(StateDiagramCorpus.machine(stateCount: 600, extraTransitionCount: 300))
        sources.append("classDiagram\n" + (0..<500).map { index in "  C\(index) <|-- C\(index + 1)\n  C\(index) : +field\(index) int" }.joined(separator: "\n"))
        sources += ["stateDiagram-v2\n  state A {\n    a --> b", "classDiagram\n  class A {\n    +x int", "stateDiagram-v2\n  note left of A"]
        let expected = sources.map { source in Self.outcome(source, typography: typography) }
        let shared = SharedOutcomes(sources: sources, expected: expected, typography: typography)
        let differences = ThreadSafeCount()
        DispatchQueue.concurrentPerform(iterations: 12) { thread in
            let count = shared.sources.count
            for step in 0..<count {
                let index = (thread &* 31 &+ step) % count
                if Self.outcome(shared.sources[index], typography: shared.typography) != shared.expected[index] { differences.add() }
            }
        }
        XCTAssertEqual(differences.value, 0)
        XCTAssertGreaterThan(sources.count, 300)
    }

    /// What reading and preparing `source` gives: its digest line, or the error reading it threw.
    private static func outcome(_ source: String, typography: DiagramTypography) -> String {
        do {
            _ = try MermaidDiagramReader.read(source, limits: .standard)
        } catch {
            return "refused: \(error)"
        }
        return OutputDigest.Outcome(source: source, typography: typography, narrowColumnWidths: [280]).summaryLine
    }
}

/// The inputs and expected outcomes the threads share; read only once made.
private final class SharedOutcomes: @unchecked Sendable {
    let sources: [String]
    let expected: [String]
    let typography: DiagramTypography

    init(sources: [String], expected: [String], typography: DiagramTypography) {
        self.sources = sources
        self.expected = expected
        self.typography = typography
    }
}
