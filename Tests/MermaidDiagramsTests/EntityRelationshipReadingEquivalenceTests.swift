/**
 * File: EntityRelationshipReadingEquivalenceTests.swift
 * -----------------------------------------------------
 * Layer: Tests
 * Description: The entity relationship reader on the text's borrowed bytes, with its names interned, against 0.7.0's
 *              reader kept as the reference: every input of the corpora and of Pele's compatibility tests, generated
 *              schemas, random and mutated texts (beyond ASCII and kept to it), groups nested in every order, the
 *              limits, each the same diagram or the same error; hostile texts and names that collide in the name
 *              table's hash read alike in time that grows with their length, and readings on twelve threads alike.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 25/11/2026
 */

import Foundation
import XCTest
@testable import MermaidDiagrams
@testable import MermaidDiagramsBenchmark

final class EntityRelationshipReadingEquivalenceTests: XCTestCase {
    func testEveryInputOfTheCorporaAndOfPelesCompatibilityTestsIsReadAsTheReferenceReadsIt() throws {
        let sources = try OutputDigest.corpora().flatMap(\.sources) + PeleResults.compatInputs().sorted { $0.key < $1.key }.flatMap(\.value)
        XCTAssertGreaterThan(Self.assertReadAlike(sources), 25)
        XCTAssertGreaterThan(Self.assertReadAlike(sources.map(GraphTextMutations.ascii)), 25)
    }

    func testGeneratedSchemasAreReadAsTheReferenceReadsThem() {
        let sources = [1, 10, 80, 400].map { count in EntityRelationshipCorpus.schema(entityCount: count) }
        XCTAssertEqual(Self.assertReadAlike(sources), sources.count)
    }

    func testRandomTextsAreReadAsTheReferenceReadsThem() {
        var generator = EntityRelationshipRandomTexts(seed: 61)
        let sources = (0..<3_000).map { _ in generator.text(statementCount: 24) }
        XCTAssertGreaterThan(Self.assertReadAlike(sources), 2_500)
        XCTAssertGreaterThan(Self.assertReadAlike(sources.map(GraphTextMutations.ascii)), 2_500)
    }

    func testMutatedTextsAreReadAsTheReferenceReadsThem() throws {
        var mutations = GraphTextMutations(seed: 67)
        let pieces = GraphTextMutations.commonPieces + [
            "||--o{", "}|..|{", "|o--o|", " one or more ", " zero or many ", " only one ", " optionally to ", " to ", "u--", "1 ", "1+", "0+",
            "many(0)", "2.5", "{\n string name PK \"c\"\n}", "{ int id PK, FK }", "List~int~ x", "`a b` c", "subgraph g [t]\n", "end\n",
            "direction LR\n", "accTitle: x\n", "accDescr { y\n z }", "p[Person]", ":::c", "class a c\n", "style a fill:#f00\n", "\"q\"", "\u{00A0}",
            "\u{B5}", "\u{C0}", "''",
        ]
        let originals = try EntityRelationshipCorpus.documentationExamples() + PeleResults.compatInputs().filter { $0.key.hasPrefix("er") }.flatMap(\.value)
        var sources: [String] = []
        for round in 0..<8_000 {
            let mutated = mutations.mutated(originals[round % originals.count], pieces: pieces)
            sources.append(round % 2 == 0 ? mutated : GraphTextMutations.ascii(mutated))
        }
        XCTAssertGreaterThan(Self.assertReadAlike(sources), 6_000)
    }

    /// Groups nested and repeated in every order, holding entities, relationships and each other's identifiers, an
    /// identifier that is also an entity's name, names written twice, and groups left open or closed twice.
    func testGroupsInEveryOrderHoldAlike() {
        let statements = [
            "subgraph g1 [First group]", "subgraph g2", "end", "end", "A ||--o{ B : has", "B { int id PK }", "C", "g1 ||--|| A : is",
            "subgraph g1", "end", "direction LR", "A[Alias]", "g2 }o--o{ C : x", "D", "subgraph A",
        ]
        var mutations = GraphTextMutations(seed: 71)
        var sources: [String] = []
        for _ in 0..<800 {
            var shuffled = statements
            for index in shuffled.indices.reversed() { shuffled.swapAt(index, mutations.below(index + 1)) }
            sources.append("erDiagram\n" + shuffled.prefix(4 + mutations.below(statements.count - 3)).joined(separator: "\n"))
        }
        XCTAssertEqual(Self.assertReadAlike(sources), sources.count)
    }

