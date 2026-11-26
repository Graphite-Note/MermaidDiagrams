/**
 * File: SwimlaneLayoutEquivalenceTests.swift
 * ------------------------------------------
 * Layer: Tests
 * Description: The swimlane layout made in the scratch arena (its graph written as spans, its edges moved onto the page
 *              as they are made) against the 0.7.0 swimlane layout kept as the reference: every swimlane diagram of the
 *              corpora, random and changed ones and hostile ones, regular, tight and fitted to columns, on twelve
 *              threads at once, alike to the bit; and the graph itself box for box.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 26/11/2026
 */

import CoreGraphics
import XCTest
@testable import MermaidDiagrams
@testable import MermaidDiagramsBenchmark

final class SwimlaneLayoutEquivalenceTests: XCTestCase {
    static let columnWidths: [CGFloat] = [180, 320, 520, 900]

    func testEverySwimlaneOfTheCorporaIsLaidOutAsTheReferenceLaysItOut() throws {
        let diagrams = try Self.corpusDiagrams()
        XCTAssertGreaterThan(diagrams.count, 12)
        XCTAssertEqual(Self.mismatches(among: diagrams, fittedToColumns: true), 0)
    }

    func testRandomAndChangedSwimlanesAreLaidOutAsTheReferenceLaysThemOut() throws {
        var generator = RandomSwimlaneTexts(seed: 77)
        var sources = (0..<600).map { _ in generator.text() }
        var mutations = C4RandomTexts(seed: 31)
        let originals = try PeleResults.sources(ofCorpus: "swimlane-docs")
            + PeleResults.compatInputs().filter { $0.key.hasPrefix("swimlane/") }.sorted { $0.key < $1.key }.flatMap(\.value)
        for round in 0..<600 { sources.append(mutations.mutated(originals[round % originals.count])) }
        let diagrams = sources.compactMap(Self.swimlane(of:))
        XCTAssertGreaterThan(diagrams.count, 700)
        XCTAssertEqual(Self.mismatches(among: diagrams, fittedToColumns: false), 0)
    }

    func testHostileSwimlanesAreLaidOutAsTheReferenceLaysThemOut() {
        let diagrams = SwimlaneHostileTexts.all.compactMap(Self.swimlane(of:))
        XCTAssertEqual(diagrams.count, SwimlaneHostileTexts.all.count)
        XCTAssertEqual(Self.mismatches(among: diagrams, fittedToColumns: false), 0)
    }

    func testTheGraphHoldsTheReferenceGraphsBoxesAndEdges() throws {
        let typography = DiagramSceneSamples.typography
        var generator = RandomSwimlaneTexts(seed: 3)
        let sources = try PeleResults.sources(ofCorpus: "swimlane-docs") + (0..<300).map { _ in generator.text() } + SwimlaneHostileTexts.all
        var compared = 0
        for written in sources.compactMap(Self.swimlane(of:)) {
            let diagram = FlowchartCollapsedGroups.collapsing(written)
            for isTight in [false, true] {
                let measured = SwimlaneLayoutEngine.measurement(of: diagram, nodeText: typography.nodeText, edgeText: typography.edgeText, isTight: isTight)
                let reference = ReferenceSwimlaneGraph(diagram: diagram, measured: measured, titleText: typography.nodeText, titleWidth: 150, isTight: isTight,
                                                       edgeTextRoom: FlowchartLayoutEngine.edgeTextRoom)
                let alike = DiagramScratchArena.withCurrentThread { arena in
                    let graph = SwimlaneGraph(diagram: diagram, measured: measured, titleText: typography.nodeText, titleWidth: 150, isTight: isTight,
                                              edgeTextRoom: FlowchartLayoutEngine.edgeTextRoom, arena: arena)
                    return Self.graphsAlike(graph, reference)
                }
                XCTAssertTrue(alike, "the graph differs for\(isTight ? " tight" : ""):\n\(written.title ?? "")")
                compared += 1
            }
        }
        XCTAssertGreaterThan(compared, 600)
    }

