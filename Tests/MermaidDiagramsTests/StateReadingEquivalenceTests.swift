/**
 * File: StateReadingEquivalenceTests.swift
 * ----------------------------------------
 * Layer: Tests
 * Description: The state diagram reader on the text's bytes against 0.7.0's reader kept as the reference: every input
 *              of the corpora and of Pele's compatibility tests, generated machines, random and mutated texts (beyond
 *              ASCII and kept to it), each the same diagram, field for field, or the same error; hostile texts read
 *              in time that grows with their length, and readings on many threads at once alike.
 *
 * Authors: Bahey Shalash
 * Version: 0.2
 * Date: 25/11/2026
 */

import Foundation
import XCTest
@testable import MermaidDiagrams
@testable import MermaidDiagramsBenchmark

final class StateReadingEquivalenceTests: XCTestCase {
    func testEveryInputOfTheCorporaAndOfPelesCompatibilityTestsIsReadAsTheReferenceReadsIt() throws {
        let sources = try OutputDigest.corpora().flatMap(\.sources) + PeleResults.compatInputs().sorted { $0.key < $1.key }.flatMap(\.value)
        XCTAssertGreaterThan(Self.assertReadAlike(sources), 40)
        XCTAssertGreaterThan(Self.assertReadAlike(sources.map(GraphTextMutations.ascii)), 40)
    }

    func testGeneratedMachinesAreReadAsTheReferenceReadsThem() {
        let sources = [1, 10, 80, 400].flatMap { count in [0, count / 2, count * 2].map { extra in StateDiagramCorpus.machine(stateCount: count, extraTransitionCount: extra) } }
        XCTAssertEqual(Self.assertReadAlike(sources), sources.count)
    }

    func testRandomTextsAreReadAsTheReferenceReadsThem() {
        var generator = StateRandomTexts(seed: 23)
        let sources = (0..<3_000).map { _ in generator.text(statementCount: 24) }
        XCTAssertGreaterThan(Self.assertReadAlike(sources), 2_500)
        XCTAssertGreaterThan(Self.assertReadAlike(sources.map(GraphTextMutations.ascii)), 2_500)
    }

    func testMutatedTextsAreReadAsTheReferenceReadsThem() throws {
        var mutations = GraphTextMutations(seed: 29)
        let pieces = GraphTextMutations.commonPieces + ["-->", "[*]", "state ", "note left of ", "note right of ", "end note", "<<fork>>", "[[join]]",
                                                        "<<choice>>", "hide empty description", "scale 2", "state \"t\" as ", " as X:y", "  A : x",
                                                        // Bytes Foundation trims as white space or line breaks that the reader's byte tests do not.
                                                        "\u{0B}", "\u{0C}", "\u{85}", " as X\u{0B}", " as X\u{0C}:y"]
        let originals = try StateDiagramCorpus.documentationExamples() + PeleResults.compatInputs().filter { $0.key.hasPrefix("state") }.flatMap(\.value)
        var sources: [String] = []
        for round in 0..<6_000 {
            let mutated = mutations.mutated(originals[round % originals.count], pieces: pieces)
            sources.append(round % 2 == 0 ? mutated : GraphTextMutations.ascii(mutated))
        }
        XCTAssertGreaterThan(Self.assertReadAlike(sources), 4_000)
    }

    /// The vertical tab and the form feed, which Foundation trims from a declaration's quoted text but not from the
    /// identifier after `as`, are trimmed and kept as 0.7.0 trimmed and kept them, in ASCII texts and beyond.
    func testDeclarationsTrimAsFoundationTrims() {
        var sources: [String] = []
        for space in ["\u{0B}", "\u{0C}", "\u{85}", "\r", "\t"] {
            sources += [
                "stateDiagram-v2\n  state \"t\" as X\(space):y\n  X --> Z",
                "stateDiagram-v2\n  state \"t\" as \(space)X:y\n  X --> Z",
                "stateDiagram-v2\n  state \"\(space)t\(space)\" as X\n  X --> Z",
                "stateDiagram-v2\n  state \"t\" as X:\(space)y\(space)\n  X --> Z",
                "stateDiagram-v2\n  state \"t\" as X\(space) {\n    [*] --> X\n  }",
            ]
        }
        XCTAssertEqual(Self.assertReadAlike(sources), sources.count)
    }

