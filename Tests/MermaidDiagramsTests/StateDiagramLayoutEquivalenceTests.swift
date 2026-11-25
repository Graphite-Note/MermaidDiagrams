/**
 * File: StateDiagramLayoutEquivalenceTests.swift
 * ----------------------------------------------
 * Layer: Tests
 * Description: Every state diagram of the corpora, Pele's generated machines and random state diagrams laid out by the
 *              state diagram layout and by the 0.7.0 engine kept as the reference, as they run and fitted to Graphite's
 *              narrow columns, alike to the bit; small layout budgets refused alike.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 24/11/2026
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