    func testLimitsRefuseAlike() {
        let source = EntityRelationshipCorpus.schema(entityCount: 60) + "\nsubgraph g\nA ||--|| B : x\nend"
        let standard = MermaidDiagramLimits.standard
        for (nodes, edges, bytes) in [(5, 500, standard.maximumSourceBytes), (500, 7, standard.maximumSourceBytes), (500, 500, 100),
                                      (500, 500, standard.maximumSourceBytes)] {
            let limits = MermaidDiagramLimits(maximumSourceBytes: bytes, maximumNodeCount: nodes, maximumEdgeCount: edges,
                                              maximumLayoutPointCount: standard.maximumLayoutPointCount)
            XCTAssertEqual(Self.assertReadAlike([source], limits: limits), 1)
        }
    }

    /// Long lines, thousands of entities and relationships with names that share all but their last bytes, long
    /// attribute blocks, deep groups and long runs of tildes: read as the reference reads them, and a text ten times
    /// as long in at most forty times the time.
    func testHostileTextsAreReadAlikeInTimeThatGrowsWithTheirLength() {
        func hostile(_ count: Int) -> [String] {
            let prefix = String(repeating: "n", count: 40)
            let names = (0..<count).map { index in "\(prefix)\(index)" }
            return [
                "erDiagram\n" + names.enumerated().map { index, name in "  \(name) ||--o{ \(names[(index * 7) % count]) : t" }.joined(separator: "\n"),
                "erDiagram\n  A {\n" + (0..<count).map { index in "    string~int~ f\(index) PK, FK \"c\"" }.joined(separator: "\n") + "\n  }",
                "erDiagram\n  A {\n    " + String(repeating: "x~ ", count: count * 4) + "y~ z\n  }",
                "erDiagram\n" + (0..<min(count, 400)).map { index in "subgraph g\(index)\n  E\(index)" }.joined(separator: "\n")
                    + "\n" + String(repeating: "end\n", count: min(count, 400)),
                "erDiagram\n" + String(repeating: "a", count: count * 20) + " ||--|| " + String(repeating: "b", count: count * 20) + " : x",
                "erDiagram\nsubgraph g\n" + names.map { name in "\(name)\n\(name) ||--|| \(name) : self" }.joined(separator: "\n") + "\nend",
            ]
        }
        let limits = MermaidDiagramLimits(maximumSourceBytes: 10_000_000, maximumNodeCount: 100_000, maximumEdgeCount: 100_000, maximumLayoutPointCount: 1_000_000)
        let small = hostile(300)
        let large = hostile(3_000)
        XCTAssertEqual(Self.assertReadAlike(small + large, limits: limits), small.count + large.count)
        func seconds(_ sources: [String]) -> Double {
            let start = Date()
            for source in sources { _ = try? MermaidDiagramReader.read(source, limits: limits) }
            return Date().timeIntervalSince(start)
        }
        _ = seconds(small)
        XCTAssertLessThan(seconds(large), max(seconds(small), 0.005) * 40)
    }

