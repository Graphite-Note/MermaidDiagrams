/**
 * File: C4ArenaReadingTests.swift
 * -------------------------------
 * Layer: Tests
 * Description: The C4 reader with its tokens and its macros' arguments in lists on the thread's scratch arena: macros of
 *              many arguments, RelIndex's dropped number, lists past the arena's first region, a reading inside another
 *              arena scope, and readings on twelve threads at once, each as the 0.7.0 reference reads it.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 25/11/2026
 */

import Foundation
import XCTest
@testable import MermaidDiagrams
@testable import MermaidDiagramsBenchmark

final class C4ArenaReadingTests: XCTestCase {
    /// A macro of thousands of arguments grows its list past the room made for eight; RelIndex drops its first.
    func testMacrosOfManyArgumentsAreReadAlike() {
        let many = (0..<3_000).map { index in index % 3 == 0 ? "$k\(index)=\"v\"" : "\"a\(index)\"" }.joined(separator: ", ")
        let sources = [
            "C4Context\nPerson(p, \"P\", " + many + ")\nSystem(s, \"S\")\nRel(p, s, " + many + ")",
            "C4Context\nPerson(p, \"P\")\nSystem(s, \"S\")\nRelIndex(1, p, s, \"uses\")\nRelIndex(p, s)\nRelIndex(2)",
            "C4Context\nPerson(p, \"P\")\nUpdateElementStyle(p, " + many + ")\nUpdateLayoutConfig(" + many + ")",
            "C4Context\nBoundary(b, \"B\", " + many + ") {\n  Person(p, \"P\")\n}",
        ]
        XCTAssertEqual(C4ReadingEquivalenceTests.assertReadAlike(sources), sources.count)
    }

    /// A text of more tokens than the arena's first region holds reads as the reference reads it.
    func testTokensPastTheArenasFirstRegionAreReadAlike() {
        var limits = MermaidDiagramLimits.standard
        limits.maximumSourceBytes = 2_000_000
        limits.maximumNodeCount = 100_000
        limits.maximumEdgeCount = 100_000
        let source = C4Corpus.generated(shapeCount: 2_000, boundaryCount: 40, relationCount: 4_000)
        XCTAssertEqual(C4ReadingEquivalenceTests.assertReadAlike([source], limits: limits), 1)
    }

    /// A reading inside a scope of the arena that already holds lists leaves them as they were.
    func testAReadingInsideAnotherScopeLeavesItsListsAlone() throws {
        let source = try C4Corpus.documentationExamples()[0]
        let expected = try MermaidDiagramReader.read(source, limits: .standard)
        DiagramScratchArena.withCurrentThread { arena in
            var outer: ScratchList<Int> = arena.list(capacity: 4)
            for value in 0..<100 { outer.append(value) }
            XCTAssertEqual(try? MermaidDiagramReader.read(source, limits: .standard), expected)
            XCTAssertEqual(Array(outer), Array(0..<100))
        }
    }

    /// The same texts read on twelve threads at once give what one thread gives.
    func testReadingsOnTwelveThreadsAtOnceAreAlike() throws {
        var generator = C4RandomTexts(seed: 53)
        let sources = try C4Corpus.documentationExamples() + (0..<300).map { _ in generator.text() }
        let expected = sources.map { source in try? MermaidDiagramReader.read(source, limits: .standard) }
        let mismatches = ThreadSafeCount()
        DispatchQueue.concurrentPerform(iterations: 12) { _ in
            for (index, source) in sources.enumerated() where (try? MermaidDiagramReader.read(source, limits: .standard)) != expected[index] {
                mismatches.add()
            }
        }
        XCTAssertEqual(mismatches.value, 0)
    }
}
