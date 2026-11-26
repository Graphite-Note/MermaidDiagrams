/**
 * File: StateDiagramLayoutEquivalenceTests.swift
 * ----------------------------------------------
 * Layer: Tests
 * Description: Every state diagram of the corpora, Pele's generated machines, random state diagrams and composites
 *              with several notes laid out by the state diagram layout and by the 0.7.0 engine kept as the reference, as
 *              they run and fitted to Graphite's narrow columns, alike to the bit; small layout budgets refused alike.
 *
 * Authors: Bahey Shalash
 * Version: 0.2
 * Date: 26/11/2026
 */

import CoreGraphics
import XCTest
@testable import MermaidDiagrams
@testable import MermaidDiagramsBenchmark

final class StateDiagramLayoutEquivalenceTests: XCTestCase {
    func testEveryStateDiagramOfTheCorporaMatchesTheReferenceBitForBit() throws {
        var sources = try OutputDigest.corpora().flatMap(\.sources)
        sources += try StateDiagramCorpus.documentationExamples()
        var stateDiagramCount = 0
        var mismatches = 0
        for source in sources {
            guard case .stateDiagram(let diagram)? = try? MermaidDiagramReader.read(source, limits: .standard) else { continue }
            stateDiagramCount += 1
            if let difference = Self.firstDifference(diagram, limits: .standard) {
                mismatches += 1
                if mismatches <= 5 { XCTFail("\(difference) differs for:\n\(source.prefix(400))") }
            }
        }
        XCTAssertGreaterThan(stateDiagramCount, 40)
        XCTAssertEqual(mismatches, 0)
    }

    func testGeneratedMachinesMatchTheReferenceBitForBit() throws {
        for (stateCount, extraTransitionCount) in [(50, 20), (200, 80), (500, 200)] {
            let source = StateDiagramCorpus.machine(stateCount: stateCount, extraTransitionCount: extraTransitionCount)
            guard case .stateDiagram(let diagram) = try MermaidDiagramReader.read(source, limits: .standard) else { return XCTFail("not a state diagram") }
            XCTAssertNil(Self.firstDifference(diagram, limits: .standard), "\(stateCount) states")
        }
    }

    /// Random state diagrams: composites inside composites, regions, directions, notes, loops, marks, texts.
    func testRandomStateDiagramsMatchTheReferenceBitForBit() {
        var texts = StateRandomTexts(seed: 0x57A7_E5)
        var stateDiagramCount = 0
        var compositeCount = 0
        for index in 0..<3_000 {
            let source = texts.text(statementCount: 22)
            guard case .stateDiagram(let diagram)? = try? MermaidDiagramReader.read(source, limits: .standard) else { continue }
            stateDiagramCount += 1
            if !diagram.composites.isEmpty { compositeCount += 1 }
            if let difference = Self.firstDifference(diagram, limits: .standard) { XCTFail("random state diagram \(index): \(difference) differs for:\n\(source)") }
        }
        XCTAssertGreaterThan(stateDiagramCount, 1_400)
        XCTAssertGreaterThan(compositeCount, 600)
    }

    /// Composites with several notes each, on either side, around loops and nested composites: the notes of one composite
    /// are laid out in the order written (the random diagrams rarely put two notes on one composite).
    func testCompositesWithSeveralNotesMatchTheReferenceBitForBit() throws {
        var generator = SeededNumbers(state: 0x5EED_0A7E)
        let texts = ["a", "short note", "a much longer note that is wide", "two\\nlines", "x"]
        var noteCount = 0
        for index in 0..<300 {
            var lines = ["stateDiagram-v2"]
            if index % 3 == 1 { lines.append("  direction LR") }
            let compositeCount = 1 + index % 3
            for composite in 0..<compositeCount {
                lines.append("  state C\(composite) {")
                lines.append("    a\(composite) --> b\(composite)")
                if index % 4 == 2 { lines += ["    state D\(composite) {", "      d\(composite) --> e\(composite)", "    }", "    note right of D\(composite) : inner"] }
                lines.append("  }")
                for _ in 0..<(2 + generator.next(4)) {
                    lines.append("  note \(generator.next(2) == 0 ? "left" : "right") of C\(composite) : \(texts[generator.next(texts.count)])")
                    noteCount += 1
                }
                if generator.next(2) == 0 { lines.append("  C\(composite) --> C\(composite) : loop") }
                lines.append("  x --> C\(composite)")
            }
            let source = lines.joined(separator: "\n")
            guard case .stateDiagram(let diagram) = try MermaidDiagramReader.read(source, limits: .standard) else { return XCTFail("not a state diagram") }
            if let difference = Self.firstDifference(diagram, limits: .standard) { XCTFail("diagram \(index): \(difference) differs for:\n\(source)") }
        }
        XCTAssertGreaterThan(noteCount, 1_000)
    }

