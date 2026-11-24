/**
 * File: TypeLayoutEquivalenceTests.swift
 * --------------------------------------
 * Layer: Tests
 * Description: The faster layout passes of single types give exactly the numbers of the passes they replace, kept as
 *              references: Sankey placements of random flows, Venn spots and circle placements of random sets, block
 *              grids measured and placed, and the XY chart's numbers written.
 *
 * Authors: Bahey Shalash
 * Version: 0.2
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

    /// Fans of 21 to 60 bands into and out of one node, and columns of as many nodes: past 20 elements Swift's sort
    /// searches for runs instead of inserting, so a list already in order is left as it is by a different path.
    private func randomSankeyFanRows(_ generator: inout SeededGenerator) -> String {
        let fanCount = Int.random(in: 21...60, using: &generator)
        let values = ["1", "2", "3", "2.5", "10", "0.5", "7", "none", "0"]
        var rows: [String] = []
        for index in 0..<fanCount {
            rows.append("in\(index),hub,\(values.randomElement(using: &generator) ?? "1")")
            rows.append("hub,out\(index),\(values.randomElement(using: &generator) ?? "1")")
            if Bool.random(using: &generator) {
                rows.append("out\(index),last\(Int.random(in: 0..<3, using: &generator)),\(values.randomElement(using: &generator) ?? "1")")
            }
        }
        return "sankey\n" + rows.joined(separator: "\n")
    }

    func testWideSankeyFansGetExactlyTheReferencePlacement() throws {
        var generator = SeededGenerator(state: 24_11_2026)
        let alignments: [SankeyNodeAlignment] = [.justify, .left, .right, .center]
        var longestList = 0
        for _ in 0..<120 {
            let diagram = try SankeyReading.diagram(randomSankeyFanRows(&generator))
            let options = SankeyPlacement.Options(width: [600, 1200].randomElement(using: &generator) ?? 600,
                                                  height: [400, 120, 2400].randomElement(using: &generator) ?? 400,
                                                  nodeWidth: 10, nodePadding: [12, 0, 4].randomElement(using: &generator) ?? 12,
                                                  labelHeight: [0, 14].randomElement(using: &generator) ?? 0,
                                                  alignment: alignments.randomElement(using: &generator) ?? .justify)
            let placement = try SankeyPlacement(diagram: diagram, options: options)
            let reference = try SankeyPlacementReference(diagram: diagram, options: options)
            longestList = max(longestList, placement.columns.map(\.count).max() ?? 0)
            XCTAssertEqual(placement.columns, reference.columns)
            XCTAssertEqual(placement.nodes.map(\.y.bitPattern), reference.nodes.map(\.y.bitPattern))
            XCTAssertEqual(placement.nodes.map(\.height.bitPattern), reference.nodes.map(\.height.bitPattern))
            XCTAssertEqual(placement.links.map(\.sourceY.bitPattern), reference.links.map(\.sourceY.bitPattern))
            XCTAssertEqual(placement.links.map(\.targetY.bitPattern), reference.links.map(\.targetY.bitPattern))
        }
        XCTAssertGreaterThan(longestList, 20, "the fans should make columns longer than Swift's insertion sort handles")
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

    // MARK: - Block

    /// A random block diagram: a few columns or none, blocks of every kind (shapes, spaces, wide blocks, arrows and
    /// composites with their own columns), some styled or of a class, and edges between them.
    private func randomBlockSource(_ generator: inout SeededGenerator) -> String {
        var lines = ["block"]
        if Bool.random(using: &generator) { lines.append("  columns \(Int.random(in: 1...4, using: &generator))") }
        let shapes = ["[\"Box %\"]", "(\"Round %\")", "((\"Circle %\"))", "{\"Diamond %\"}", "[(\"Store %\")]", ">\"Flag %\"]",
                      "{{\"Hexagon %\"}}", "([\"Stadium %\"])", "[\"A longer label for % that wraps\"]", ""]
        var identifiers: [String] = []
        var compositeCount = 0
        func addBlocks(_ count: Int, indent: String) {
            for _ in 0..<count {
                let choice = Int.random(in: 0..<10, using: &generator)
                let identifier = "b\(identifiers.count)"
                switch choice {
                case 0: lines.append(indent + (Bool.random(using: &generator) ? "space" : "space:2"))
                case 1: lines.append(indent + identifier + "<[\"Go\"]>(" + ["right", "left", "up", "down", "x"].randomElement(using: &generator)! + ")")
                    identifiers.append(identifier)
                case 2 where compositeCount < 3 && indent.count < 6:
                    compositeCount += 1
                    let composite = "g\(compositeCount)"
                    lines.append(indent + "block:" + composite + (Bool.random(using: &generator) ? ":2" : ""))
                    if Bool.random(using: &generator) { lines.append(indent + "  columns \(Int.random(in: 1...3, using: &generator))") }
                    addBlocks(Int.random(in: 1...4, using: &generator), indent: indent + "  ")
                    lines.append(indent + "end")
                    identifiers.append(composite)
                default:
                    let shape = shapes.randomElement(using: &generator)!.replacingOccurrences(of: "%", with: "\(identifiers.count)")
                    lines.append(indent + identifier + shape + (Int.random(in: 0..<5, using: &generator) == 0 ? ":2" : ""))
                    identifiers.append(identifier)
                }
            }
        }
        addBlocks(Int.random(in: 1...12, using: &generator), indent: "  ")
        lines.append("  classDef hot fill:#f96,stroke:#333,font-weight:bold")
        for identifier in identifiers where Int.random(in: 0..<4, using: &generator) == 0 {
            lines.append(Bool.random(using: &generator) ? "  style \(identifier) fill:#9cf,color:#fff,font-size:20px" : "  class \(identifier) hot")
        }
        for _ in 0..<Int.random(in: 0...4, using: &generator) where identifiers.count > 1 {
            lines.append("  \(identifiers.randomElement(using: &generator)!) --> \(identifiers.randomElement(using: &generator)!)")
        }
        return lines.joined(separator: "\n")
    }

    func testRandomBlockGridsAreMeasuredAndPlacedExactlyAsTheReferenceDoes() throws {
        var generator = SeededGenerator(state: 15_3_2026)
        var compared = 0
        for _ in 0..<400 {
            guard let diagram = try? BlockReading.block(randomBlockSource(&generator)) else { continue }
            let views = BlockViews(diagram, measurers: BlockReading.measurers, gap: 8, wrappingWidth: 200, titleWidth: 300)
            let reference = BlockViewsReference(diagram, measurers: BlockReading.measurers, gap: 8, wrappingWidth: 200, titleWidth: 300)
            XCTAssertEqual(views.parentIndices, reference.parentIndices)
            XCTAssertEqual(views.cellIndicesByIdentifier, reference.cellIndicesByIdentifier)
            assertSameCells(views.cells, reference.cells)
            assertSameViews(views.views, reference.views)
            var placement = BlockPlacement(views, gap: 8)
            var referencePlacement = BlockPlacementReference(reference, gap: 8)
            for _ in 0..<2 {
                try placement.place()
                try referencePlacement.place()
                XCTAssertEqual(placement.contentSize, referencePlacement.contentSize)
                XCTAssertEqual(placement.outlines, referencePlacement.outlines)
                XCTAssertEqual(placement.obstacleIndices, referencePlacement.obstacleIndices)
                XCTAssertEqual(placement.titles.map(\.center), referencePlacement.titles.map(\.center))
                XCTAssertEqual(placement.titles.map(\.size), referencePlacement.titles.map(\.size))
                assertSameCells(placement.cells, referencePlacement.cells)
                assertSameViews(placement.views, referencePlacement.views)
                placement.clearGaps()
                referencePlacement.clearGaps()
            }
            compared += 1
        }
        XCTAssertGreaterThan(compared, 300)
    }

    private func assertSameCells(_ cells: [BlockCell], _ reference: [BlockCell], line: UInt = #line) {
        XCTAssertEqual(cells.count, reference.count, line: line)
        for (cell, expected) in zip(cells, reference) {
            XCTAssertEqual(cell.childIndices, expected.childIndices, line: line)
            XCTAssertEqual([cell.columns, cell.span, cell.column, cell.row, cell.columnCount],
                           [expected.columns, expected.span, expected.column, expected.row, expected.columnCount], line: line)
            XCTAssertEqual(cell.isSpace, expected.isSpace, line: line)
            XCTAssertEqual([cell.titleHeight, cell.neededWidth, cell.neededHeight, cell.width, cell.height],
                           [expected.titleHeight, expected.neededWidth, expected.neededHeight, expected.width, expected.height], line: line)
            XCTAssertEqual(cell.rowHeights, expected.rowHeights, line: line)
            XCTAssertEqual(cell.center, expected.center, line: line)
        }
    }

    private func assertSameViews(_ views: [BlockView], _ reference: [BlockView], line: UInt = #line) {
        XCTAssertEqual(views.count, reference.count, line: line)
        for (view, expected) in zip(views, reference) {
            XCTAssertEqual(view.blockIndex, expected.blockIndex, line: line)
            XCTAssertEqual(view.kind, expected.kind, line: line)
            XCTAssertEqual(view.text, expected.text, line: line)
            XCTAssertEqual(view.appearance, expected.appearance, line: line)
            XCTAssertEqual(view.textOffset, expected.textOffset, line: line)
            XCTAssertEqual(view.drawnSize, expected.drawnSize, line: line)
        }
    }

    // MARK: - XY chart

    /// Whole numbers small and large, either sign and zero of either sign, halves, steps of marks and numbers past the
    /// whole numbers' shortcut: written as JavaScript writes them, as before.
    func testTheXYChartsNumbersAreWrittenAsJavaScriptWritesThem() {
        var generator = SeededGenerator(state: 6_4_2026)
        var values: [Double] = [0, -0.0, 1, -1, 0.5, -0.5, 1e15 - 1, 1e15, -1e15, 1e15 + 2, 1e21, 1e-7, .nan, .infinity, -.infinity,
                                Double(Int64.max), 123_456_789_012_345]
        for _ in 0..<5_000 {
            let magnitude = pow(10, Double(Int.random(in: -8...17, using: &generator)))
            let whole = (Double.random(in: -1...1, using: &generator) * magnitude).rounded()
            values.append(whole)
            values.append(whole / 4)
            values.append(Double(Int.random(in: -40...40, using: &generator)) * [0.1, 0.2, 0.25, 0.5, 2, 5, 1000].randomElement(using: &generator)!)
        }
        for value in values {
            XCTAssertEqual(XYChartScaleMarks.numberText(value), JavaScriptNumberText.text(value), "\(value)")
        }
    }
}
