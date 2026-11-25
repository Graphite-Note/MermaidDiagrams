/**
 * File: UseCaseLayoutEquivalenceTests.swift
 * -----------------------------------------
 * Layer: Tests
 * Description: Every use case diagram of the corpora, generated diagrams and random ones laid out by the use case layout
 *              and by the 0.7.0 engine kept as the reference, as they run and fitted to Graphite's narrow columns, alike
 *              to the bit; small layout budgets refused alike; twelve threads laying out at once alike.
 *
 * Authors: Bahey Shalash
 * Version: 0.2
 * Date: 25/11/2026
 */

import CoreGraphics
import Foundation
import XCTest
@testable import MermaidDiagrams
@testable import MermaidDiagramsBenchmark

final class UseCaseLayoutEquivalenceTests: XCTestCase {
    func testEveryUseCaseDiagramOfTheCorporaMatchesTheReferenceBitForBit() throws {
        var sources = try OutputDigest.corpora().flatMap(\.sources)
        sources += try UseCaseCorpus.documentationExamples()
        var diagramCount = 0
        var mismatches = 0
        for source in sources {
            guard case .useCase(let diagram)? = try? MermaidDiagramReader.read(source, limits: .standard) else { continue }
            diagramCount += 1
            if let difference = Self.firstDifference(diagram, limits: .standard) {
                mismatches += 1
                if mismatches <= 5 { XCTFail("\(difference) differs for:\n\(source.prefix(400))") }
            }
        }
        XCTAssertGreaterThan(diagramCount, 40)
        XCTAssertEqual(mismatches, 0)
    }

    func testGeneratedDiagramsMatchTheReferenceBitForBit() throws {
        var readingLimits = MermaidDiagramLimits.standard
        readingLimits.maximumSourceBytes = 1_000_000
        for (actors, useCases, boundaries, relationships) in [(3, 8, 1, 12), (10, 40, 4, 80), (20, 120, 6, 260)] {
            let source = UseCaseCorpus.generated(actorCount: actors, useCaseCount: useCases, boundaryCount: boundaries, relationshipCount: relationships)
            guard case .useCase(let diagram) = try MermaidDiagramReader.read(source, limits: readingLimits) else { return XCTFail("not a use case diagram") }
            XCTAssertNil(Self.firstDifference(diagram, limits: .standard), "\(useCases) use cases")
        }
    }

    func testRandomUseCaseDiagramsMatchTheReferenceBitForBit() {
        var texts = UseCaseRandomTexts(seed: 0x05E_CA5E)
        var diagramCount = 0
        for index in 0..<3_000 {
            let source = texts.text(statementCount: 22)
            // Many random texts contradict themselves as Pele's reader sees them (a name declared as two kinds); those are left out.
            guard case .useCase(let diagram)? = try? MermaidDiagramReader.read(source, limits: .standard) else { continue }
            diagramCount += 1
            if let difference = Self.firstDifference(diagram, limits: .standard) { XCTFail("random diagram \(index): \(difference) differs for:\n\(source)") }
        }
        XCTAssertGreaterThan(diagramCount, 1_000)
    }

    /// Budgets of layout points too small for some diagrams: both refuse the same ones alike.
    func testSmallLayoutBudgetsAreRefusedAlike() throws {
        var limits = MermaidDiagramLimits.standard
        var texts = UseCaseRandomTexts(seed: 0xB0D_05E)
        let sources = try UseCaseCorpus.documentationExamples() + (0..<200).map { _ in texts.text(statementCount: 16) }
        for budget in [1, 3, 8, 20] {
            limits.maximumLayoutPointCount = budget
            for source in sources {
                guard case .useCase(let diagram)? = try? MermaidDiagramReader.read(source, limits: .standard) else { continue }
                XCTAssertNil(Self.firstDifference(diagram, limits: limits), "budget \(budget):\n\(source.prefix(300))")
            }
        }
    }

    /// The layout runs on the calling thread's scratch arena: twelve threads laying out the documentation examples, with
    /// and without boundaries, and random diagrams at once lay each out as the reference does alone.
    func testLayoutsOnTwelveThreadsAtOnceMatchTheReference() throws {
        var texts = UseCaseRandomTexts(seed: 0x7_4EAD)
        let sources = try UseCaseCorpus.documentationExamples() + (0..<200).map { _ in texts.text(statementCount: 18) }
        let diagrams = sources.compactMap { source -> UseCaseDiagram? in
            guard case .useCase(let diagram)? = try? MermaidDiagramReader.read(source, limits: .standard) else { return nil }
            return diagram
        }
        XCTAssertGreaterThan(diagrams.count, 80)
        let typography = DiagramSceneSamples.typography
        let expected = diagrams.map { diagram in UseCaseLayoutBits { try ReferenceUseCaseLayoutEngine.layout(diagram, typography: typography) } }
        let mismatches = ThreadSafeCount()
        DispatchQueue.concurrentPerform(iterations: 12) { thread in
            for offset in diagrams.indices {
                let index = (offset + thread * 7) % diagrams.count
                if UseCaseLayoutBits(laying: { try UseCaseLayoutEngine.layout(diagrams[index], typography: typography) }) != expected[index] { mismatches.add() }
            }
        }
        XCTAssertEqual(mismatches.value, 0)
    }

    /// The first way of laying `diagram` out whose layout differs from the reference's, or nil.
    static func firstDifference(_ diagram: UseCaseDiagram, limits: MermaidDiagramLimits) -> String? {
        let typography = DiagramSceneSamples.typography
        let laidOut = UseCaseLayoutBits { try UseCaseLayoutEngine.layout(diagram, typography: typography, limits: limits) }
        let reference = UseCaseLayoutBits { try ReferenceUseCaseLayoutEngine.layout(diagram, typography: typography, limits: limits) }
        if laidOut != reference { return "the layout" }
        for width in OutputDigest.narrowColumnWidths {
            let laidOut = UseCaseLayoutBits { try UseCaseLayoutEngine.layout(diagram, typography: typography, limits: limits, fittingWidth: width) }
            let reference = UseCaseLayoutBits { try ReferenceUseCaseLayoutEngine.layout(diagram, typography: typography, limits: limits, fittingWidth: width) }
            if laidOut != reference { return "the layout \(width) points wide" }
        }
        return nil
    }
}

/// A use case diagram's layout as the text of every part, which prints every number in full, or the error laying it out
/// threw: its types compare their numbers as `==` does, which keeps 0 and -0 alike, so their descriptions are compared
/// with each number's bits beside it.
struct UseCaseLayoutBits: Equatable {
    var description: String

    init(laying: () throws -> UseCaseLayout) {
        do {
            let layout = try laying()
            description = String(reflecting: layout) + " " + Self.bitsOfNumbers(in: String(reflecting: layout))
        } catch {
            description = "error " + String(describing: error)
        }
    }

    /// Every number of `text` read back as a Double and written as its bits, so that -0 and 0 differ.
    private static func bitsOfNumbers(in text: String) -> String {
        var bits: [String] = []
        var current = ""
        for character in text {
            if character.isNumber || character == "." || character == "-" || character == "e" {
                current.append(character)
            } else {
                if let value = Double(current) { bits.append(String(value.bitPattern, radix: 16)) }
                current = ""
            }
        }
        return bits.joined(separator: ",")
    }
}