    func testLimitsRefuseAlike() {
        let source = StateDiagramCorpus.machine(stateCount: 60, extraTransitionCount: 60) + "\n  note left of S1 : n\n  state Big {\n    [*] --> In\n  }"
        let standard = MermaidDiagramLimits.standard
        for (nodes, edges, bytes) in [(5, 500, standard.maximumSourceBytes), (500, 7, standard.maximumSourceBytes), (61, 500, standard.maximumSourceBytes),
                                      (500, 500, 100)] {
            let limits = MermaidDiagramLimits(maximumSourceBytes: bytes, maximumNodeCount: nodes, maximumEdgeCount: edges,
                                              maximumLayoutPointCount: standard.maximumLayoutPointCount)
            XCTAssertEqual(Self.assertReadAlike([source], limits: limits), 1)
        }
    }

    /// Long lines, thousands of states with names that share all but their last bytes, deep composites and many notes:
    /// read as the reference reads them, and a text ten times as long in at most forty times the time.
    func testHostileTextsAreReadAlikeInTimeThatGrowsWithTheirLength() {
        func hostile(_ count: Int) -> [String] {
            let prefix = String(repeating: "n", count: 40)
            let names = (0..<count).map { index in "\(prefix)\(index)" }
            return [
                "stateDiagram-v2\n" + names.enumerated().map { index, name in "  \(name) --> \(names[(index * 7) % count]) : t" }.joined(separator: "\n"),
                "stateDiagram-v2\n  A : " + String(repeating: "word_ ", count: count * 4) + "\n  A --> B",
                "stateDiagram-v2\n" + (0..<min(count, 400)).map { index in String(repeating: " ", count: index) + "state S\(index) {" }.joined(separator: "\n")
                    + "\n[*] --> X\n" + String(repeating: "}\n", count: min(count, 400)),
                "stateDiagram-v2\n" + (0..<count).map { index in "  note left of S\(index % 50)\n    line \(index)\n  end note" }.joined(separator: "\n"),
                "stateDiagram\n" + String(repeating: "a", count: count * 20) + " --> " + String(repeating: "b", count: count * 20),
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

    /// The same texts read on eight threads at once give what one thread gives.
    func testReadingsOnManyThreadsAtOnceAreAlike() {
        var generator = StateRandomTexts(seed: 31)
        let sources = (0..<400).map { index in index % 2 == 0 ? generator.text(statementCount: 20) : GraphTextMutations.ascii(generator.text(statementCount: 20)) }
        let expected = sources.map { source in try? MermaidDiagramReader.read(source, limits: .standard) }
        let mismatches = ThreadSafeCount()
        DispatchQueue.concurrentPerform(iterations: 8) { _ in
            for (index, source) in sources.enumerated() where (try? MermaidDiagramReader.read(source, limits: .standard)) != expected[index] {
                mismatches.add()
            }
        }
        XCTAssertEqual(mismatches.value, 0)
    }

    /// Reads each source both ways and fails for each that differs; returns how many the reference read as a state
    /// diagram, or refused while reading one.
    @discardableResult
    static func assertReadAlike(_ sources: [String], limits: MermaidDiagramLimits = .standard, file: StaticString = #filePath, line: UInt = #line) -> Int {
        var checked = 0
        var mismatches = 0
        for source in sources {
            let reference = Result { () throws(MermaidDiagramReadError) in try ReferenceStateReading.read(source, limits: limits) }
            let package = Result { () throws(MermaidDiagramReadError) in try MermaidDiagramReader.read(source, limits: limits) }
            var difference: String?
            switch (reference, package) {
            case (.success(nil), _): continue
            case (.success(let expected?), .success(.stateDiagram(let read))):
                if expected != read { difference = "read otherwise: \(read.states.count) states, \(read.transitions.count) transitions" }
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

/// A count several threads add to.
final class ThreadSafeCount: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0

    func add() {
        lock.lock()
        count += 1
        lock.unlock()
    }

    var value: Int {
        lock.lock()
        defer { lock.unlock() }
        return count
    }
}
