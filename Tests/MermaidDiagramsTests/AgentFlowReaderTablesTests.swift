/**
 * File: AgentFlowReaderTablesTests.swift
 * --------------------------------------
 * Layer: Tests
 * Description: The tables the agent flow reader on bytes keeps instead of String-keyed dictionaries: the edge counts by
 *              pair of names against a dictionary, with pairs that share a name, mirror each other or crowd one start,
 *              and the shape names found by their bytes, every one and none other; names that collide in the name
 *              table's hash read alike and in time.
 *
 * Authors: Bahey Shalash
 * Version: 0.2
 * Date: 26/11/2026
 */

import Foundation
import XCTest
@testable import MermaidDiagrams

final class AgentFlowReaderTablesTests: XCTestCase {
    /// Counts set and read back as a dictionary keeps them: pairs that mirror each other, many pairs from one start and
    /// to one end, numbers far apart, the table grown many times.
    func testPairCountsAreADictionarysCounts() {
        DiagramScratchArena.withCurrentThread { arena in checkPairCounts(in: arena) }
    }

    private func checkPairCounts(in arena: DiagramScratchArena) {
        var counts = AgentFlowPairCounts(arena: arena)
        var expected: [Int64: Int] = [:]
        var generator = SystemRandomNumberGenerator()
        func key(_ start: Int32, _ end: Int32) -> Int64 { Int64(start) << 32 | Int64(end) }
        var pairs: [(Int32, Int32)] = []
        for index in 0..<3_000 { pairs += [(0, Int32(index)), (Int32(index), 0), (Int32(index), Int32(index)), (Int32(index), Int32(index) + 1)] }
        for _ in 0..<5_000 { pairs.append((Int32.random(in: 0..<100_000, using: &generator), Int32.random(in: 0..<100_000, using: &generator))) }
        pairs += [(Int32.max - 1, Int32.max - 1), (Int32.max - 1, 0), (0, Int32.max - 1)]
        for (round, pair) in (pairs + pairs.reversed()).enumerated() {
            XCTAssertEqual(counts.count(pair.0, pair.1), expected[key(pair.0, pair.1)] ?? 0)
            counts.set(pair.0, pair.1, to: round % 7 + 1)
            expected[key(pair.0, pair.1)] = round % 7 + 1
        }
        for pair in pairs { XCTAssertEqual(counts.count(pair.0, pair.1), expected[key(pair.0, pair.1)]) }
        XCTAssertEqual(counts.count(5, 100_001), 0)
    }

    /// Edges between the same two nodes and between mirrored pairs are numbered as 0.7.0 numbered them, in a text of
    /// thousands of edges read in time that grows with it.
    func testEdgesBetweenTheSamePairsAreNumberedAlike() {
        var lines = ["agentflow-beta"]
        for index in 0..<2_000 { lines += ["  a --> n\(index % 40)", "  n\(index % 40) --> a", "  n\(index % 7) --> n\(index % 11)"] }
        let limits = MermaidDiagramLimits(maximumSourceBytes: 10_000_000, maximumNodeCount: 100_000, maximumEdgeCount: 100_000, maximumLayoutPointCount: 1_000_000)
        XCTAssertEqual(AgentFlowReadingEquivalenceTests.assertReadAlike([lines.joined(separator: "\n")], limits: limits), 1)
    }

    /// Every shape name is found by its bytes, and no other spelling: prefixes, longer words, other cases.
    func testShapeNamesAreFoundByTheirBytesAlone() {
        for (number, name) in AgentFlowShapeNames.names.enumerated() {
            XCTAssertEqual(AgentFlowShapeNames.number(of: Array(name.utf8)[...]), Int16(number), name)
            XCTAssertEqual(AgentFlowShapeNames.number(name), Int16(number), name)
            for other in [String(name.dropLast()), name + "x", "x" + name, name.uppercased(), name.capitalized] where !AgentFlowShapeNames.names.contains(other) {
                XCTAssertEqual(AgentFlowShapeNames.number(of: Array(other.utf8)[...]), -1, other)
            }
        }
        XCTAssertEqual(AgentFlowShapeNames.number(of: [][...]), -1)
        XCTAssertGreaterThan(AgentFlowShapeNames.names.count, 100)
        XCTAssertEqual(Set(AgentFlowShapeNames.names).count, AgentFlowShapeNames.names.count)
    }

    /// Agent flows whose 8,192 node names, and so the edges' made identifiers (`L_start_end_0`), collide in the name
    /// table's hash's low bits for every basis are read as the reference reads them, and in time that grows with their
    /// count: ten times the names in at most forty times the time. Each text ends by looking up an identifier that could
    /// be a made one, which names every edge's identifier in the table.
    func testNamesThatShareTheHashsLowBitsAreReadAlikeAndInTime() {
        func flow(_ names: [String]) -> String {
            "agentflow-beta\n" + names.enumerated().map { index, name in "  \(name) --> \(names[(index &* 7 &+ 1) % names.count])" }.joined(separator: "\n")
                + "\n  L_\(names[0])_\(names[1])_0@{ curve: linear }\n  class L_\(names[1])_\(names[2])_0 hot"
        }
        let limits = MermaidDiagramLimits(maximumSourceBytes: 10_000_000, maximumNodeCount: 100_000, maximumEdgeCount: 100_000,
                                          maximumLayoutPointCount: 1_000_000)
        let caseVariants = GraphDiagramNameTableTests.caseVariants(of: "abcdefghijklm")
        let highBitVariants = GraphDiagramNameTableTests.highBitVariants(count: caseVariants.count)
        let sources = [flow(caseVariants), flow(highBitVariants), flow((0..<caseVariants.count).map { index in "node\(index)" })]
        XCTAssertEqual(AgentFlowReadingEquivalenceTests.assertReadAlike(sources, limits: limits), sources.count)
        func seconds(_ source: String) -> Double {
            let start = Date()
            for _ in 0..<3 { _ = try? MermaidDiagramReader.read(source, limits: limits) }
            return Date().timeIntervalSince(start)
        }
        for names in [caseVariants, highBitVariants] {
            let small = flow(Array(names.prefix(names.count / 10)))
            _ = seconds(small)
            XCTAssertLessThan(seconds(flow(names)), max(seconds(small), 0.002) * 40)
        }
    }
}
