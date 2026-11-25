/**
 * File: RequirementReadingEquivalenceTests.swift
 * ----------------------------------------------
 * Layer: Tests
 * Description: The requirement diagram reader on the text's borrowed bytes, with its names interned, against 0.7.0's
 *              reader kept as the reference: every input of the corpora and of Pele's compatibility tests, random and
 *              mutated texts (beyond ASCII and kept to it), styles and classes in every order, the limits, each the same
 *              diagram or the same error; hostile texts and names that collide in the name table's hash read alike in
 *              time that grows with their length, and readings on twelve threads at once alike.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 25/11/2026
 */

import Foundation
import XCTest
@testable import MermaidDiagrams
@testable import MermaidDiagramsBenchmark

final class RequirementReadingEquivalenceTests: XCTestCase {
    func testEveryInputOfTheCorporaAndOfPelesCompatibilityTestsIsReadAsTheReferenceReadsIt() throws {
        let sources = try OutputDigest.corpora().flatMap(\.sources) + PeleResults.compatInputs().sorted { $0.key < $1.key }.flatMap(\.value)
        XCTAssertGreaterThan(Self.assertReadAlike(sources), 9)
        XCTAssertGreaterThan(Self.assertReadAlike(sources.map(GraphTextMutations.ascii)), 9)
    }

    func testRandomTextsAreReadAsTheReferenceReadsThem() {
        var generator = RequirementRandomTexts(seed: 41)
        let sources = (0..<3_000).map { _ in generator.text(statementCount: 24) }
        XCTAssertGreaterThan(Self.assertReadAlike(sources), 2_500)
        XCTAssertGreaterThan(Self.assertReadAlike(sources.map(GraphTextMutations.ascii)), 2_500)
    }

    func testMutatedTextsAreReadAsTheReferenceReadsThem() throws {
        var mutations = GraphTextMutations(seed: 43)
        let pieces = GraphTextMutations.commonPieces + [
            "requirement ", "element ", "functionalRequirement x {\n", "id: 1\n", "text: t\n", "risk: high\n", "verifymethod: test\n", "type: t\n",
            "docref: d\n", " - satisfies -> ", " <- traces - ", "classDef c fill:#f00,color:red\n", "class a,b c\n", ":::c", "style a stroke:#00f\n",
            "direction LR", "direction\u{2028}TB", "accTitle: x\n", "accDescr { y\n z }", "title t\n", "#lt;", "#9829;", "default", "\u{00A0}",
            "\u{3000}", "\u{FEFF}", "\u{2029}", "\"", "%%{init: {}}%%\n",
        ]
        let originals = try RequirementCorpus.documentationExamples() + PeleResults.compatInputs().filter { $0.key.hasPrefix("requirement") }.flatMap(\.value)
        var sources: [String] = []
        for round in 0..<8_000 {
            let mutated = mutations.mutated(originals[round % originals.count], pieces: pieces)
            sources.append(round % 2 == 0 ? mutated : GraphTextMutations.ascii(mutated))
        }
        XCTAssertGreaterThan(Self.assertReadAlike(sources), 6_000)
    }

    /// `style`, `class`, `:::` and `classDef` in every order on requirements and elements that share names, classes
    /// given twice, `default` defined and given, unknown names, and declarations that set a color and a fill.
    func testStylesAndClassesInEveryOrderAreAppliedAlike() {
        let statements = [
            "requirement a {\n}", "element a {\n}", "element b {\n}", "classDef c fill:#f00,color:red", "classDef default stroke:#0f0",
            "class a,b c", "class b c", "a:::c,default", "b:::d", "style a,x,b fill:#00f", "style b color:#fff,fill:#000", "classDef c,d font-size:9px",
            "class x c", "classDef d color:blue", "requirement b {\n}",
        ]
        var sources: [String] = []
        var mutations = GraphTextMutations(seed: 47)
        var seeded = RequirementRandomTexts(seed: 47)
        for _ in 0..<600 {
            var shuffled = statements
            for index in shuffled.indices.reversed() { shuffled.swapAt(index, mutations.below(index + 1)) }
            sources.append("requirementDiagram\n" + shuffled.joined(separator: "\n") + "\n" + seeded.text(statementCount: 4).dropFirst(18))
        }
        XCTAssertEqual(Self.assertReadAlike(sources), sources.count)
    }

