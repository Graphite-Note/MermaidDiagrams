/**
 * File: FlowchartLayoutRecordsTests.swift
 * ---------------------------------------
 * Layer: Tests
 * Description: A flowchart's layout kept as flat records gives back the nodes and edges it was made from, to the bit,
 *              is laid out as the 0.7.0 engine lays it out on twelve threads at once and for hostile flowcharts, and
 *              places texts written in many storages, in any order, where they were.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 26/11/2026
 */

import CoreGraphics
import Foundation
import XCTest
@testable import MermaidDiagrams
@testable import MermaidDiagramsBenchmark

final class FlowchartLayoutRecordsTests: XCTestCase {
    private static var typography: DiagramTypography { DiagramSceneSamples.typography }

    /// Every corpus flowchart's layout, its nodes and edges read as values and made into a layout again: the same values
    /// to the bit, equal as layouts, and the same scene.
    func testALayoutMadeFromItsValuesGivesTheSameValuesBack() throws {
        var flowchartCount = 0
        for diagram in try Self.corpusFlowcharts() {
            guard let layout = try? FlowchartLayoutEngine.layout(diagram, typography: Self.typography, limits: .standard) else { continue }
            flowchartCount += 1
            let remade = FlowchartLayout(size: layout.size, font: layout.font, nodes: layout.nodes, edges: layout.edges, title: layout.title,
                                         clusters: layout.clusters)
            XCTAssertEqual(FlowchartLayoutBits { remade }, FlowchartLayoutBits { layout })
            XCTAssertEqual(remade, layout)
            XCTAssertEqual(DiagramSVGWriter().document(of: DiagramScene(layout: remade), diagramType: "flowchart"),
                           DiagramSVGWriter().document(of: DiagramScene(layout: layout), diagramType: "flowchart"))
        }
        XCTAssertGreaterThan(flowchartCount, 280)
    }

    /// Layouts that differ in one node's place, one edge's point or one text are not equal.
    func testLayoutsThatDifferInOnePieceAreNotEqual() throws {
        let layout = try FlowchartLayoutEngine.layout(FlowchartReading.flowchart("flowchart TD\n  A[Start] -->|go| B(End)\n"), typography: Self.typography,
                                                      limits: .standard)
        var nodes = layout.nodes
        let node = nodes[0]
        nodes[0] = FlowchartLayoutNode(shape: node.shape, frame: node.frame.offsetBy(dx: 0.5, dy: 0), text: node.text, style: node.style, asset: node.asset)
        XCTAssertNotEqual(FlowchartLayout(size: layout.size, font: layout.font, nodes: nodes, edges: layout.edges, title: layout.title,
                                          clusters: layout.clusters), layout)
        var edges = layout.edges
        let edge = edges[0]
        var path = edge.path
        path.start = CGPoint(x: path.start.x, y: path.start.y + 1)
        edges[0] = FlowchartLayoutEdge(stroke: edge.stroke, path: path, sourceMark: edge.sourceMark, targetMark: edge.targetMark, text: nil, style: edge.style)
        XCTAssertNotEqual(FlowchartLayout(size: layout.size, font: layout.font, nodes: layout.nodes, edges: edges, title: layout.title,
                                          clusters: layout.clusters), layout)
    }

    /// Twelve threads lay out the corpus flowcharts at once, each as the 0.7.0 engine lays it out.
    func testTheLayoutIsTheReferencesOnTwelveThreadsAtOnce() throws {
        let diagrams = try Self.corpusFlowcharts()
        let expected = diagrams.map { diagram in
            FlowchartLayoutBits { try ReferenceFlowchartLayoutEngine.layout(diagram, typography: Self.typography, limits: .standard) }
        }
        let mismatches = ThreadSafeCount()
        DispatchQueue.concurrentPerform(iterations: 12) { thread in
            for round in 0..<60 {
                let index = (thread * 29 + round * 7) % diagrams.count
                let laidOut = FlowchartLayoutBits { try FlowchartLayoutEngine.layout(diagrams[index], typography: Self.typography, limits: .standard) }
                if laidOut != expected[index] { mismatches.add() }
            }
        }
        XCTAssertEqual(mismatches.value, 0)
    }

