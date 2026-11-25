/**
 * File: ClassReadingEquivalenceTests.swift
 * ----------------------------------------
 * Layer: Tests
 * Description: The class diagram reader on the text's borrowed bytes, with its names interned, against 0.7.0's reader
 *              kept as the reference: every input of the corpora and of Pele's compatibility tests, generated
 *              hierarchies, random and mutated texts (beyond ASCII and kept to it), namespaces and notes in every
 *              order, the limits, each the same diagram or the same error; hostile texts and names that collide in the
 *              name table's hash read alike in time that grows with their length, and readings on twelve threads alike.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 25/11/2026
 */

import Foundation
import XCTest
@testable import MermaidDiagrams
@testable import MermaidDiagramsBenchmark

final class ClassReadingEquivalenceTests: XCTestCase {
    func testEveryInputOfTheCorporaAndOfPelesCompatibilityTestsIsReadAsTheReferenceReadsIt() throws {
        let sources = try OutputDigest.corpora().flatMap(\.sources) + PeleResults.compatInputs().sorted { $0.key < $1.key }.flatMap(\.value)
        XCTAssertGreaterThan(Self.assertReadAlike(sources), 38)
        XCTAssertGreaterThan(Self.assertReadAlike(sources.map(GraphTextMutations.ascii)), 38)
    }

    func testGeneratedHierarchiesAreReadAsTheReferenceReadsThem() {
        let sources = [1, 10, 80, 400].flatMap { count in [1, 3].map { fan in ClassDiagramCorpus.hierarchy(classCount: count, fan: fan) } }
        XCTAssertEqual(Self.assertReadAlike(sources), sources.count)
    }

    func testRandomTextsAreReadAsTheReferenceReadsThem() {
        var generator = ClassRandomTexts(seed: 79)
        let sources = (0..<3_000).map { _ in generator.text(statementCount: 24) }
        XCTAssertGreaterThan(Self.assertReadAlike(sources), 2_500)
        XCTAssertGreaterThan(Self.assertReadAlike(sources.map(GraphTextMutations.ascii)), 2_500)
    }

    func testMutatedTextsAreReadAsTheReferenceReadsThem() throws {
        var mutations = GraphTextMutations(seed: 83)
        let pieces = GraphTextMutations.commonPieces + [
            "class ", "class A~T~", "class `A b`", "[\"Label\"]", ":::s", "<<interface>>", "<<>>", "{\n +int x\n +go() int\n}", " : +field",
            " <|-- ", " *-- ", " o-- ", " --> ", " ..> ", " ..|> ", " -- ", " .. ", " ()-- ", " --() ", " \"1\" ", " \"*\" ", " : label",
            "note \"n\"\n", "note for A \"n\"\n", "namespace N {\n", "namespace N[\"T\"] {\n", "}\n", "direction LR\n", "direction XY\n",
            "accTitle: t\n", "accDescr { d\n e }", "style A fill:#f00\n", "classDef c fill:#f00\n", "cssClass \"A\" c\n", "click A call f()\n",
            "link A \"u\"\n", "callback A \"f\"\n", "Ca-r", "Company.Engine", "o", "~", "`",
        ]
        let originals = try ClassDiagramCorpus.documentationExamples() + PeleResults.compatInputs().filter { $0.key.hasPrefix("class") }.flatMap(\.value)
        var sources: [String] = []
        for round in 0..<8_000 {
            let mutated = mutations.mutated(originals[round % originals.count], pieces: pieces)
            sources.append(round % 2 == 0 ? mutated : GraphTextMutations.ascii(mutated))
        }
        XCTAssertGreaterThan(Self.assertReadAlike(sources), 5_500)
    }

    /// Namespaces nested and repeated, notes for classes declared before and after them and for none, interfaces of
    /// lollipop ends, classes named in relations before their declaration, labels set twice.
    func testNamespacesNotesAndInterfacesInEveryOrderAreReadAlike() {
        let statements = [
            "namespace N {\nclass A\nnote for A \"n\"\n}", "namespace N.M {\nclass B\n}", "note for C \"c\"", "note \"free\"", "class C[\"Cee\"]",
            "A <|-- C", "bar ()-- A", "B --() baz", "class A[\"Again\"]", "A : +x", "<<abstract>> B", "class D~T~ {\n+go()\n}", "D \"1\" o-- \"*\" A : has",
            "direction RL",
        ]
        var mutations = GraphTextMutations(seed: 89)
        var sources: [String] = []
        for _ in 0..<800 {
            var shuffled = statements
            for index in shuffled.indices.reversed() { shuffled.swapAt(index, mutations.below(index + 1)) }
            sources.append("classDiagram\n" + shuffled.prefix(4 + mutations.below(statements.count - 3)).joined(separator: "\n"))
        }
        XCTAssertEqual(Self.assertReadAlike(sources), sources.count)
    }

