/**
 * File: EntityRelationshipLayoutEquivalenceTests.swift
 * ----------------------------------------------------
 * Layer: Tests
 * Description: Every entity relationship diagram of the corpora, generated schemas and random diagrams laid out by the
 *              entity relationship layout and by the 0.7.0 engine kept as the reference, as they run and turned to run
 *              down as Graphite's narrow columns lay them out, alike to the bit; small layout budgets refused alike.
 *
 * Authors: Bahey Shalash
 * Version: 0.2
 * Date: 24/11/2026
 */

import CoreGraphics
import XCTest
@testable import MermaidDiagrams
@testable import MermaidDiagramsBenchmark

final class EntityRelationshipLayoutEquivalenceTests: XCTestCase {
    func testEveryEntityRelationshipDiagramOfTheCorporaMatchesTheReferenceBitForBit() throws {
        var sources = try OutputDigest.corpora().flatMap(\.sources)
        sources += try EntityRelationshipCorpus.documentationExamples()
        var diagramCount = 0
        var mismatches = 0
        for source in sources {
            guard case .entityRelationship(let diagram)? = try? MermaidDiagramReader.read(source, limits: .standard) else { continue }
            diagramCount += 1
            if let difference = Self.firstDifference(diagram, limits: .standard) {
                mismatches += 1
                if mismatches <= 5 { XCTFail("\(difference) differs for:\n\(source.prefix(400))") }
            }
        }
        XCTAssertGreaterThan(diagramCount, 40)
        XCTAssertEqual(mismatches, 0)
    }

    func testGeneratedSchemasMatchTheReferenceBitForBit() throws {
        var readingLimits = MermaidDiagramLimits.standard
        readingLimits.maximumSourceBytes = 1_000_000
        for entityCount in [20, 100, 300] {
            guard case .entityRelationship(let diagram) = try MermaidDiagramReader.read(EntityRelationshipCorpus.schema(entityCount: entityCount),
                                                                                        limits: readingLimits) else { return XCTFail("not an ER diagram") }
            XCTAssertNil(Self.firstDifference(diagram, limits: .standard), "\(entityCount) entities")
        }
    }

    /// Random diagrams: groups inside groups, attribute tables, every cardinality, labels, loops, directions.
    func testRandomEntityRelationshipDiagramsMatchTheReferenceBitForBit() {
        var texts = EntityRelationshipRandomTexts(seed: 0xE2_D1A6)
        var diagramCount = 0
        var groupedCount = 0
        for index in 0..<3_000 {
            let source = texts.text(statementCount: 22)
            guard case .entityRelationship(let diagram)? = try? MermaidDiagramReader.read(source, limits: .standard) else { continue }
            diagramCount += 1
            if !diagram.subgraphs.isEmpty { groupedCount += 1 }
            if let difference = Self.firstDifference(diagram, limits: .standard) { XCTFail("random diagram \(index): \(difference) differs for:\n\(source)") }
        }
        XCTAssertGreaterThan(diagramCount, 1_400)
        XCTAssertGreaterThan(groupedCount, 300)
    }

    /// Types and names with every line ending: a line feed, a carriage return and line feed, a carriage return alone at
    /// the end or inside, both at once, and text without any, read from backticks and, as the reader turns a lone
    /// carriage return into a line feed, also set on the attribute as a diagram built in code holds it; the layout splits
    /// and trims them as the 0.7.0 engine did, which a type or name kept whole only when it holds neither a line feed nor
    /// a final carriage return relies on.
    func testTypesAndNamesWithEveryLineEndingMatchTheReference() throws {
        let texts = ["plain", "a\nb", "a\r\nb", "a\r", "a\rb", "a\r\n", "\r", "\n", "a\n\rb\r", "é\r", "a\u{301}\r"]
        guard case .entityRelationship(let built) = try MermaidDiagramReader.read("erDiagram\n  A {\n    string name\n  }\n", limits: .standard) else {
            return XCTFail("not an entity relationship diagram")
        }
        var comparedCount = 0
        for text in texts {
            for source in ["erDiagram\n  A {\n    `\(text)` name PK\n  }\n", "erDiagram\n  A {\n    string `\(text)`\n  }\n"] {
                guard case .entityRelationship(let diagram)? = try? MermaidDiagramReader.read(source, limits: .standard) else { continue }
                comparedCount += 1
                XCTAssertNil(Self.firstDifference(diagram, limits: .standard), "\(source.debugDescription)")
            }
            var diagram = built
            diagram.entities[0].attributes = [EntityRelationshipAttribute(type: text, name: "name"), EntityRelationshipAttribute(type: "string", name: text)]
            comparedCount += 1
            XCTAssertNil(Self.firstDifference(diagram, limits: .standard), "\(text.debugDescription) set on the attribute")
        }
        XCTAssertGreaterThan(comparedCount, 25)
    }

