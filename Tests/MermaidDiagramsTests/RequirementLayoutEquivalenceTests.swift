/**
 * File: RequirementLayoutEquivalenceTests.swift
 * ---------------------------------------------
 * Layer: Tests
 * Description: Every requirement diagram of the corpora, generated diagrams and random ones laid out by the requirement
 *              layout and by the 0.7.0 engine kept as the reference, as they run and turned to run down as Graphite's
 *              narrow columns lay them out, alike to the bit; small layout budgets refused alike.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 24/11/2026
 */

import CoreGraphics
import XCTest
@testable import MermaidDiagrams
@testable import MermaidDiagramsBenchmark

final class RequirementLayoutEquivalenceTests: XCTestCase {
    func testEveryRequirementDiagramOfTheCorporaMatchesTheReferenceBitForBit() throws {
        var sources = try OutputDigest.corpora().flatMap(\.sources)
        sources += try RequirementCorpus.documentationExamples()
        var diagramCount = 0
        var mismatches = 0
        for source in sources {
            guard case .requirement(let diagram)? = try? MermaidDiagramReader.read(source, limits: .standard) else { continue }
            diagramCount += 1
            if let difference = Self.firstDifference(diagram, limits: .standard) {
                mismatches += 1
                if mismatches <= 5 { XCTFail("\(difference) differs for:\n\(source.prefix(400))") }
            }
        }
        XCTAssertGreaterThan(diagramCount, 15)
        XCTAssertEqual(mismatches, 0)
    }

    func testGeneratedDiagramsMatchTheReferenceBitForBit() throws {
        var readingLimits = MermaidDiagramLimits.standard
        readingLimits.maximumSourceBytes = 1_000_000
        for (requirementCount, direction) in [(10, "TB"), (60, "LR"), (200, "TB")] {
            guard case .requirement(let diagram) = try MermaidDiagramReader.read(RequirementCorpus.generated(requirementCount: requirementCount,
                                                                                                           direction: direction),
                                                                                 limits: readingLimits) else { return XCTFail("not a requirement diagram") }
            XCTAssertNil(Self.firstDifference(diagram, limits: .standard), "\(requirementCount) requirements")
        }
    }

    func testRandomRequirementDiagramsMatchTheReferenceBitForBit() {
        var texts = RequirementRandomTexts(seed: 0x2E_9017)
        var diagramCount = 0
        for index in 0..<3_000 {
            let source = texts.text(statementCount: 22)
            guard case .requirement(let diagram)? = try? MermaidDiagramReader.read(source, limits: .standard) else { continue }
            diagramCount += 1
            if let difference = Self.firstDifference(diagram, limits: .standard) { XCTFail("random diagram \(index): \(difference) differs for:\n\(source)") }
        }
        XCTAssertGreaterThan(diagramCount, 1_400)
    }

    /// Budgets of layout points too small for some diagrams: both refuse the same ones alike.
    func testSmallLayoutBudgetsAreRefusedAlike() throws {
        var limits = MermaidDiagramLimits.standard
        var texts = RequirementRandomTexts(seed: 0xB0D_2E)
        let sources = try RequirementCorpus.documentationExamples() + (0..<200).map { _ in texts.text(statementCount: 16) }
        for budget in [1, 3, 8, 20] {
            limits.maximumLayoutPointCount = budget
            for source in sources {
                guard case .requirement(let diagram)? = try? MermaidDiagramReader.read(source, limits: .standard) else { continue }
                XCTAssertNil(Self.firstDifference(diagram, limits: limits), "budget \(budget):\n\(source.prefix(300))")
            }
        }
    }

    /// The first way of laying `diagram` out whose layout differs from the reference's, or nil.
    static func firstDifference(_ diagram: RequirementDiagram, limits: MermaidDiagramLimits) -> String? {
        let typography = DiagramSceneSamples.typography
        let laidOut = RequirementLayoutBits { try RequirementLayoutEngine.layout(diagram, typography: typography, limits: limits) }
        let reference = RequirementLayoutBits { try ReferenceRequirementLayoutEngine.layout(diagram, typography: typography, limits: limits) }
        if laidOut != reference { return "the layout" }
        if let turned = diagram.turnedToRunDown {
            let laidOut = RequirementLayoutBits { try RequirementLayoutEngine.layout(turned, typography: typography, limits: limits) }
            let reference = RequirementLayoutBits { try ReferenceRequirementLayoutEngine.layout(turned, typography: typography, limits: limits) }
            if laidOut != reference { return "the layout turned to run down" }
        }
        return nil
    }
}

/// Every number, text and choice of a requirement diagram's layout as bit patterns, or the error laying it out threw.
struct RequirementLayoutBits: Equatable {
    var bits = FlowchartLayoutBits { throw CancellationError() }

    init(laying: () throws -> RequirementLayout) {
        bits.error = nil
        let layout: RequirementLayout
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
        bits.bits.append(UInt64(layout.boxes.count))
        for box in layout.boxes {
            bits.add(box.frame)
            bits.bits.append(box.isRequirement ? 1 : 0)
            bits.add(box.stereotype)
            bits.add(box.name)
            bits.add(box.dividerY ?? .nan)
            bits.bits.append(UInt64(box.fieldNames.count))
            for text in box.fieldNames + box.fieldValues { bits.add(text) }
            bits.descriptions.append(String(describing: box.style))
        }
        bits.bits.append(UInt64(layout.relations.count))
        for relation in layout.relations {
            bits.descriptions.append(String(describing: relation.kind))
            bits.add(relation.path)
            switch relation.mark {
            case .containment(let point, let towardBox):
                bits.add(point)
                bits.add(towardBox.dx)
                bits.add(towardBox.dy)
            case .arrow(let tip, let direction):
                bits.bits.append(7)
                bits.add(tip)
                bits.add(direction.dx)
                bits.add(direction.dy)
            }
            bits.add(relation.text)
        }
    }
}
