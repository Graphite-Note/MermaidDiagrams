/**
 * File: FlowchartModelEquivalenceTests.swift
 * ------------------------------------------
 * Layer: Tests
 * Description: The gate of the reading redesign: every corpus input, every text of Mermaid's flowchart specs and of
 *              Pele's compatibility inputs, the generated graphs, hostile texts and ten thousand mutations of the
 *              documentation's examples read into the same flowchart, or fail with the same error on the same line,
 *              as with MermaidDiagrams 0.7.0's frozen reader.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 24/11/2026
 */

import XCTest
@testable import MermaidDiagrams
@testable import MermaidDiagramsBenchmark

final class FlowchartModelEquivalenceTests: XCTestCase {
    /// The differences found in `sources`, each with the start of its text, at most `limit` of them.
    private func differences(in sources: [String], limits: MermaidDiagramLimits = .standard, limit: Int = 5) -> [String] {
        var found: [String] = []
        for source in sources {
            guard let difference = FlowchartReadingEquivalence.difference(source, limits: limits) else { continue }
            found.append("\(difference) in \(String(source.prefix(160)).debugDescription)")
            if found.count == limit { break }
        }
        return found
    }

    func testEveryCorpusInputReadsAsTheReferenceReadsIt() throws {
        let sources = try OutputDigest.corpora().flatMap(\.sources)
        XCTAssertGreaterThan(sources.count, 800)
        XCTAssertEqual(differences(in: sources), [])
    }

    func testEveryFlowchartSpecTextReadsAsTheReferenceReadsIt() throws {
        let sources = try PeleResults.flowchartSpecTexts().map(\.source)
        XCTAssertGreaterThan(sources.count, 900)
        XCTAssertEqual(differences(in: sources), [])
    }

    func testEveryCompatibilityInputReadsAsTheReferenceReadsIt() throws {
        let sources = try PeleResults.compatInputs().sorted { first, second in first.key < second.key }.flatMap(\.value)
        XCTAssertGreaterThan(sources.count, 100)
        XCTAssertEqual(differences(in: sources), [])
    }

    func testDocumentationExamplesAndGeneratedGraphsReadAsTheReferenceReadsThem() throws {
        let sources = try FlowchartCorpus.documentationExamples() + PeleResults.generatedBenchmarkInputs.map(\.source)
            + PeleResults.sources(ofCorpus: "random-flat")
        XCTAssertEqual(differences(in: sources), [])
    }

    /// Ten thousand texts made from the documentation's examples by cutting lines, splicing pieces and inserting the
    /// tokens the reader treats apart: most are refused, and every one reads or fails as the reference does.
    func testMutatedExamplesReadAsTheReferenceReadsThem() throws {
        let examples = try FlowchartCorpus.documentationExamples()
        var mutations = FlowchartReadingMutations(seed: 0x5EED_0F_F10C)
        var sources: [String] = []
        sources.reserveCapacity(10_000)
        for index in 0..<10_000 { sources.append(mutations.mutated(examples[index % examples.count])) }
        XCTAssertEqual(differences(in: sources), [])
    }

    /// Ten thousand flowcharts written at random from a pool of names and statements: names in a group and the group
    /// around it, groups ended again under one identifier or named as nodes, styles before and after their nodes.
    func testRandomFlowchartsReadAsTheReferenceReadsThem() {
        var texts = FlowchartRandomTexts(seed: 0x6A0_0F_6A0)
        var sources: [String] = []
        for _ in 0..<10_000 { sources.append(texts.text(statementCount: 14)) }
        var readCount = 0
        for source in sources where (try? MermaidDiagramReader.read(source, limits: .standard)) != nil { readCount += 1 }
        XCTAssertGreaterThan(readCount, 3_000, "most random texts should read, so that their models are compared")
        XCTAssertEqual(differences(in: sources), [])
    }

    /// Small limits make the readers stop at the same node or edge.
    func testLimitsStopBothReadersAtTheSamePlace() throws {
        var limits = MermaidDiagramLimits.standard
        limits.maximumSourceBytes = 400
        limits.maximumNodeCount = 4
        limits.maximumEdgeCount = 3
        let sources = try FlowchartCorpus.documentationExamples() + PeleResults.generatedBenchmarkInputs.map(\.source)
        XCTAssertEqual(differences(in: sources, limits: limits), [])
    }

    /// Texts made to be slow to read: long lines of short tokens, many links, deep nesting, many groups ended under
    /// one name, many `@` and `direction`s.
    func testHostileTextsReadAsTheReferenceReadsThem() {
        XCTAssertEqual(differences(in: FlowchartHostileTexts.all(scale: 2_000)), [])
    }
}

/// Texts made to make a reader slow: each grows with `scale`.
enum FlowchartHostileTexts {
    static func all(scale: Int) -> [String] {
        [
            "flowchart TD\n" + String(repeating: "a:", count: scale) + "a",
            "flowchart TD\n" + String(repeating: "&", count: scale),
            "flowchart TD\n" + String(repeating: "a@", count: scale) + "-->b",
            "flowchart TD\n" + String(repeating: "@", count: scale),
            "flowchart TD\n" + String(repeating: "a ", count: scale) + "direction LR",
            "flowchart TD\n" + String(repeating: "direction LR ", count: scale / 10),
            "flowchart TD\n" + (0..<scale).map { index in "n\(index) --> n\(index + 1)" }.joined(separator: "\n"),
            "flowchart TD\n" + (0..<scale).map { index in "n\(index % 50) -->|t| n\((index * 7) % 50)" }.joined(separator: "\n"),
            "flowchart TD\n" + String(repeating: "subgraph g\n", count: scale / 10) + "a\n" + String(repeating: "end\n", count: scale / 10),
            "flowchart TD\n" + (0..<scale / 4).map { index in "subgraph \(index % 2 == 0 ? "A" : "B")\nn\(index)\nend" }.joined(separator: "\n"),
            "flowchart TD\n" + "a -- " + String(repeating: ".", count: scale) + " b",
            "flowchart TD\n" + "a -. " + String(repeating: ".", count: scale) + " b",
            "flowchart TD\n" + "a[" + String(repeating: "x", count: scale * 4),
            "flowchart TD\n" + "a@{ label: \"" + String(repeating: "y", count: scale * 4),
            "flowchart TD\n" + String(repeating: "a & ", count: scale / 2) + "b --> " + String(repeating: "c & ", count: 40) + "d",
            "flowchart TD\n" + String(repeating: "classDef c fill:#f00\n", count: scale / 10) + String(repeating: "a:::c\n", count: scale / 10),
            "flowchart TD\n" + String(repeating: "\u{2028}a", count: scale),
            "flowchart TD\n" + String(repeating: "中", count: scale) + " --> b",
        ]
    }
}
