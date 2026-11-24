/**
 * File: RailroadLayoutEquivalenceTests.swift
 * ------------------------------------------
 * Layer: Tests
 * Description: The railroad layout, which places each rule half a point over as it goes, lays every railroad text out
 *              exactly as MermaidDiagrams 0.7.0's frozen layout, which moved each placed rule afterwards: every corpus
 *              input, the generated grammars, mutated examples, and the narrow columns Graphite lays them out in.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 24/11/2026
 */

import XCTest
@testable import MermaidDiagrams
@testable import MermaidDiagramsBenchmark

final class RailroadLayoutEquivalenceTests: XCTestCase {
    private static var typography: DiagramTypography { DiagramSceneSamples.typography }

    /// The texts whose layouts differ from the reference's, at most five; texts that are not railroad diagrams are
    /// skipped, and how many were laid out is returned with them.
    private func differences(in sources: [String]) -> (laidOut: Int, differences: [String]) {
        var found: [String] = []
        var laidOut = 0
        let typography = Self.typography
        for source in sources {
            guard case .railroad(let diagram) = try? MermaidDiagramReader.read(source, limits: .standard) else { continue }
            laidOut += 1
            if RailroadLayoutEngine.layout(diagram, typography: typography) != ReferenceRailroadLayoutEngine.layout(diagram, typography: typography) {
                found.append("regular layout of \(String(source.prefix(120)).debugDescription)")
            }
            for width: CGFloat in [120, 280, 390, 600]
            where RailroadLayoutEngine.layout(diagram, typography: typography, columnWidth: width)
                != ReferenceRailroadLayoutEngine.layout(diagram, typography: typography, columnWidth: width) {
                found.append("\(width) pt layout of \(String(source.prefix(120)).debugDescription)")
            }
            if found.count >= 5 { break }
        }
        return (laidOut, found)
    }

    func testEveryCorpusInputIsLaidOutAsTheReferenceLaysItOut() throws {
        let (laidOut, found) = differences(in: try OutputDigest.corpora().flatMap(\.sources))
        XCTAssertGreaterThanOrEqual(laidOut, 14)
        XCTAssertEqual(found, [])
    }

    func testGeneratedGrammarsAreLaidOutAsTheReferenceLaysThemOut() throws {
        let (laidOut, found) = differences(in: [12, 60, 200].map { ruleCount in RailroadCorpus.generated(ruleCount: ruleCount) })
        XCTAssertEqual(laidOut, 3)
        XCTAssertEqual(found, [])
    }

    /// Four thousand texts made from the railroad examples by cutting lines, splicing pieces and inserting tokens.
    func testMutatedExamplesAreLaidOutAsTheReferenceLaysThemOut() throws {
        let examples = try PeleResults.sources(ofCorpus: "railroad-docs")
        var mutations = FlowchartReadingMutations(seed: 0x4A_11_40_AD)
        var sources: [String] = []
        for index in 0..<4_000 { sources.append(mutations.mutated(examples[index % examples.count])) }
        let (laidOut, found) = differences(in: sources)
        XCTAssertGreaterThan(laidOut, 400, "enough mutated texts should still read, so that their layouts are compared")
        XCTAssertEqual(found, [])
    }
}
