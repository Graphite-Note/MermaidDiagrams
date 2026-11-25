/**
 * File: BlockEdgeEndLookupTests.swift
 * -----------------------------------
 * Layer: Tests
 * Description: The block layout finds an edge's ends by their identifiers' interned numbers where 0.7.0 looked them up
 *              in a dictionary keyed by the identifiers' Strings: on the corpora, the specification texts, texts whose
 *              identifiers are canonically equivalent but written apart, `root` and the identifiers the reading makes,
 *              mutated and random texts, every edge's ends are the cells the String dictionary gives.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 24/11/2026
 */

import XCTest
@testable import MermaidDiagrams

final class BlockEdgeEndLookupTests: XCTestCase {
    /// Texts whose edges name their ends in the ways the numbers must agree with Strings on: one identifier composed
    /// and decomposed, a sign that is canonically a letter, the root, a block written `root`, a block that only waits
    /// for its declaration, a composite and a space named by the reading.
    static let identifierTexts = [
        "block\n  e\u{301} --> b\n  \u{E9}[\"composed\"]\n  b --> \u{E9}\n",
        "block\n  \u{E9} --> e\u{301}\n",
        "block\n  \u{212A} --> K\n  K[\"letter\"]\n",
        "block\n  A\u{30A} --> \u{C5}\n  \u{212B} --> b\n",
        "block\n  a --> root\n  root --> a\n",
        "block\n  root[\"written root\"] a\n  a --> root\n",
        "block\n  block:root\n    a\n  end\n  a --> root\n",
        "block\n  class waiting hot\n  waiting --> a\n  a\n",
        "block\n  style waiting fill:#f96\n  a --> waiting\n  a\n",
        "block\n  block\n    a\n  end\n  id-1 --> a\n",
        "block\n  space\n  a\n  id-1 --> a\n  id-1-0 --> a\n",
        "block\n  a b\n  a --> b\n  a --> b\n  b --> a\n  a[\"again\"]\n",
        "block\n  block:g\n    columns 2\n    a b\n  end\n  g --> a\n  b --> g\n",
        "block\n  x --> y\n",
    ]

    private func assertEdgeEndsAreThoseOfTheirStrings(_ source: String, file: StaticString = #filePath, line: UInt = #line) -> Int {
        guard let diagram = try? BlockReading.block(source) else { return 0 }
        let views = BlockViews(diagram, measurers: BlockReading.measurers, gap: 8, wrappingWidth: 200, titleWidth: 300)
        let cellsByIdentifier = views.cellIndicesByIdentifier(in: diagram)
        let model = diagram.model
        for (record, edge) in zip(model.edges, diagram.edges) {
            XCTAssertEqual(views.cellIndex(ofIdentifierNumber: record.sourceNumber, in: model), cellsByIdentifier[edge.sourceIdentifier],
                           "source of \(edge.identifier) in \(source.prefix(200))", file: file, line: line)
            XCTAssertEqual(views.cellIndex(ofIdentifierNumber: record.targetNumber, in: model), cellsByIdentifier[edge.targetIdentifier],
                           "target of \(edge.identifier) in \(source.prefix(200))", file: file, line: line)
        }
        return model.edges.count
    }

    func testIdentifiersWrittenApartFindTheCellsTheirStringsFind() {
        var edgeCount = 0
        for source in Self.identifierTexts { edgeCount += assertEdgeEndsAreThoseOfTheirStrings(source) }
        XCTAssertGreaterThanOrEqual(edgeCount, 18)
    }

    /// The composed and decomposed é are one block, as Swift's Strings are one key: the edge between them is a loop.
    func testCanonicallyEquivalentIdentifiersAreOneBlock() throws {
        let diagram = try BlockReading.block("block\n  e\u{301} --> b\n  \u{E9}[\"composed\"]\n  b --> \u{E9}\n")
        let views = BlockViews(diagram, measurers: BlockReading.measurers, gap: 8, wrappingWidth: 200, titleWidth: 300)
        let model = diagram.model
        XCTAssertEqual(model.edges[0].sourceNumber, model.edges[1].targetNumber)
        XCTAssertNotNil(views.cellIndex(ofIdentifierNumber: model.edges[0].sourceNumber, in: model))
        XCTAssertEqual(BlockReading.topBlocks(diagram).map(\.label), ["composed", "b"])
    }