    /// Long texts in storages of their own between short ones, many nodes and edges, loops, deep groups: laid out as the
    /// reference lays them out.
    func testHostileFlowchartsAreLaidOutAsTheReferenceLaysThemOut() throws {
        let longText = String(repeating: "word ", count: 1_200)
        var alternating = "flowchart LR\n"
        for index in 0..<60 {
            alternating += index % 2 == 0 ? "  n\(index)[\"\(longText)\(index)\"] -->|\(longText)| n\(index + 1)\n" : "  n\(index) -->|short| n\(index + 1)\n"
        }
        var loops = "flowchart TD\n"
        for index in 0..<200 { loops += "  a\(index) --> a\(index)\n  a\(index) -->|back \(index)| a\(index)\n  a\(index) --> a\(index + 1)\n" }
        var nested = "flowchart TD\n"
        for depth in 0..<40 { nested += String(repeating: " ", count: depth) + "subgraph g\(depth) [group \(depth)]\n  x\(depth) --> y\(depth)\n" }
        for _ in 0..<40 { nested += "end\n" }
        let sources = [alternating, loops, nested, FlowchartCorpus.tree(nodeCount: 1_500), FlowchartCorpus.mesh(nodeCount: 400, extraEdgeCount: 300)]
        for source in sources {
            guard case .flowchart(let diagram)? = try? MermaidDiagramReader.read(source, limits: .standard) else { continue }
            for spacing in [DiagramSpacing.standard, .compact] {
                let laidOut = FlowchartLayoutBits { try FlowchartLayoutEngine.layout(diagram, typography: Self.typography, limits: .standard, spacing: spacing) }
                let reference = FlowchartLayoutBits {
                    try ReferenceFlowchartLayoutEngine.layout(diagram, typography: Self.typography, limits: .standard, spacing: spacing)
                }
                XCTAssertEqual(laidOut, reference, String(source.prefix(120)))
            }
        }
    }

    /// Blocks written in many storages (texts larger than a quarter of a storage get one each), placed in an order that
    /// goes back and forth between them: each placed text gives back its block, and placing stays fast.
    func testTextsInManyStoragesArePlacedAndReadBackWhereTheyWere() {
        let measurer = Self.typography.nodeText
        var blocks: [DiagramTextBlock] = []
        for index in 0..<400 {
            let text = index % 3 == 0 ? String(repeating: "long text \(index) ", count: 400) : "short \(index)"
            blocks.append(DiagramTextBlock(label: DiagramLabel(text), measurer: measurer, maximumWidth: 200))
        }
        let distinct = Set(blocks.map { block in ObjectIdentifier(block.storage) }).count
        XCTAssertGreaterThan(distinct, 100, "the long texts are in storages of their own")
        var order = Array(blocks.indices)
        var generator = SeededShuffleGenerator(seed: 0x5EED)
        order.shuffle(using: &generator)
        var storages = DiagramPlacedTextStorages()
        let start = Date()
        for _ in 0..<20 {
            var placed: [(DiagramPlacedText, Int)] = []
            for index in order { placed.append((storages.place(blocks[index]), index)) }
            for (text, index) in placed {
                var original = blocks[index]
                original.center = .zero
                XCTAssertEqual(storages.block(text), original)
            }
        }
        XCTAssertEqual(storages.count, distinct)
        XCTAssertLessThan(Date().timeIntervalSince(start), 20, "placing stays linear in the storages")
    }

    private static func corpusFlowcharts() throws -> [FlowchartDiagram] {
        var sources = try OutputDigest.corpora().flatMap(\.sources)
        sources += try FlowchartCorpus.documentationExamples()
        return sources.compactMap { source in
            guard case .flowchart(let diagram)? = try? MermaidDiagramReader.read(source, limits: .standard) else { return nil }
            return diagram
        }
    }
}

/// A small seeded generator, so that a shuffled order is the same on every run.
private struct SeededShuffleGenerator: RandomNumberGenerator {
    var state: UInt64

    init(seed: UInt64) {
        state = seed
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var value = state
        value = (value ^ (value >> 30)) &* 0xBF58_476D_1CE4_E5B9
        value = (value ^ (value >> 27)) &* 0x94D0_49BB_1331_11EB
        return value ^ (value >> 31)
    }
}