    func testTheLayoutIsTheReferencesOnTwelveThreadsAtOnce() throws {
        let typography = DiagramSceneSamples.typography
        var generator = RandomSwimlaneTexts(seed: 12)
        let diagrams = try Self.corpusDiagrams() + (0..<40).map { _ in generator.text() }.compactMap(Self.swimlane(of:))
        let expected = diagrams.map { diagram in Self.bits(ReferenceSwimlaneLayoutEngine.layout(diagram, typography: typography)) }
        let mismatches = ThreadSafeCount()
        DispatchQueue.concurrentPerform(iterations: 12) { thread in
            for round in 0..<30 {
                let index = (thread * 11 + round) % diagrams.count
                if Self.bits(SwimlaneLayoutEngine.layout(diagrams[index], typography: DiagramSceneSamples.typography)) != expected[index] { mismatches.add() }
            }
        }
        XCTAssertEqual(mismatches.value, 0)
    }

    // MARK: - Helpers

    static func corpusDiagrams() throws -> [FlowchartDiagram] {
        try OutputDigest.corpora().flatMap(\.sources).compactMap(swimlane(of:))
    }

    static func swimlane(of source: String) -> FlowchartDiagram? {
        guard case .swimlane(let diagram)? = try? MermaidDiagramReader.read(source, limits: .standard) else { return nil }
        return diagram
    }

    /// How many of the diagrams' layouts, regular and tight, as written and turned (and, when asked, fitted to columns),
    /// differ from the reference's; the first few are reported.
    static func mismatches(among diagrams: [FlowchartDiagram], fittedToColumns: Bool) -> Int {
        let typography = DiagramSceneSamples.typography
        var mismatches = 0
        func compare(_ laidOut: SwimlaneLayout, _ reference: SwimlaneLayout, _ what: String) {
            guard bits(laidOut) != bits(reference) else { return }
            mismatches += 1
            if mismatches <= 5 { XCTFail("the swimlane layout differs, \(what)") }
        }
        for written in diagrams {
            for diagram in [written, written.swimlaneTurnedToRunDown].compactMap({ diagram in diagram }) {
                for spacing in [DiagramSpacing.standard, .compact] {
                    for columnWidth in [nil, CGFloat(300)] {
                        compare(SwimlaneLayoutEngine.layout(diagram, typography: typography, spacing: spacing, columnWidth: columnWidth),
                                ReferenceSwimlaneLayoutEngine.layout(diagram, typography: typography, spacing: spacing, columnWidth: columnWidth),
                                "\(spacing), column \(String(describing: columnWidth))")
                    }
                }
            }
            guard fittedToColumns else { continue }
            for width in columnWidths {
                compare(SwimlaneLayoutEngine.layout(written, typography: typography, availableWidth: width),
                        ReferenceSwimlaneLayoutEngine.layout(written, typography: typography, availableWidth: width), "fitted to \(width)")
            }
        }
        return mismatches
    }

    /// Every number, text and choice of a swimlane layout as bit patterns and descriptions.
    static func bits(_ layout: SwimlaneLayout) -> FlowchartLayoutBits {
        var bits = FlowchartLayoutBits { layout.flowchart }
        bits.bits.append(UInt64(layout.lanes.count))
        for lane in layout.lanes {
            bits.add(lane.frame)
            bits.add(lane.titleBand)
            bits.add(lane.title)
            bits.bits.append(lane.isTitleTurned ? 1 : 0)
        }
        return bits
    }