    func testLimitsRefuseAlike() {
        var generator = RequirementRandomTexts(seed: 53)
        let source = (0..<6).map { _ in generator.text(statementCount: 30) }.joined(separator: "\n").replacingOccurrences(of: "requirementDiagram\n", with: "")
        let text = "requirementDiagram\n" + source + "\nclassDef big " + Array(repeating: "a:b", count: 400).joined(separator: ",")
            + String(repeating: "\nclass test_req,r2,e1,x big", count: 900)
        let standard = MermaidDiagramLimits.standard
        for (nodes, edges, bytes) in [(3, 500, standard.maximumSourceBytes), (500, 4, standard.maximumSourceBytes), (500, 500, 100),
                                      (500, 500, standard.maximumSourceBytes)] {
            let limits = MermaidDiagramLimits(maximumSourceBytes: bytes, maximumNodeCount: nodes, maximumEdgeCount: edges,
                                              maximumLayoutPointCount: standard.maximumLayoutPointCount)
            XCTAssertEqual(Self.assertReadAlike([text], limits: limits), 1)
        }
    }

    /// Long lines, thousands of requirements and relations with names that share all but their last bytes, many styles
    /// and classes, long style lists and many direction statements: read as the reference reads them, and a text ten
    /// times as long in at most forty times the time.
    func testHostileTextsAreReadAlikeInTimeThatGrowsWithTheirLength() {
        func hostile(_ count: Int) -> [String] {
            let prefix = String(repeating: "n", count: 40)
            let names = (0..<count).map { index in "\(prefix)\(index)" }
            return [
                "requirementDiagram\n" + names.map { name in "requirement \(name) {\nid: 1\ntext: t\n}" }.joined(separator: "\n") + "\n"
                    + names.enumerated().map { index, name in "\(name) - satisfies -> \(names[(index * 7) % count])" }.joined(separator: "\n"),
                "requirementDiagram\nrequirement a {\ntext: " + String(repeating: "word ", count: count * 4) + "\n}",
                "requirementDiagram\n" + names.map { name in "element \(name) {\n}" }.joined(separator: "\n") + "\nclass "
                    + names.joined(separator: ",") + " c\nclassDef c fill:#f00,color:red\nstyle " + names.joined(separator: ",") + " stroke:#000",
                "requirementDiagram\n" + (0..<count).map { index in "direction LR\nelement e\(index) {\n}" }.joined(separator: "\n"),
                "requirementDiagram\n" + String(repeating: "a", count: count * 20) + " - copies -> " + String(repeating: "b", count: count * 20),
                "requirementDiagram\n" + (0..<count).map { index in "classDef k\(index) fill:#\(index % 10)\(index % 10)\(index % 10)" }.joined(separator: "\n"),
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

    /// Requirements, elements and classes whose 8,192 names collide in the name table's hash's low bits for every basis
    /// are read as the reference reads them, ten times the names in at most forty times the time.
    func testNamesThatShareTheHashsLowBitsAreReadAlikeAndInTime() {
        func diagram(_ names: [String]) -> String {
            "requirementDiagram\n" + names.map { name in "requirement \(name) {\n}" }.joined(separator: "\n") + "\n"
                + names.enumerated().map { index, name in "\(name) - traces -> \(names[(index &* 7 &+ 1) % names.count])" }.joined(separator: "\n")
                + "\n" + names.prefix(64).map { name in "\(name):::\(name)" }.joined(separator: "\n")
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
    /// requirement, element or class, as 0.7.0's String keys made them.
    func testSpellingsSwiftHoldsEqualNameOneNode() throws {
        let sources = [
            "requirementDiagram\nrequirement caf\u{E9} {\n}\nrequirement cafe\u{301} {\n}\ncaf\u{E9} - copies -> cafe\u{301}",
            "requirementDiagram\nelement \u{212A} {\n}\nclassDef K fill:#f00\nclass \u{212A} \u{212A}\nstyle K stroke:#000",
        ]
        XCTAssertEqual(Self.assertReadAlike(sources), sources.count)
        guard case .requirement(let first) = try MermaidDiagramReader.read(sources[0], limits: .standard) else { return XCTFail("not read") }
        XCTAssertEqual(first.requirements.count, 1)
    }

    /// The same texts read on twelve threads at once give what one thread gives.
    func testReadingsOnTwelveThreadsAtOnceAreAlike() {
        var generator = RequirementRandomTexts(seed: 59)
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

    /// Reads each source both ways and fails for each that differs; returns how many the reference read as a requirement
    /// diagram, or refused while reading one.
    @discardableResult
    static func assertReadAlike(_ sources: [String], limits: MermaidDiagramLimits = .standard, file: StaticString = #filePath, line: UInt = #line) -> Int {
        var checked = 0
        var mismatches = 0
        for source in sources {
            let reference = Result { () throws(MermaidDiagramReadError) in try ReferenceRequirementReading.read(source, limits: limits) }
            let package = Result { () throws(MermaidDiagramReadError) in try MermaidDiagramReader.read(source, limits: limits) }
            var difference: String?
            switch (reference, package) {
            case (.success(nil), _): continue
            case (.success(let expected?), .success(.requirement(let read))):
                if expected != read { difference = "read otherwise: \(read.requirements.count) requirements, \(read.relations.count) relations" }
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
