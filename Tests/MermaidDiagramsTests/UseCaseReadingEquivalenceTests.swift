/**
 * File: UseCaseReadingEquivalenceTests.swift
 * ------------------------------------------
 * Layer: Tests
 * Description: The use case reader on the text's bytes, with its names interned, against 0.7.0's reader on UTF-16
 *              code units kept as the reference: every input of the corpora and of Pele's compatibility tests,
 *              generated and random diagrams, mutated texts (beyond ASCII and kept to it), texts made to break each
 *              rule, each the same diagram field for field or the same error at the same line; hostile texts read in
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

final class UseCaseReadingEquivalenceTests: XCTestCase {
    func testEveryInputOfTheCorporaAndOfPelesCompatibilityTestsIsReadAsTheReferenceReadsIt() throws {
        let sources = try OutputDigest.corpora().flatMap(\.sources) + UseCaseCorpus.documentationExamples()
            + PeleResults.compatInputs().sorted { $0.key < $1.key }.flatMap(\.value)
        XCTAssertGreaterThan(Self.assertReadAlike(sources), 40)
        XCTAssertGreaterThan(Self.assertReadAlike(sources.map(GraphTextMutations.ascii)), 40)
    }

    func testGeneratedDiagramsAreReadAsTheReferenceReadsThem() {
        var limits = MermaidDiagramLimits.standard
        limits.maximumSourceBytes = 1_000_000
        let sources = [(3, 8, 1, 12), (10, 40, 4, 80), (20, 120, 6, 260), (40, 300, 10, 700)].map { actors, useCases, boundaries, relationships in
            UseCaseCorpus.generated(actorCount: actors, useCaseCount: useCases, boundaryCount: boundaries, relationshipCount: relationships)
        }
        XCTAssertEqual(Self.assertReadAlike(sources, limits: limits), sources.count)
    }

    func testRandomTextsAreReadAsTheReferenceReadsThem() {
        var generator = UseCaseRandomTexts(seed: 37)
        let sources = (0..<4_000).map { _ in generator.text(statementCount: 24) }
        XCTAssertGreaterThan(Self.assertReadAlike(sources), 3_500)
        XCTAssertGreaterThan(Self.assertReadAlike(sources.map(GraphTextMutations.ascii)), 3_500)
    }

    func testMutatedTextsAreReadAsTheReferenceReadsThem() throws {
        var mutations = GraphTextMutations(seed: 41)
        let pieces = GraphTextMutations.commonPieces + Self.useCasePieces
        var generator = UseCaseRandomTexts(seed: 43)
        let originals = try UseCaseCorpus.documentationExamples() + (0..<40).map { _ in generator.text(statementCount: 16) }
        var sources: [String] = []
        for round in 0..<12_000 {
            let mutated = mutations.mutated(originals[round % originals.count], pieces: pieces)
            sources.append(round % 2 == 0 ? mutated : GraphTextMutations.ascii(mutated))
        }
        XCTAssertGreaterThan(Self.assertReadAlike(sources), 10_000)
    }

    /// What the use case grammar reads apart: its keywords, operators, strings, stereotypes, metadata and JSON, with
    /// white space and line breaks JavaScript's `trim` and `^` take that ASCII's do not.
    static let useCasePieces = ["actor ", "systemBoundary ", "end", "note for ", "json J@{ \"a\": [1, {\"b\": null}] }", "classDef c fill:#f00",
                                "class A c", "style A fill:#0f0, stroke:red", "-->", "<--", "--", "--o", "o--", "--x", "x--", "--|>", "..>", ": include",
                                ": Extend", "<<", ">>", " <<Core>> ", "@{", "@{ type: hollow }", "@{ icon: \"fa:user\" }", "@{ business: true }",
                                "@{ type: package }", "@{ animate: true }", "@{ animation: slow }", "e1@", "(", ")", "[", "]", "\"`**b**`\"", "\"x y\"",
                                "'q'", ":::c", ",", "\\,", "direction TB", "accDescr {\n  a\n  b\n}", "accTitle: \u{00A0}t\u{2028}", "%% c\n", "%%{init: {}}%%\n",
                                "\u{2028}", "\u{2029}", "\u{1680}", "\u{2009}", "\u{205F}", "\u{0B}", "\u{0C}", "\u{85}", "😀", "a\u{1F600}b",
                                "\"caf\u{E9}\"", "\"cafe\u{301}\"", "(caf\u{E9})", "(cafe\u{301})", "1.5px", ".5", "#abc"]

    /// Each kind of contradiction, statement and error, and labels Swift holds equal though their bytes differ.
    func testTextsThatBreakEachRuleAreReadAlike() {
        let bodies = [
            "actor A\n  A(x)", "actor A\nA --> B\nB(\"x\")\nB(\"y\")", "\"Reset pw\"\nReset_pw", "J@{ type: rect }", "json J@{ \"a\": 1 }\njson J@{ \"b\": 2 }",
            "A e1@--> B\nC e1@--> D", "actor A@{ type: hollow }\nactor A@{ type: awesome }", "A@{ business: true }\nA@{ business: false }\nA",
            "A(x)\nA(y)", "A(x)\nA[x]", "systemBoundary S\n  A\nend\nsystemBoundary T\n  A\nend", "A <<x>>\nA <<y>>", "systemBoundary S\nend\nsystemBoundary S[t]\nend",
            "A:::c --> B", "class Q c", "style Q fill:red", "systemBoundary S\nend\nA --> S", "actor A\nA ..> : include B", "actor A\nA --|> B",
            "json J@{ \"a\": 1 }\nJ --o A", "Q@{ icon: x }", "actor A@{ icon: x, type: hollow }", "actor A@{ business: true, type: awesome }",
            "A[x]@{ business: true }", "note for Q n", "systemBoundary S\nend\nnote for S n", "json J@{ \"a\": 1, }", "json J@{ \"a\" 1 }", "json J@{ [1] }",
            "json J@{\n  \"a\": \"\u{1F600}\",\n  \"b\": x\n}", "A --> B\nA@{ animation: slow }\ne1@{ animate: true }", "A e1@--> B\ne1@{ animation: fast }",
            "A e1@--> B\ne1@{ animate: maybe }", "systemBoundary S\nend\nS@{ type: package }", "A@{ unknown: 1 }", "\"caf\u{E9}\"\n\"cafe\u{301}\"",
            "A(caf\u{E9})\nA(cafe\u{301})", "A <<caf\u{E9}>>\nA <<cafe\u{301}>>", "systemBoundary S(caf\u{E9})\nend\nsystemBoundary S(cafe\u{301})\nend",
            "classDef c fill:red\nclassDef c, d stroke:blue\nclass A, B c, d\nA --> B", "A -- \"x\" --> B", "A -- x y --o B", "A <-- x -- B", "A x-- y -- B",
            "A ----> B", "A <---- B", "A --- B", "A -- x B", "A e1@ --> B", "direction XY", "accDescr {\n   a\n\u{00A0} b\n}", "accDescr { never closed",
            "A <<", "A <<   >>", "A \"unclosed", "A --> B\n%% c\nA(\"x\"", "\n\n%% one\n%% two\nA(\"x\"", "A\r\nB\rC(", "rectangle R", "SkinParam x",
            "A@{\n\n\n}", "A@{ a: b,\n\n c: d }", "A@{ type: hollow,\n,\n}", "\"\" --> B", "\"`x`\" --> \"y\"",
            // Ids made from labels beyond ASCII: a character of four bytes is two code units, so two underscores.
            "\"a\u{1F600}b\" --> B", "\"a\u{1F600}b\"\na__b(x)", "\"a\u{E9}b\"\na_b(x)", "\"\u{1F600}\" --> \"\u{E9}\u{301}\"",
            "\"`a \u{1F600}`\"@{ business: true }\n\"`a \u{1F600}`\" --> B",
        ]
        let sources = bodies.flatMap { body in ["usecase-beta\n" + body, "usecase-beta\n" + body + "\n", "---\ntitle: T\n---\nusecase-beta\n  " + body] }
        XCTAssertEqual(Self.assertReadAlike(sources), sources.count)
    }

    func testLimitsRefuseAlike() {
        let source = UseCaseCorpus.generated(actorCount: 10, useCaseCount: 40, boundaryCount: 4, relationshipCount: 80) + "\nnote for A0 n\nnote for A1 m"
        let standard = MermaidDiagramLimits.standard
        for (nodes, edges, bytes) in [(5, 500, standard.maximumSourceBytes), (500, 7, standard.maximumSourceBytes), (54, 500, standard.maximumSourceBytes),
                                      (500, 81, standard.maximumSourceBytes), (500, 500, 100)] {
            let limits = MermaidDiagramLimits(maximumSourceBytes: bytes, maximumNodeCount: nodes, maximumEdgeCount: edges,
                                              maximumLayoutPointCount: standard.maximumLayoutPointCount)
            XCTAssertEqual(Self.assertReadAlike([source], limits: limits), 1)
        }
    }

    /// Long lines, thousands of names that share all but their last bytes, long class and style lists and many
    /// boundaries: read as the reference reads them, and a text ten times as long in at most forty times the time.
    func testHostileTextsAreReadAlikeInTimeThatGrowsWithTheirLength() {
        func hostile(_ count: Int) -> [String] {
            let prefix = String(repeating: "n", count: 40)
            let names = (0..<count).map { index in "\(prefix)\(index)" }
            let classes = (0..<count).map { index in "c\(index)" }
            return [
                "usecase-beta\n" + names.enumerated().map { index, name in "\(name) --> \(names[(index * 7) % count])" }.joined(separator: "\n"),
                "usecase-beta\nA(" + String(repeating: "word ", count: count * 4) + ")\nA --> B",
                "usecase-beta\nA --> B\nclass A, B " + classes.joined(separator: ", ") + "\nclass A " + classes.reversed().joined(separator: ","),
                "usecase-beta\nA --> B\nstyle A " + (0..<count).map { index in "p\(index):v\(index)" }.joined(separator: ", "),
                "usecase-beta\n" + (0..<count).map { index in "systemBoundary S\(index)\n  U\(index)(u)\nend" }.joined(separator: "\n"),
                "usecase-beta\n" + (0..<count).map { index in "\"label \(index) words\" --> \"other \(index % 50)\"" }.joined(separator: "\n"),
                "usecase-beta\n" + String(repeating: "a", count: count * 20) + " --> " + String(repeating: "b", count: count * 20),
                "usecase-beta\nactor " + names.joined(separator: ", "),
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

    /// The same texts read on twelve threads at once give what one thread gives.
    func testReadingsOnTwelveThreadsAtOnceAreAlike() {
        var generator = UseCaseRandomTexts(seed: 47)
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

    /// Reads each source both ways and fails for each that differs; returns how many the reference read as a use case
    /// diagram, or refused while reading one.
    @discardableResult
    static func assertReadAlike(_ sources: [String], limits: MermaidDiagramLimits = .standard, file: StaticString = #filePath, line: UInt = #line) -> Int {
        var checked = 0
        var mismatches = 0
        for source in sources {
            let reference = Result { () throws(MermaidDiagramReadError) in try ReferenceUseCaseReading.read(source, limits: limits) }
            let package = Result { () throws(MermaidDiagramReadError) in try MermaidDiagramReader.read(source, limits: limits) }
            var difference: String?
            switch (reference, package) {
            case (.success(nil), _): continue
            case (.success(let expected?), .success(.useCase(let read))): difference = ReferenceUseCaseReading.difference(read, from: expected)
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
