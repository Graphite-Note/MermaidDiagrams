/**
 * File: ArchitectureGridEquivalenceTests.swift
 * --------------------------------------------
 * Layer: Tests
 * Description: The architecture diagram's items are placed on the cells 0.7.0's grid placement gave them, on every
 *              corpus input and spec text, thousands of them changed at random, random diagrams of nested groups,
 *              junctions, edges between every pair of sides and alignments, and large ones.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 24/11/2026
 */

import XCTest
@testable import MermaidDiagrams

final class ArchitectureGridEquivalenceTests: XCTestCase {
    private static let tokens = ["service s(server)[S]\n", "service t(database)[T] in g\n", "group g(cloud)[G]\n", "group h[H] in g\n", "junction j\n",
                                 "s:R -- L:t\n", "s:T --> B:j\n", "t:L <-- R:s\n", "s{group}:B -- T:t\n", "align row s t\n", "align column s j t\n"]

    private func assertPlacedAsTheReference(_ source: String, file: StaticString = #filePath, line: UInt = #line) -> Bool {
        guard case .architecture(let diagram)? = try? MermaidDiagramReader.read(source, limits: .standard) else { return false }
        XCTAssertEqual(ArchitectureGridPlacement.grid(of: diagram), ReferenceArchitectureGridPlacement.grid(of: diagram), source, file: file, line: line)
        return true
    }

    func testEveryTextAndItsChangesArePlacedAsTheFrozenPlacementPlacedThem() throws {
        let texts = MapReadingEquivalence.texts(readAs: .architecture, among: try MapReadingEquivalence.everyText(), mutationCount: 300, tokens: Self.tokens,
                                                seed: 0xA2C_417)
        var comparedCount = 0
        for text in texts where assertPlacedAsTheReference(text) { comparedCount += 1 }
        XCTAssertGreaterThan(comparedCount, 1_000)
    }

    func testRandomDiagramsArePlacedAsTheFrozenPlacementPlacedThem() {
        var random = MapReadingMutations(seed: 0xA2C_0002, tokens: [])
        let sides = ["L", "R", "T", "B"]
        let arrows = [" -- ", " --> ", " <-- ", " <--> "]
        var comparedCount = 0
        for _ in 0..<1_500 {
            let groupCount = random.below(5)
            let serviceCount = 1 + random.below(14)
            var text = "architecture-beta\n"
            for group in 0..<groupCount {
                text += "group g\(group)[G\(group)]" + (group > 0 && random.below(2) == 0 ? " in g\(random.below(group))" : "") + "\n"
            }
            for service in 0..<serviceCount {
                let kind = random.below(5) == 0 ? "junction j\(service)" : "service s\(service)(server)[S\(service)]"
                text += kind + (groupCount > 0 && random.below(3) > 0 ? " in g\(random.below(groupCount))" : "") + "\n"
            }
            func item(_ index: Int) -> String { text.contains("junction j\(index)") ? "j\(index)" : "s\(index)" }
            for _ in 0..<random.below(2 * serviceCount + 1) {
                let first = random.below(serviceCount)
                let second = random.below(serviceCount)
                text += item(first) + (random.below(6) == 0 ? "{group}" : "") + ":" + sides[random.below(4)] + arrows[random.below(4)]
                    + sides[random.below(4)] + ":" + item(second) + "\n"
            }
            if serviceCount > 2, random.below(3) == 0 {
                text += (random.below(2) == 0 ? "align row " : "align column ") + (0..<3).map { _ in item(random.below(serviceCount)) }.joined(separator: " ") + "\n"
            }
            if assertPlacedAsTheReference(text) { comparedCount += 1 }
        }
        // About a third are refused: an edge to its own end, or between a group and a service inside it.
        XCTAssertGreaterThan(comparedCount, 900)
    }

    /// Many services in a chain and a mesh, many groups, and long alignments are placed as the frozen placement places them.
    func testLargeDiagramsArePlacedAsTheFrozenPlacementPlacedThem() {
        let chain = (0..<400).map { index in "service s\(index)[S]\n" }.joined() + (0..<399).map { index in "s\(index):R -- L:s\(index + 1)\n" }.joined()
        let mesh = (0..<120).map { index in "service s\(index)[S]\n" }.joined()
            + (0..<500).map { index in "s\(index % 120):\(["L", "R", "T", "B"][index % 4]) -- \(["R", "L", "B", "T"][index % 4]):s\((index * 37 + 11) % 120)\n" }.joined()
        let groups = (0..<150).map { index in "group g\(index)[G]" + (index > 0 ? " in g\(index - 1)" : "") + "\nservice s\(index)[S] in g\(index)\n" }.joined()
            + (0..<149).map { index in "s\(index):B -- T:s\(index + 1)\n" }.joined()
        let aligned = (0..<200).map { index in "service s\(index)[S]\n" }.joined() + "align row " + (0..<200).map { index in "s\(index)" }.joined(separator: " ") + "\n"
        for body in [chain, mesh, groups, aligned] {
            XCTAssertTrue(assertPlacedAsTheReference("architecture-beta\n" + body))
        }
    }
}