    /// Budgets of layout points too small for some diagrams: both refuse the same ones alike.
    func testSmallLayoutBudgetsAreRefusedAlike() throws {
        var limits = MermaidDiagramLimits.standard
        var texts = EntityRelationshipRandomTexts(seed: 0xB0D_E2)
        let sources = try EntityRelationshipCorpus.documentationExamples() + (0..<200).map { _ in texts.text(statementCount: 16) }
        for budget in [1, 3, 8, 20] {
            limits.maximumLayoutPointCount = budget
            for source in sources {
                guard case .entityRelationship(let diagram)? = try? MermaidDiagramReader.read(source, limits: .standard) else { continue }
                XCTAssertNil(Self.firstDifference(diagram, limits: limits), "budget \(budget):\n\(source.prefix(300))")
            }
        }
    }

    /// The first way of laying `diagram` out whose layout differs from the reference's, or nil.
    static func firstDifference(_ diagram: EntityRelationshipDiagram, limits: MermaidDiagramLimits) -> String? {
        let typography = DiagramSceneSamples.typography
        let laidOut = EntityRelationshipLayoutBits { try EntityRelationshipLayoutEngine.layout(diagram, typography: typography, limits: limits) }
        let reference = EntityRelationshipLayoutBits { try ReferenceEntityRelationshipLayoutEngine.layout(diagram, typography: typography, limits: limits) }
        if laidOut != reference { return "the layout" }
        if let turned = diagram.turnedTopToBottom {
            let laidOut = EntityRelationshipLayoutBits { try EntityRelationshipLayoutEngine.layout(turned, typography: typography, limits: limits) }
            let reference = EntityRelationshipLayoutBits { try ReferenceEntityRelationshipLayoutEngine.layout(turned, typography: typography, limits: limits) }
            if laidOut != reference { return "the layout turned to run down" }
        }
        return nil
    }
}

/// Every number, text and choice of an entity relationship diagram's layout as bit patterns, or the error laying it out
/// threw.
struct EntityRelationshipLayoutBits: Equatable {
    var bits = FlowchartLayoutBits { throw CancellationError() }

    init(laying: () throws -> EntityRelationshipLayout) {
        bits.error = nil
        let layout: EntityRelationshipLayout
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
        bits.bits.append(UInt64(layout.entities.count))
        for entity in layout.entities {
            bits.add(entity.frame)
            bits.add(entity.name)
            bits.bits.append(UInt64(entity.rows.count))
            for row in entity.rows {
                bits.add(row.frame)
                bits.bits.append(UInt64(row.texts.count))
                for cell in row.texts {
                    bits.descriptions.append(String(describing: cell.column))
                    bits.add(cell.text)
                }
            }
        }
        bits.bits.append(UInt64(layout.relationships.count))
        for relationship in layout.relationships {
            bits.descriptions.append(String(describing: relationship.identification))
            bits.add(relationship.path)
            for mark in [relationship.firstEntityMark, relationship.secondEntityMark] {
                bits.descriptions.append(String(describing: mark.cardinality))
                bits.add(mark.tip)
                bits.add(mark.direction.dx)
                bits.add(mark.direction.dy)
            }
            bits.add(relationship.label)
        }
        bits.bits.append(UInt64(layout.subgraphs.count))
        for subgraph in layout.subgraphs {
            bits.add(subgraph.frame)
            bits.add(subgraph.title)
            bits.bits += [UInt64(subgraph.depth), subgraph.isTitleCrossed ? 1 : 0]
        }
    }
}