    /// These texts are read as 0.7.0 read them, blocks merged by canonically equivalent identifiers alike.
    func testIdentifierTextsAreReadAsZeroSevenReadThem() {
        for source in Self.identifierTexts {
            let agrees = ChartReadingEquivalence.agree(source, keywords: ["block"], read: { (cursor, keyword) throws(MermaidDiagramReadError) in
                try BlockParser.parse(cursor, keyword: keyword, limits: .standard)
            }, reference: { (cursor, keyword) throws(MermaidDiagramReadError) in
                try ReferenceBlockParser.parse(cursor, keyword: keyword, limits: .standard)
            })
            XCTAssertEqual(agrees, true, source)
        }
    }

    /// Many distinct identifiers, beyond ASCII and decomposed among them, chained by edges up to the limits: read as
    /// 0.7.0 read them, every end found as the Strings find it, in time that grows with the text.
    func testManyDistinctIdentifiersStayBoundedAndAgree() {
        let chained = "block\n  " + (0..<2_400).map { index in "n\(index)" }.joined(separator: " --> ") + "\n"
        let accented = "block\n  " + (0..<1_200).map { index in (index % 2 == 0 ? "e\u{301}" : "\u{E9}") + "\(index / 2)" }.joined(separator: " --> ") + "\n"
        let long = "block\n  " + (0..<200).map { index in String(repeating: "\u{3B1}", count: 100) + "\(index)" }.joined(separator: " --> ") + "\n"
        for source in [chained, accented, long] {
            let started = Date()
            let agrees = ChartReadingEquivalence.agree(source, keywords: ["block"], read: { (cursor, keyword) throws(MermaidDiagramReadError) in
                try BlockParser.parse(cursor, keyword: keyword, limits: .standard)
            }, reference: { (cursor, keyword) throws(MermaidDiagramReadError) in
                try ReferenceBlockParser.parse(cursor, keyword: keyword, limits: .standard)
            })
            XCTAssertEqual(agrees, true, String(source.prefix(80)))
            XCTAssertGreaterThan(assertEdgeEndsAreThoseOfTheirStrings(source), 190)
            XCTAssertLessThan(Date().timeIntervalSince(started), 5, String(source.prefix(80)))
        }
    }

    func testEveryCorpusAndSpecificationTextFindsTheCellsTheStringsFind() throws {
        var edgeCount = 0
        let sources = try ChartReadingEquivalence.corpusSources(keywords: ["block", "block-beta"]) + BlockReadingEquivalenceTests.specificationTexts
        for source in sources { edgeCount += assertEdgeEndsAreThoseOfTheirStrings(source) }
        XCTAssertGreaterThanOrEqual(edgeCount, 15)
    }

    func testMutatedAndRandomTextsFindTheCellsTheStringsFind() throws {
        var mutations = ChartTextMutations(seed: 0xED6E_E7D5)
        var edgeCount = 0
        for source in try ChartReadingEquivalence.corpusSources(keywords: ["block", "block-beta"]) + Self.identifierTexts {
            for _ in 0..<30 {
                edgeCount += assertEdgeEndsAreThoseOfTheirStrings(mutations.mutated(source))
                edgeCount += assertEdgeEndsAreThoseOfTheirStrings(mutations.spliced(source))
            }
        }
        var random = BlockRandomStatements(seed: 0xB10C_ED6E)
        for index in 0..<600 { edgeCount += assertEdgeEndsAreThoseOfTheirStrings(random.text(statementCount: 1 + index % 30)) }
        XCTAssertGreaterThan(edgeCount, 1_000)
    }
}