    /// Budgets of layout points too small for some diagrams: both refuse the same ones alike.
    func testSmallLayoutBudgetsAreRefusedAlike() throws {
        var limits = MermaidDiagramLimits.standard
        var texts = StateRandomTexts(seed: 0xB0D_6E7)
        let sources = try StateDiagramCorpus.documentationExamples() + (0..<200).map { _ in texts.text(statementCount: 16) }
        for budget in [1, 3, 8, 20] {
            limits.maximumLayoutPointCount = budget
            for source in sources {
                guard case .stateDiagram(let diagram)? = try? MermaidDiagramReader.read(source, limits: .standard) else { continue }
                XCTAssertNil(Self.firstDifference(diagram, limits: limits), "budget \(budget):\n\(source.prefix(300))")
            }
        }
    }

    /// The first way of laying `diagram` out whose layout differs from the reference's, or nil.
    static func firstDifference(_ diagram: StateDiagram, limits: MermaidDiagramLimits) -> String? {
        let typography = DiagramSceneSamples.typography
        let laidOut = StateDiagramLayoutBits { try StateDiagramLayoutEngine.layout(diagram, typography: typography, limits: limits) }
        let reference = StateDiagramLayoutBits { try ReferenceStateDiagramLayoutEngine.layout(diagram, typography: typography, limits: limits) }
        if laidOut != reference { return "the layout" }
        for width in OutputDigest.narrowColumnWidths {
            let laidOut = StateDiagramLayoutBits { try StateDiagramLayoutEngine.layout(diagram, typography: typography, limits: limits, availableWidth: width) }
            let reference = StateDiagramLayoutBits {
                try ReferenceStateDiagramLayoutEngine.layout(diagram, typography: typography, limits: limits, availableWidth: width)
            }
            if laidOut != reference { return "the layout \(width) points wide" }
        }
        return nil
    }
}

/// Numbers below a bound from a seed, the same each run (a linear congruential generator).
private struct SeededNumbers {
    var state: UInt64

    mutating func next(_ bound: Int) -> Int {
        state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
        return Int((state >> 33) % UInt64(bound))
    }
}

/// Every number, text and choice of a state diagram's layout as bit patterns, or the error laying it out threw.
struct StateDiagramLayoutBits: Equatable {
    var bits = FlowchartLayoutBits { throw CancellationError() }

    init(laying: () throws -> StateDiagramLayout) {
        bits.error = nil
        let layout: StateDiagramLayout
        do {
            layout = try laying()
        } catch {
            bits.error = String(describing: error)
            return
        }
        bits.add(layout.size.width)
        bits.add(layout.size.height)
        bits.descriptions.append(String(describing: layout.font))
        bits.add(layout.title)
        bits.bits.append(UInt64(layout.states.count))
        for state in layout.states {
            bits.descriptions.append(String(describing: state.kind))
            bits.add(state.frame)
            bits.add(state.name)
            bits.add(state.details)
        }
        bits.bits.append(UInt64(layout.transitions.count))
        for transition in layout.transitions {
            bits.add(transition.path)
            bits.add(transition.arrow)
            bits.add(transition.text)
        }
        bits.bits.append(UInt64(layout.notes.count))
        for note in layout.notes {
            bits.add(note.frame)
            bits.add(note.text)
            bits.add(note.connector)
        }
        bits.bits.append(UInt64(layout.composites.count))
        for composite in layout.composites {
            bits.add(composite.frame)
            bits.add(composite.title)
            bits.bits += [UInt64(composite.depth), composite.isTitleCrossed ? 1 : 0]
        }
        bits.bits.append(UInt64(layout.regionDividers.count))
        for divider in layout.regionDividers { bits.add(divider) }
    }
}
