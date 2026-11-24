/**
 * File: ClassDiagramLayoutEquivalenceTests.swift
 * ----------------------------------------------
 * Layer: Tests
 * Description: Every class diagram of the corpora, generated hierarchies and random class diagrams laid out by the
 *              class diagram layout and by the 0.7.0 engine kept as the reference, as they run and fitted to Graphite's
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

final class ClassDiagramLayoutEquivalenceTests: XCTestCase {
    func testEveryClassDiagramOfTheCorporaMatchesTheReferenceBitForBit() throws {
        var sources = try OutputDigest.corpora().flatMap(\.sources)
        sources += try ClassDiagramCorpus.documentationExamples()
        var classDiagramCount = 0
        var mismatches = 0
        for source in sources {
            guard case .classDiagram(let diagram)? = try? MermaidDiagramReader.read(source, limits: .standard) else { continue }
            classDiagramCount += 1
            if let difference = Self.firstDifference(diagram, limits: .standard) {
                mismatches += 1
                if mismatches <= 5 { XCTFail("\(difference) differs for:\n\(source.prefix(400))") }
            }
        }
        XCTAssertGreaterThan(classDiagramCount, 60)
        XCTAssertEqual(mismatches, 0)
    }

    func testGeneratedHierarchiesMatchTheReferenceBitForBit() throws {
        for (classCount, fan) in [(30, 3), (200, 4), (400, 2)] {
            var readingLimits = MermaidDiagramLimits.standard
            readingLimits.maximumSourceBytes = 1_000_000
            guard case .classDiagram(let diagram) = try MermaidDiagramReader.read(ClassDiagramCorpus.hierarchy(classCount: classCount, fan: fan),
                                                                                  limits: readingLimits) else { return XCTFail("not a class diagram") }
            XCTAssertNil(Self.firstDifference(diagram, limits: .standard), "\(classCount) classes")
        }
    }

    /// Random class diagrams: namespaces inside namespaces, members, relations of every kind, cardinalities, interfaces,
    /// loops, notes, directions.
    func testRandomClassDiagramsMatchTheReferenceBitForBit() {
        var texts = ClassRandomTexts(seed: 0xC1A_55E5)
        var classDiagramCount = 0
        var namespacedCount = 0
        for index in 0..<3_000 {
            let source = texts.text(statementCount: 22)
            guard case .classDiagram(let diagram)? = try? MermaidDiagramReader.read(source, limits: .standard) else { continue }
            classDiagramCount += 1
            if !diagram.namespaces.isEmpty { namespacedCount += 1 }
            if let difference = Self.firstDifference(diagram, limits: .standard) { XCTFail("random class diagram \(index): \(difference) differs for:\n\(source)") }
        }
        XCTAssertGreaterThan(classDiagramCount, 1_400)
        XCTAssertGreaterThan(namespacedCount, 250)
    }

    /// Budgets of layout points too small for some diagrams: both refuse the same ones alike.
    func testSmallLayoutBudgetsAreRefusedAlike() throws {
        var limits = MermaidDiagramLimits.standard
        var texts = ClassRandomTexts(seed: 0xB0D_C1A5)
        let sources = try ClassDiagramCorpus.documentationExamples() + (0..<200).map { _ in texts.text(statementCount: 16) }
        for budget in [1, 3, 8, 20] {
            limits.maximumLayoutPointCount = budget
            for source in sources {
                guard case .classDiagram(let diagram)? = try? MermaidDiagramReader.read(source, limits: .standard) else { continue }
                XCTAssertNil(Self.firstDifference(diagram, limits: limits), "budget \(budget):\n\(source.prefix(300))")
            }
        }
    }

    /// The first way of laying `diagram` out whose layout differs from the reference's, or nil.
    static func firstDifference(_ diagram: ClassDiagram, limits: MermaidDiagramLimits) -> String? {
        let typography = DiagramSceneSamples.typography
        let laidOut = ClassDiagramLayoutBits { try ClassDiagramLayoutEngine.layout(diagram, typography: typography, limits: limits) }
        let reference = ClassDiagramLayoutBits { try ReferenceClassDiagramLayoutEngine.layout(diagram, typography: typography, limits: limits) }
        if laidOut != reference { return "the layout" }
        for width in OutputDigest.narrowColumnWidths + [120] {
            let laidOut = ClassDiagramLayoutBits { try ClassDiagramLayoutEngine.layout(diagram, typography: typography, limits: limits, availableWidth: width) }
            let reference = ClassDiagramLayoutBits {
                try ReferenceClassDiagramLayoutEngine.layout(diagram, typography: typography, limits: limits, availableWidth: width)
            }
            if laidOut != reference { return "the layout \(width) points wide" }
        }
        return nil
    }
}

/// Every number, text and choice of a class diagram's layout as bit patterns, or the error laying it out threw.
struct ClassDiagramLayoutBits: Equatable {
    var bits = FlowchartLayoutBits { throw CancellationError() }

    init(laying: () throws -> ClassDiagramLayout) {
        bits.error = nil
        let layout: ClassDiagramLayout
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
        bits.bits.append(UInt64(layout.classes.count))
        for box in layout.classes {
            bits.add(box.frame)
            for y in box.dividerYs { bits.add(y) }
            bits.bits.append(UInt64(box.annotations.count))
            for annotation in box.annotations { bits.add(annotation) }
            bits.add(box.name)
            bits.bits.append(UInt64(box.members.count))
            for member in box.members {
                bits.add(member.text)
                bits.descriptions.append(String(describing: member.classifier))
            }
        }
        bits.bits.append(UInt64(layout.notes.count))
        for note in layout.notes {
            bits.add(note.frame)
            bits.add(note.text)
        }
        bits.bits.append(UInt64(layout.interfaces.count))
        for interface in layout.interfaces { bits.add(interface) }
        for edges in [layout.relations, layout.noteLinks] {
            bits.bits.append(UInt64(edges.count))
            for edge in edges {
                bits.descriptions.append(String(describing: edge.line))
                bits.add(edge.path)
                for mark in [edge.sourceMark, edge.targetMark] {
                    guard let mark else {
                        bits.bits.append(UInt64.max)
                        continue
                    }
                    bits.descriptions.append(String(describing: mark.end))
                    bits.add(mark.tip)
                    bits.add(mark.direction.dx)
                    bits.add(mark.direction.dy)
                }
                bits.add(edge.text)
                bits.add(edge.sourceCardinality)
                bits.add(edge.targetCardinality)
            }
        }
        bits.bits.append(UInt64(layout.namespaces.count))
        for namespace in layout.namespaces {
            bits.add(namespace.frame)
            bits.add(namespace.title)
            bits.bits += [UInt64(namespace.depth), namespace.isTitleCrossed ? 1 : 0]
        }
    }
}
