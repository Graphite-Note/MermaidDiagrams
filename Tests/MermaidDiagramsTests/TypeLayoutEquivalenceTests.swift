/**
 * File: TypeLayoutEquivalenceTests.swift
 * --------------------------------------
 * Layer: Tests
 * Description: The faster layout passes of single types give exactly the numbers of the passes they replace, kept as
 *              references: Sankey placements of random flows, Venn spots and circle placements of random sets.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 23/11/2026
 */

import XCTest
@testable import MermaidDiagrams

final class TypeLayoutEquivalenceTests: XCTestCase {
    /// A small seeded generator, so that every run tries the same cases.
    private struct SeededGenerator: RandomNumberGenerator {
        var state: UInt64

        mutating func next() -> UInt64 {
            state &+= 0x9E37_79B9_7F4A_7C15
            var mixed = state
            mixed = (mixed ^ (mixed >> 30)) &* 0xBF58_476D_1CE4_E5B9
            mixed = (mixed ^ (mixed >> 27)) &* 0x94D0_49BB_1331_11EB
            return mixed ^ (mixed >> 31)
        }
    }

    // MARK: - Sankey

    /// Random flows between up to 14 nodes, each link from an earlier node to a later one, so that there is no cycle;
    /// values from a few, so that bands and nodes tie, some not a number or zero.
    private func randomSankeyRows(_ generator: inout SeededGenerator) -> String {
        let nodeCount = Int.random(in: 2...14, using: &generator)
        let linkCount = Int.random(in: 1...(nodeCount * 3), using: &generator)
        let values = ["1", "2", "3", "2.5", "10", "0.5", "7", "none", "0"]
        var rows: [String] = []
        for _ in 0..<linkCount {
            let source = Int.random(in: 0..<(nodeCount - 1), using: &generator)
            let target = Int.random(in: (source + 1)..<nodeCount, using: &generator)
            rows.append("n\(source),n\(target),\(values.randomElement(using: &generator) ?? "1")")
        }
        return "sankey\n" + rows.joined(separator: "\n")
    }

    func testRandomSankeyFlowsGetExactlyTheReferencePlacement() throws {
        var generator = SeededGenerator(state: 2_026_11_23)
        let alignments: [SankeyNodeAlignment] = [.justify, .left, .right, .center]
        var compared = 0
        for _ in 0..<600 {
            let diagram = try SankeyReading.diagram(randomSankeyRows(&generator))
            let options = SankeyPlacement.Options(width: [600, 280, 1200].randomElement(using: &generator) ?? 600,
                                                  height: [400, 120, 900].randomElement(using: &generator) ?? 400,
                                                  nodeWidth: 10, nodePadding: [12, 0, 40].randomElement(using: &generator) ?? 12,
                                                  labelHeight: [0, 14, 30].randomElement(using: &generator) ?? 0,
                                                  alignment: alignments.randomElement(using: &generator) ?? .justify)
            let placement = try SankeyPlacement(diagram: diagram, options: options)
            let reference = try SankeyPlacementReference(diagram: diagram, options: options)
            XCTAssertEqual(placement.columns, reference.columns)
            XCTAssertEqual(placement.nodes.count, reference.nodes.count)
            for (node, expected) in zip(placement.nodes, reference.nodes) {
                XCTAssertEqual(node.layer, expected.layer)
                XCTAssertEqual(node.value.bitPattern, expected.value.bitPattern)
                XCTAssertEqual(node.x.bitPattern, expected.x.bitPattern)
                XCTAssertEqual(node.y.bitPattern, expected.y.bitPattern)
                XCTAssertEqual(node.height.bitPattern, expected.height.bitPattern)
            }
            XCTAssertEqual(placement.links.count, reference.links.count)
            for (link, expected) in zip(placement.links, reference.links) {
                XCTAssertEqual(link.thickness.bitPattern, expected.thickness.bitPattern)
                XCTAssertEqual(link.sourceY.bitPattern, expected.sourceY.bitPattern)
                XCTAssertEqual(link.targetY.bitPattern, expected.targetY.bitPattern)
            }
            compared += 1
        }
        XCTAssertEqual(compared, 600)
    }

    // MARK: - Venn

    private func randomCircles(_ generator: inout SeededGenerator, count: Int) -> [VennCircle] {
        (0..<count).map { index in
            VennCircle(identifier: "S\(index)", x: Double.random(in: -3...3, using: &generator), y: Double.random(in: -3...3, using: &generator),
                       radius: Double.random(in: 0.4...2.5, using: &generator))
        }
    }

    func testRandomVennRegionsGetExactlyTheReferenceSpot() {
        var generator = SeededGenerator(state: 19_11_2026)
        for _ in 0..<1_500 {
            let count = Int.random(in: 1...6, using: &generator)
            let circles = randomCircles(&generator, count: count)
            let order = Array(circles.indices).shuffled(using: &generator)
            let insideCount = Int.random(in: 1...count, using: &generator)
            let inside = Array(order.prefix(insideCount))
            let outside = Array(order.dropFirst(insideCount).filter { _ in Bool.random(using: &generator) })
            let spot = VennRegionSpot.find(in: circles, inside: inside, outside: outside)
            let reference = VennRegionSpotReference.find(in: circles, inside: inside, outside: outside)
            XCTAssertEqual(spot.x.bitPattern, reference.x.bitPattern)
            XCTAssertEqual(spot.y.bitPattern, reference.y.bitPattern)
            XCTAssertEqual(spot.margin.bitPattern, reference.margin.bitPattern)
        }
    }

    /// Random sets of 2 to 9 circles (and one of 70, past the table's reach), random sizes and overlaps, some of three.
    func testRandomVennSetsGetExactlyTheReferenceCircles() throws {
        var generator = SeededGenerator(state: 23_11_2026)
        var cases: [[VennSubset]] = []
        for _ in 0..<300 {
            let count = Int.random(in: 2...9, using: &generator)
            cases.append(randomVennSubsets(&generator, count: count))
        }
        cases.append(randomVennSubsets(&generator, count: 70))
        for subsets in cases {
            let placement = try VennCirclePlacement(subsets: subsets, limits: .standard)
            let reference = try VennCirclePlacementReference(subsets: subsets, limits: .standard)
            XCTAssertEqual(placement.circles.count, reference.circles.count)
            for (circle, expected) in zip(placement.circles, reference.circles) {
                XCTAssertEqual(circle.identifier, expected.identifier)
                XCTAssertEqual(circle.x.bitPattern, expected.x.bitPattern)
                XCTAssertEqual(circle.y.bitPattern, expected.y.bitPattern)
                XCTAssertEqual(circle.radius.bitPattern, expected.radius.bitPattern)
            }
        }
    }

    private func randomVennSubsets(_ generator: inout SeededGenerator, count: Int) -> [VennSubset] {
        let names = (0..<count).map { index in "S\(index)" }
        var subsets = names.map { name in VennSubset(sets: [name], size: Double.random(in: 1...40, using: &generator).rounded(), label: nil) }
        for _ in 0..<Int.random(in: 0...(count * 2), using: &generator) {
            let size = Bool.random(using: &generator) ? 3 : 2
            let members = Array(names.shuffled(using: &generator).prefix(size)).sorted()
            subsets.append(VennSubset(sets: members, size: Double.random(in: 0...8, using: &generator).rounded(), label: nil))
        }
        return subsets
    }
}