    /// Entities and groups whose 8,192 names collide in the name table's hash's low bits for every basis are read as
    /// the reference reads them, ten times the names in at most forty times the time.
    func testNamesThatShareTheHashsLowBitsAreReadAlikeAndInTime() {
        func diagram(_ names: [String]) -> String {
            "erDiagram\nsubgraph outer\n" + names.enumerated().map { index, name in "  \(name) ||--o{ \(names[(index &* 7 &+ 1) % names.count]) : r" }
                .joined(separator: "\n") + "\nend\n" + names.prefix(64).map { name in "subgraph \(name)\n\(name)\nend" }.joined(separator: "\n")
        }
        let limits = MermaidDiagramLimits(maximumSourceBytes: 10_000_000, maximumNodeCount: 100_000, maximumEdgeCount: 100_000,
                                          maximumLayoutPointCount: 1_000_000)
        let caseVariants = GraphDiagramNameTableTests.caseVariants(of: "abcdefghijklm")
        let highBitVariants = GraphDiagramNameTableTests.highBitVariants(count: caseVariants.count)
        let sources = [diagram(caseVariants), diagram(highBitVariants)]
        XCTAssertEqual(Self.assertReadAlike(sources, limits: limits), sources.count)
        func seconds(_ source: String) -> Double {
            let start = Date()
            for _ in 0..<3 { _ = try? MermaidDiagramReader.read(source, limits: limits) }
            return Date().timeIntervalSince(start)
        }
        for names in [caseVariants, highBitVariants] {
            let small = diagram(Array(names.prefix(names.count / 10)))
            _ = seconds(small)
            XCTAssertLessThan(seconds(diagram(names)), max(seconds(small), 0.002) * 40)
        }
    }

    /// Names in two spellings Swift holds equal (a composed and a decomposed letter, the Kelvin sign and `K`) are one
    /// entity or group, quoted or not, as 0.7.0's String keys made them.
    func testSpellingsSwiftHoldsEqualNameOneEntity() throws {
        let sources = [
            "erDiagram\n  caf\u{E9} ||--o{ \"cafe\u{301}\" : x\n  cafe\u{301} { int id }",
            "erDiagram\n  subgraph \u{212A}\n  K\n  end\n  \u{212A} ||--|| K : self",
        ]
        XCTAssertEqual(Self.assertReadAlike(sources), sources.count)
        guard case .entityRelationship(let first) = try MermaidDiagramReader.read(sources[0], limits: .standard) else { return XCTFail("not read") }
        XCTAssertEqual(first.entities.count, 1)
    }

    /// The same texts read on twelve threads at once give what one thread gives.
    func testReadingsOnTwelveThreadsAtOnceAreAlike() {
        var generator = EntityRelationshipRandomTexts(seed: 73)
        let sources = (0..<400).map { index in index % 2 == 0 ? generator.text(statementCount: 20) : GraphTextMutations.ascii(generator.text(statementCount: 20)) }
        let expected = sources.map { source in try? MermaidDiagramReader.read(source, limits: .standard) }
        let mismatches = ThreadSafeCount()
        DispatchQueue.concurrentPerform(iterations: 12) { _ in
            for (index, source) in sources.enumerated() where (try? MermaidDiagramReader.read(source, limits: .standard)) != expected[index] {
                mismatches.add()
            }
        }
        XCTAssertEqual(mismatches.value, 0)
    }

    /// Reads each source both ways and fails for each that differs; returns how many the reference read as an entity
    /// relationship diagram, or refused while reading one.
    @discardableResult
    static func assertReadAlike(_ sources: [String], limits: MermaidDiagramLimits = .standard, file: StaticString = #filePath, line: UInt = #line) -> Int {
        var checked = 0
        var mismatches = 0
        for source in sources {
            let reference = Result { () throws(MermaidDiagramReadError) in try ReferenceEntityRelationshipReading.read(source, limits: limits) }
            let package = Result { () throws(MermaidDiagramReadError) in try MermaidDiagramReader.read(source, limits: limits) }
            var difference: String?
            switch (reference, package) {
            case (.success(nil), _): continue
            case (.success(let expected?), .success(.entityRelationship(let read))):
                if expected != read { difference = "read otherwise: \(read.entities.count) entities, \(read.relationships.count) relationships" }
            case (.failure(let expected), .failure(let error)):
                if expected != error { difference = "error \(error) where the reference throws \(expected)" }
            case (.failure(let expected), .success): difference = "read where the reference throws \(expected)"
            case (.success, .failure(let error)): difference = "throws \(error) where the reference reads"
            case (.success, .success): difference = "read as another type"
            }
            checked += 1
            if let difference {
                mismatches += 1
                if mismatches <= 5 { XCTFail("\(difference):\n\(source.prefix(600).debugDescription)", file: file, line: line) }
            }
        }
        XCTAssertEqual(mismatches, 0, file: file, line: line)
        return checked
    }
}
