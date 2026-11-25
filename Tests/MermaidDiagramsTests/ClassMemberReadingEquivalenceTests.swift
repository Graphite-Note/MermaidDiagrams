/**
 * File: ClassMemberReadingEquivalenceTests.swift
 * ----------------------------------------------
 * Layer: Tests
 * Description: A class member's text read on its bytes against 0.7.0's reading kept as the reference: every line of
 *              every corpus input and compatibility test, every line of random class diagrams, and random texts of
 *              the pieces a member's reading treats apart, as written and kept to ASCII, each the same member.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 25/11/2026
 */

import Foundation
import XCTest
@testable import MermaidDiagrams
@testable import MermaidDiagramsBenchmark

final class ClassMemberReadingEquivalenceTests: XCTestCase {
    func testEveryLineOfTheCorporaIsReadAsTheReferenceReadsIt() throws {
        let sources = try OutputDigest.corpora().flatMap(\.sources) + PeleResults.compatInputs().sorted { $0.key < $1.key }.flatMap(\.value)
        var generator = ClassRandomTexts(seed: 41)
        let random = (0..<2_000).map { _ in generator.text(statementCount: 20) }
        let lines = (sources + random).flatMap { source in source.split(separator: "\n").map { line in ClassDiagramMemberSyntax.trimmed(String(line)) } }
        XCTAssertGreaterThan(Self.assertReadAlike(lines + lines.map(GraphTextMutations.ascii)), 20_000)
    }

    func testRandomMemberTextsAreReadAsTheReferenceReadsThem() {
        let pieces = ["+", "-", "#", "~", "$", "*", "(", ")", ",", " ", "  ", "\t", "\n", "List~int~", "Map~K,V~", "~T~", "name", "get", ":", ";",
                      "&amp;", "#59;", "#quot;", "&lt;", "int", "String[]", "é", "e\u{301}", "中", "\u{00A0}", "<<", ">>", "~~", ",,", "()", "($)",
                      "(*)", " $", " *", "x y"]
        var mutations = GraphTextMutations(seed: 43)
        var texts: [String] = []
        for _ in 0..<40_000 {
            texts.append((0..<(1 + mutations.below(9))).map { _ in pieces[mutations.below(pieces.count)] }.joined())
        }
        XCTAssertEqual(Self.assertReadAlike(texts + texts.map(GraphTextMutations.ascii)), 80_000)
    }

    /// A long member of thousands of tildes and commas reads alike, ten times as long in at most forty times the time.
    func testLongMembersAreReadAlikeInTimeThatGrowsWithTheirLength() {
        func member(_ count: Int) -> String { "+get(" + String(repeating: "List~int~, ", count: count) + ") " + String(repeating: "~a~", count: count) + "$" }
        XCTAssertEqual(Self.assertReadAlike([member(200), member(2_000)]), 2)
        func seconds(_ text: String) -> Double {
            let start = Date()
            for _ in 0..<5 { _ = ClassDiagramMemberSyntax.member(from: text) }
            return Date().timeIntervalSince(start)
        }
        _ = seconds(member(200))
        XCTAssertLessThan(seconds(member(2_000)), max(seconds(member(200)), 0.002) * 40)
    }

    @discardableResult
    static func assertReadAlike(_ texts: [String], file: StaticString = #filePath, line: UInt = #line) -> Int {
        var mismatches = 0
        for text in texts {
            let read = ClassDiagramMemberSyntax.member(from: text)
            let expected = ReferenceClassDiagramMemberSyntax.member(from: text)
            if read.member != expected.member || read.isMethod != expected.isMethod {
                mismatches += 1
                if mismatches <= 5 { XCTFail("\(text.debugDescription): \(read) where the reference reads \(expected)", file: file, line: line) }
            }
        }
        XCTAssertEqual(mismatches, 0, file: file, line: line)
        return texts.count
    }
}