    func testLimitsRefuseAlike() {
        let source = ClassDiagramCorpus.hierarchy(classCount: 60) + "\n  note for C1 \"n\"\n  namespace A.B.C {\n    class Z\n  }\n  bar ()-- C2"
        let standard = MermaidDiagramLimits.standard
        for (nodes, edges, bytes) in [(5, 500, standard.maximumSourceBytes), (500, 7, standard.maximumSourceBytes), (500, 500, 100),
                                      (62, 500, standard.maximumSourceBytes), (500, 500, standard.maximumSourceBytes)] {
            let limits = MermaidDiagramLimits(maximumSourceBytes: bytes, maximumNodeCount: nodes, maximumEdgeCount: edges,
                                              maximumLayoutPointCount: standard.maximumLayoutPointCount)
            XCTAssertEqual(Self.assertReadAlike([source], limits: limits), 1)
        }
    }

    /// Long lines, thousands of classes and relations with names that share all but their last bytes, long bodies,
    /// deep namespaces and long annotations: read as the reference reads them, and a text ten times as long in at most
    /// forty times the time.
    func testHostileTextsAreReadAlikeInTimeThatGrowsWithTheirLength() {
        func hostile(_ count: Int) -> [String] {
            let prefix = String(repeating: "n", count: 40)
            let names = (0..<count).map { index in "\(prefix)\(index)" }
            return [
                "classDiagram\n" + names.enumerated().map { index, name in "  \(name) <|-- \(names[(index * 7) % count]) : t" }.joined(separator: "\n"),
                "classDiagram\n  class A {\n" + (0..<count).map { index in "    +List~int~ f\(index)(a, b) int" }.joined(separator: "\n") + "\n  }",
                "classDiagram\n  A : " + String(repeating: "word_ ", count: count * 4),
                "classDiagram\n" + (0..<min(count, 400)).map { index in "namespace N\(index) {" }.joined(separator: "\n") + "\nclass X\n"
                    + String(repeating: "}\n", count: min(count, 400)),
                "classDiagram\n" + String(repeating: "a", count: count * 20) + " --> " + String(repeating: "b", count: count * 20),
                "classDiagram\n" + names.map { name in "note for \(name) \"n\"\nclass \(name)" }.joined(separator: "\n"),
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

    /// Classes and notes whose 8,192 names collide in the name table's hash's low bits for every basis are read as the
    /// reference reads them, ten times the names in at most forty times the time.
    func testNamesThatShareTheHashsLowBitsAreReadAlikeAndInTime() {
        func diagram(_ names: [String]) -> String {
            "classDiagram\n" + names.enumerated().map { index, name in "  \(name) --> \(names[(index &* 7 &+ 1) % names.count])" }.joined(separator: "\n")
                + "\n" + names.prefix(64).map { name in "note for \(name) \"n\"" }.joined(separator: "\n")
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
    /// class, written plain or in backticks, as 0.7.0's String keys made them.
    func testSpellingsSwiftHoldsEqualNameOneClass() throws {
        let sources = [
            "classDiagram\n  caf\u{E9} <|-- `cafe\u{301}`\n  cafe\u{301} : +x",
            "classDiagram\n  class \u{212A}\n  note for K \"n\"\n  \u{212A} --> K",
        ]
        XCTAssertEqual(Self.assertReadAlike(sources), sources.count)
        guard case .classDiagram(let first) = try MermaidDiagramReader.read(sources[0], limits: .standard) else { return XCTFail("not read") }
        XCTAssertEqual(first.classes.count, 1)
    }

    /// The same texts read on twelve threads at once give what one thread gives.
    func testReadingsOnTwelveThreadsAtOnceAreAlike() {
        var generator = ClassRandomTexts(seed: 97)
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

    /// Reads each source both ways and fails for each that differs; returns how many the reference read as a class
    /// diagram, or refused while reading one.
    @discardableResult
    static func assertReadAlike(_ sources: [String], limits: MermaidDiagramLimits = .standard, file: StaticString = #filePath, line: UInt = #line) -> Int {
        var checked = 0
        var mismatches = 0
        for source in sources {
            let reference = Result { () throws(MermaidDiagramReadError) in try ReferenceClassReading.read(source, limits: limits) }
            let package = Result { () throws(MermaidDiagramReadError) in try MermaidDiagramReader.read(source, limits: limits) }
            var difference: String?
            switch (reference, package) {
            case (.success(nil), _): continue
            case (.success(let expected?), .success(.classDiagram(let read))):
                if expected != read { difference = "read otherwise: \(read.classes.count) classes, \(read.relations.count) relations" }
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