    static func graphsAlike(_ graph: SwimlaneGraph, _ reference: ReferenceSwimlaneGraph) -> Bool {
        let boxes = graph.graph.boxes
        let edges = graph.graph.edges
        guard boxes.count == reference.graph.boxes.count, edges.count == reference.graph.edges.count,
              graph.graph.direction == reference.graph.direction, graph.graph.lanePadding == reference.graph.lanePadding,
              Array(graph.subgraphBoxes) == reference.subgraphBoxes, Array(graph.nodeBoxes) == reference.nodeBoxes,
              graph.looseLaneBox == reference.looseLaneBox, graph.titles == reference.titles else { return false }
        for (box, expected) in zip(boxes, reference.graph.boxes) {
            guard box.size == expected.size, box.parent == expected.parent, box.isGroup == expected.isGroup, box.padding == expected.padding,
                  box.minimumWidth.bitPattern == expected.minimumWidth.bitPattern else { return false }
        }
        for (edge, expected) in zip(edges, reference.graph.edges) {
            guard edge.source == expected.source, edge.target == expected.target, edge.minimumRankSpan == expected.minimumRankSpan,
                  edge.labelSize == expected.labelSize else { return false }
        }
        let nesting = reference.nesting
        return (0..<nesting.nodeSubgraphs.count).allSatisfy { node in
            graph.nesting.nodeSubgraphs[node] == (nesting.nodeSubgraphs[node] ?? -1)
                && graph.nesting.representedSubgraphs[node] == (nesting.representedSubgraphs[node] ?? -1)
        } && (0..<nesting.subgraphParents.count).allSatisfy { group in
            graph.nesting.subgraphParents[group] == (nesting.subgraphParents[group] ?? -1) && graph.nesting.subgraphDepths[group] == nesting.subgraphDepths[group]
        }
    }
}

/// Swimlanes made to be hard: long lines, many lanes and steps, groups nested deep inside a lane, many groups at once
/// (which the group order walks), loops (some of them invisible, which the loops after them do not count) and repeated
/// handoffs.
enum SwimlaneHostileTexts {
    static let all: [String] = [longLabel, manySteps, deepNesting, manyGroups, loopsAndRepeats]

    static var longLabel: String {
        "swimlane-beta LR\n  subgraph lane[Lane]\n    a[\(String(repeating: "word ", count: 3_000))]\n    b[\(String(repeating: "x", count: 8_000))]\n  end\n  a --> b"
    }

    static var manySteps: String {
        var lines = ["swimlane-beta"]
        for lane in 0..<24 {
            lines.append("  subgraph lane\(lane)[Lane \(lane)]")
            for step in 0..<20 { lines.append("    s\(lane)_\(step)[Step \(step)]") }
            lines.append("  end")
        }
        for lane in 0..<24 { for step in 0..<19 { lines.append("  s\(lane)_\(step) --> s\((lane + 1) % 24)_\(step + 1)") } }
        return lines.joined(separator: "\n")
    }

    static var deepNesting: String {
        var lines = ["swimlane-beta TB", "  subgraph lane[Lane]"]
        for depth in 0..<60 { lines.append(String(repeating: " ", count: depth) + "  subgraph g\(depth)[Group \(depth)]\n    n\(depth)[Node \(depth)]") }
        for _ in 0..<60 { lines.append("  end") }
        lines.append("  end")
        for depth in 0..<59 { lines.append("  n\(depth) --> n\(depth + 1)") }
        return lines.joined(separator: "\n")
    }

    static var manyGroups: String {
        var lines = ["swimlane-beta RL"]
        for lane in 0..<6 {
            lines.append("  subgraph lane\(lane)[Lane \(lane)]")
            for group in 0..<30 { lines.append("    subgraph g\(lane)_\(group)\n      m\(lane)_\(group)[Member]\n    end") }
            lines.append("  end")
        }
        for lane in 0..<5 { for group in 0..<30 { lines.append("  m\(lane)_\(group) --> m\(lane + 1)_\((group * 7) % 30)") } }
        return lines.joined(separator: "\n")
    }

    static var loopsAndRepeats: String {
        var lines = ["swimlane-beta BT", "  subgraph one[One]", "    a[A]", "    b[B]", "  end", "  subgraph two[Two]", "    c[C]", "  end", "  loose[Loose]"]
        for round in 0..<40 {
            lines.append(round.isMultiple(of: 3) ? "  a -->|again \(round)| a" : (round.isMultiple(of: 5) ? "  a ~~~ a\n  b ~~~ b" : "  a --> c\n  c -.-> b\n  b --> b"))
        }
        lines.append("  two --> two\n  one --> two")
        return lines.joined(separator: "\n")
    }
}
