/**
 * File: FlowchartReadingHostileInputTests.swift
 * ---------------------------------------------
 * Layer: Tests
 * Description: Texts made to make the flowchart reader slow, as large as MermaidDiagramLimits lets a text be: each is
 *              read or refused within a bound that time growing with the square of the text would pass many times
 *              over. And identifiers compared by their bytes, as Pele compares them.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 24/11/2026
 */

import XCTest
@testable import MermaidDiagrams

final class FlowchartReadingHostileInputTests: XCTestCase {
    /// Reads `source` and returns the seconds it took, read or refused.
    private func secondsToRead(_ source: String) -> Double {
        let clock = ContinuousClock()
        let start = clock.now
        _ = try? MermaidDiagramReader.read(source, limits: .standard)
        let elapsed = clock.now - start
        return Double(elapsed.components.seconds) + Double(elapsed.components.attoseconds) / 1e18
    }

    /// Each hostile text at the size limit (50,000 bytes) is read or refused in under five seconds, even in a Debug build
    /// under load: a reading growing with the square of a line this long takes minutes.
    func testHostileTextsAtTheSizeLimitAreReadInBoundedTime() {
        let maximum = MermaidDiagramLimits.standard.maximumSourceBytes
        for text in FlowchartHostileTexts.all(scale: 12_000) {
            let source = String(decoding: text.utf8.prefix(maximum - 16), as: UTF8.self)
            let seconds = secondsToRead(source)
            XCTAssertLessThan(seconds, 5, "\(source.prefix(40).debugDescription): \(seconds) s")
        }
    }

    /// A line of 25,000 `a:` pieces: each token's look-ahead is a binary search, not a scan to the line's end.
    func testALongLineOfShortTokensIsRead() throws {
        let source = "flowchart TD\n" + String(repeating: "a:", count: 24_000) + "a --> b"
        XCTAssertLessThan(secondsToRead(source), 5)
        let diagram = try FlowchartReading.flowchart(source)
        XCTAssertEqual(diagram.nodes.count, 2)
    }

    /// A link with text of 49,000 periods that never closes: each run of periods is passed whole.
    func testALongRunOfPeriodsInsideADottedLinkIsPassedOnce() {
        let source = "flowchart TD\na -. " + String(repeating: ".", count: 49_000) + " b"
        XCTAssertLessThan(secondsToRead(source), 5)
        XCTAssertEqual(FlowchartReading.readError(source), .invalidSyntax(line: 2, problem: .unclosedEdgeLabel))
    }

    /// A tag with many `="` and no closing quotation mark is read once by the preprocessing.
    func testATagOfManyUnclosedAttributesIsPreprocessedOnce() {
        let source = "flowchart TD\nA[\"<b " + String(repeating: "=\"", count: 24_000) + ">\"]"
        XCTAssertLessThan(secondsToRead(source), 5)
    }

    /// Groups nested 2,000 deep, each naming the same node: the node joins the innermost group only.
    func testDeeplyNestedGroupsTakeANodeOnce() throws {
        let depth = 2_000
        let source = "flowchart TD\n" + (0..<depth).map { index in "subgraph g\(index)\nn\n" }.joined() + String(repeating: "end\n", count: depth)
        XCTAssertLessThan(secondsToRead(source), 5)
        let diagram = try FlowchartReading.flowchart(source)
        XCTAssertEqual(diagram.subgraphs.count, depth)
        XCTAssertEqual(diagram.subgraphs.filter { group in group.nodeIndices == [0] }.count, 1)
        XCTAssertEqual(diagram.subgraphs.last?.nodeIndices, [0])
    }

    /// Two groups ended again and again under their identifiers, each time with a new node: their members grow without
    /// being copied.
    func testGroupsEndedAgainAndAgainKeepEveryMember() throws {
        let source = "flowchart TD\n" + (0..<2_000).map { index in "subgraph \(index % 2 == 0 ? "A" : "B")\nn\(index)\nend\n" }.joined()
        XCTAssertLessThan(secondsToRead(source), 5)
        let diagram = try FlowchartReading.flowchart(source)
        XCTAssertEqual(diagram.subgraphs.map(\.nodeIndices.count), [1_000, 1_000])
    }

    /// Pele compares identifiers as JavaScript compares strings, by their code units: `K` and the Kelvin sign (U+212A), a
    /// Hangul syllable and its two jamo, which Swift's strings take as equal, are two nodes each. MermaidDiagrams 0.7.0
    /// took each pair for one node.
    func testIdentifiersCanonicallyEquivalentButWrittenApartAreTwoNodes() throws {
        let source = "flowchart TD\nK --> \u{212A}\n\u{AC00} --> \u{1100}\u{1161}"
        let diagram = try FlowchartReading.flowchart(source)
        XCTAssertEqual(diagram.nodes.map { node in Array(node.identifier.unicodeScalars) }, [["K"], ["\u{212A}"], ["\u{AC00}"], ["\u{1100}", "\u{1161}"]])
        XCTAssertEqual(diagram.edges.map { edge in [edge.sourceIndex, edge.targetIndex] }, [[0, 1], [2, 3]])
        guard case .flowchart(let reference) = try ReferenceMermaidReader.read(source, limits: .standard) else { return XCTFail("not a flowchart") }
        XCTAssertEqual(reference.edges.map { edge in [edge.sourceIndex, edge.targetIndex] }, [[0, 0], [1, 1]])
    }
}

extension FlowchartReadingHostileInputTests {
    /// A reading of many names leaves the thread's name table large; the table is let go, and the next reading on the
    /// thread makes a small one and reads as before.
    func testAReadingAfterOneOfManyNamesReadsAsBefore() throws {
        var limits = MermaidDiagramLimits.standard
        limits.maximumSourceBytes = 1_000_000
        limits.maximumNodeCount = 20_000
        let many = "graph TD\n" + (0..<10_000).map { index in "n\(index)\n" }.joined()
        XCTAssertEqual(try FlowchartReading.flowchart(many, limits: limits).nodes.count, 10_000)
        XCTAssertEqual(try FlowchartReading.flowchart("graph TD\nA --> B\nB --> A").edges.map(\.targetIndex), [1, 0])
    }
}
