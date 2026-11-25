/**
 * File: EntityRelationshipGenericTypeEquivalenceTests.swift
 * ---------------------------------------------------------
 * Layer: Tests
 * Description: An entity relationship attribute's type and name read with their tildes as angle brackets, the text
 *              without a tilde byte left unsearched, against 0.7.0's reading kept as the reference: random texts of
 *              tildes, commas and characters a tilde combines with, every word of the corpora, and the readings of
 *              every entity relationship input, as written and kept to ASCII.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 25/11/2026
 */

import XCTest
@testable import MermaidDiagrams
@testable import MermaidDiagramsBenchmark

final class EntityRelationshipGenericTypeEquivalenceTests: XCTestCase {
    func testRandomTextsAreReadAsTheReferenceReadsThem() {
        let pieces = ["~", "~~", ",", "List", "int", "K", "V", " ", "\u{301}", "~\u{301}", "\u{0303}", "e\u{301}", "\u{E9}", "中", "a", "[]", "\u{FF5E}"]
        var mutations = GraphTextMutations(seed: 47)
        var mismatches = 0
        for _ in 0..<30_000 {
            let text = (0..<mutations.below(10)).map { _ in pieces[mutations.below(pieces.count)] }.joined()
            for written in [text, GraphTextMutations.ascii(text)]
                where EntityRelationshipGenericType.angleBracketed(written) != ReferenceEntityRelationshipGenericType.angleBracketed(written) {
                mismatches += 1
                if mismatches <= 5 { XCTFail("\(written.debugDescription) read otherwise") }
            }
        }
        XCTAssertEqual(mismatches, 0)
    }

    func testEveryWordOfTheCorporaIsReadAsTheReferenceReadsIt() throws {
        let sources = try OutputDigest.corpora().flatMap(\.sources) + PeleResults.compatInputs().sorted { $0.key < $1.key }.flatMap(\.value)
        var words = 0
        for source in sources {
            for word in source.split(whereSeparator: { character in character == " " || character == "\n" }).map(String.init) {
                XCTAssertEqual(EntityRelationshipGenericType.angleBracketed(word), ReferenceEntityRelationshipGenericType.angleBracketed(word), word)
                words += 1
            }
        }
        XCTAssertGreaterThan(words, 10_000)
    }
}
