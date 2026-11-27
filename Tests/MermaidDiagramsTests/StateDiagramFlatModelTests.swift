/**
 * File: StateDiagramFlatModelTests.swift
 * --------------------------------------
 * Layer: Tests
 * Description: The state diagram's flat model: texts the decoder reads as written kept as ranges of the source and the
 *              others as labels, descriptions put in one run a state whatever order they are written in, the façade's
 *              states, transitions and notes those the reference reader makes, and its layout's texts measured from
 *              those ranges the blocks 0.7.0 measured.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 26/11/2026
 */

import Foundation
import XCTest
@testable import MermaidDiagrams
@testable import MermaidDiagramsBenchmark

final class StateDiagramFlatModelTests: XCTestCase {
    /// A text without markup in ASCII is a range of the source; one with markup, a written `\n`, or beyond ASCII is a label.
    func testTextsReadAsWrittenAreRangesAndTheOthersLabels() throws {
        let diagram = try StateDiagramReading.stateDiagram("""
        stateDiagram-v2
          A : plain words
          A --> B : go on
          B --> C : **bold**
          C --> D : two\\nlines
          note left of A : a note
          note right of B
            two
            lines
          end note
        """)
        let model = diagram.model
        XCTAssertTrue(model.descriptions[0].isSourceRange)
        XCTAssertEqual(model.transitions.map(\.label.isSourceRange), [true, false, false])
        XCTAssertEqual(model.notes.map(\.text.isSourceRange), [true, false])
        XCTAssertEqual(diagram.transitions.map { transition in transition.label?.lines ?? [] }, [["go on"], ["bold"], ["two", "lines"]])
        XCTAssertEqual(diagram.notes.map(\.text.lines), [["a note"], ["two", "lines"]])
        let beyond = try StateDiagramReading.stateDiagram("stateDiagram-v2\n  A : caf\u{E9}\n  A --> B : th\u{E9}")
        XCTAssertFalse(beyond.model.descriptions[0].isSourceRange)
        XCTAssertFalse(beyond.model.transitions[0].label.isSourceRange)
        XCTAssertEqual(beyond.states[0].name.lines, ["caf\u{E9}"])
    }

    /// Descriptions written for states out of their order, interleaved and repeated, are each state's in the order written,
    /// as the reference reader keeps them.
    func testDescriptionsWrittenOutOfOrderAreEachStatesInTheOrderWritten() throws {
        var lines = ["stateDiagram-v2"]
        for index in 0..<40 { lines.append("  S\(index) --> S\((index + 1) % 40)") }
        for round in 0..<3 {
            for index in stride(from: 39, through: 0, by: -3) { lines.append("  S\(index) : round \(round) of \(index)") }
            for index in stride(from: 1, to: 40, by: 7) { lines.append("  state \"declared \(round)\" as S\(index):more \(index)") }
        }
        let source = lines.joined(separator: "\n")
        XCTAssertEqual(StateReadingEquivalenceTests.assertReadAlike([source]), 1)
        let diagram = try StateDiagramReading.stateDiagram(source)
        XCTAssertEqual(diagram.state(at: 39).descriptions.map(\.lines), [["round 0 of 39"], ["round 1 of 39"], ["round 2 of 39"]])
        XCTAssertEqual(diagram.state(at: 1).descriptions.map(\.lines).first, ["declared 0"])
        XCTAssertEqual(diagram.states, try XCTUnwrap(ReferenceStateReading.read(source, limits: .standard)).states)
    }

    /// Names, descriptions, transition texts and notes measured from their ranges are the blocks of their labels: the
    /// layout of every corpus state diagram, regular and narrow, read again from its façade's states (every text a label
    /// then) is the same to the bit.
    func testTextsMeasuredFromRangesAreTheBlocksOfTheirLabels() throws {
        let typography = DiagramSceneSamples.typography
        var compared = 0
        var sources = try OutputDigest.corpora().flatMap(\.sources)
        var generator = StateRandomTexts(seed: 41)
        sources += (0..<400).map { _ in generator.text(statementCount: 20) }
        for source in sources {
            guard case .stateDiagram(let diagram)? = try? MermaidDiagramReader.read(source, limits: .standard) else { continue }
            let labelled = StateDiagram(direction: diagram.direction, states: diagram.states, transitions: diagram.transitions, notes: diagram.notes,
                                        composites: diagram.composites, title: diagram.title, accessibilityTitle: diagram.accessibilityTitle,
                                        accessibilityDescription: diagram.accessibilityDescription,
                                        unappliedStatementCount: diagram.unappliedStatementCount)
            for width in [nil] + OutputDigest.narrowColumnWidths.map(Optional.some) {
                let fromRanges = StateDiagramLayoutBits { try StateDiagramLayoutEngine.layout(diagram, typography: typography, limits: .standard, availableWidth: width) }
                let fromLabels = StateDiagramLayoutBits { try StateDiagramLayoutEngine.layout(labelled, typography: typography, limits: .standard, availableWidth: width) }
                XCTAssertEqual(fromRanges, fromLabels, "\(width.map { "\($0) points wide" } ?? "regular"):\n\(source.prefix(400))")
            }
            compared += 1
        }
        XCTAssertGreaterThan(compared, 200)
    }

    /// Thousands of states each given several descriptions in reverse order, and long texts, read in time that grows with
    /// their length.
    func testManyDescriptionsOutOfOrderAreReadInTimeThatGrowsWithTheirCount() {
        func text(_ count: Int) -> String {
            var lines = ["stateDiagram-v2"]
            for index in 0..<count { lines.append("  S\(index) --> S\(index + 1)") }
            for round in 0..<3 { for index in stride(from: count - 1, through: 0, by: -1) { lines.append("  S\(index) : \(round) " + String(repeating: "w", count: 30)) } }
            return lines.joined(separator: "\n")
        }
        let limits = MermaidDiagramLimits(maximumSourceBytes: 10_000_000, maximumNodeCount: 100_000, maximumEdgeCount: 100_000, maximumLayoutPointCount: 1_000_000)
        let small = text(400)
        let large = text(4_000)
        XCTAssertEqual(StateReadingEquivalenceTests.assertReadAlike([small, large], limits: limits), 2)
        func seconds(_ source: String) -> Double {
            let start = Date()
            _ = try? MermaidDiagramReader.read(source, limits: limits)
            return Date().timeIntervalSince(start)
        }
        _ = seconds(small)
        XCTAssertLessThan(seconds(large), max(seconds(small), 0.005) * 40)
    }
}
