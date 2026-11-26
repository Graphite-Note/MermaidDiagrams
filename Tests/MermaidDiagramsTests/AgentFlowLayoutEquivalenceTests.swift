/**
 * File: AgentFlowLayoutEquivalenceTests.swift
 * -------------------------------------------
 * Layer: Tests
 * Description: Every agent flow of the corpora, Pele's reference inputs, changed and hostile ones, laid out by the agent
 *              flow layout and by the 0.7.0 engine kept as the reference, as it runs and turned to run down, on one
 *              thread and on twelve at once, alike to the bit.
 *
 * Authors: Bahey Shalash
 * Version: 0.2
 * Date: 26/11/2026
 */

import CoreGraphics
import XCTest
@testable import MermaidDiagrams
@testable import MermaidDiagramsBenchmark

final class AgentFlowLayoutEquivalenceTests: XCTestCase {
    func testEveryAgentFlowOfTheCorporaMatchesTheReferenceBitForBit() throws {
        let typography = DiagramSceneSamples.typography
        var agentFlowCount = 0
        var mismatches = 0
        for source in try OutputDigest.corpora().flatMap(\.sources) {
            guard case .agentFlow(let diagram)? = try? MermaidDiagramReader.read(source, limits: .standard) else { continue }
            agentFlowCount += 1
            for isTurnedToRunDown in [false, true] {
                let laidOut = Self.bits { try AgentFlowLayoutEngine.layout(diagram, typography: typography, isTurnedToRunDown: isTurnedToRunDown) }
                let reference = Self.bits { try ReferenceAgentFlowLayoutEngine.layout(diagram, typography: typography, isTurnedToRunDown: isTurnedToRunDown) }
                if laidOut != reference {
                    mismatches += 1
                    if mismatches <= 5 { XCTFail("the agent flow \(isTurnedToRunDown ? "turned to run down " : "")differs for:\n\(source.prefix(400))") }
                }
            }
        }
        XCTAssertGreaterThan(agentFlowCount, 20)
        XCTAssertEqual(mismatches, 0)
    }

    func testThePeleReferenceInputsAndChangedOnesAreLaidOutAsTheReferenceLaysThemOut() throws {
        let entries = try XCTUnwrap(JSONSerialization.jsonObject(with: AgentFlowCorpus.referenceData()) as? [[String: Any]])
        let references = entries.compactMap { entry in entry["src"] as? String }
        XCTAssertGreaterThan(references.count, 200)
        var mutations = C4RandomTexts(seed: 44)
        let originals = try PeleResults.sources(ofCorpus: "agentflow-docs") + references
        let sources = references + (0..<900).map { round in mutations.mutated(originals[round % originals.count]) }
        let diagrams = sources.compactMap(Self.agentFlow(of:))
        XCTAssertGreaterThan(diagrams.count, 300)
        XCTAssertEqual(Self.mismatches(among: diagrams), 0)
    }

    func testHostileAgentFlowsAreLaidOutAsTheReferenceLaysThemOut() {
        let diagrams = AgentFlowHostileTexts.all.compactMap(Self.agentFlow(of:))
        XCTAssertEqual(diagrams.count, AgentFlowHostileTexts.all.count)
        XCTAssertEqual(Self.mismatches(among: diagrams), 0)
    }

    func testTheLayoutIsTheReferencesOnTwelveThreadsAtOnce() throws {
        let diagrams = try OutputDigest.corpora().flatMap(\.sources).compactMap(Self.agentFlow(of:))
        let expected = diagrams.map { diagram in
            Self.bits { try ReferenceAgentFlowLayoutEngine.layout(diagram, typography: DiagramSceneSamples.typography) }
        }
        let mismatches = ThreadSafeCount()
        DispatchQueue.concurrentPerform(iterations: 12) { thread in
            for round in 0..<40 {
                let index = (thread * 13 + round) % diagrams.count
                if Self.bits({ try AgentFlowLayoutEngine.layout(diagrams[index], typography: DiagramSceneSamples.typography) }) != expected[index] {
                    mismatches.add()
                }
            }
        }
        XCTAssertEqual(mismatches.value, 0)
    }

    static func agentFlow(of source: String) -> AgentFlowDiagram? {
        guard case .agentFlow(let diagram)? = try? MermaidDiagramReader.read(source, limits: .standard) else { return nil }
        return diagram
    }

    /// How many of the diagrams' layouts, as they run and turned to run down, differ from the reference's.
    static func mismatches(among diagrams: [AgentFlowDiagram]) -> Int {
        let typography = DiagramSceneSamples.typography
        var mismatches = 0
        for diagram in diagrams {
            for isTurnedToRunDown in [false, true] {
                let laidOut = bits { try AgentFlowLayoutEngine.layout(diagram, typography: typography, isTurnedToRunDown: isTurnedToRunDown) }
                let reference = bits { try ReferenceAgentFlowLayoutEngine.layout(diagram, typography: typography, isTurnedToRunDown: isTurnedToRunDown) }
                if laidOut != reference {
                    mismatches += 1
                    if mismatches <= 5 { XCTFail("the agent flow differs: \(diagram.title ?? "") with \(diagram.graph.nodes.count) nodes") }
                }
            }
        }
        return mismatches
    }

    /// Every number, text and choice of an agent flow's layout as bit patterns, or the error laying it out threw.
    static func bits(_ laying: () throws -> AgentFlowLayout) -> FlowchartLayoutBits {
        var bits = FlowchartLayoutBits { throw CancellationError() }
        bits.error = nil
        let layout: AgentFlowLayout
        do {
            layout = try laying()
        } catch {
            bits.error = String(describing: error)
            return bits
        }
        bits.add(layout.size.width)
        bits.add(layout.size.height)
        bits.descriptions.append(String(describing: layout.font))
        bits.add(layout.title)
        for flow in layout.flows {
            bits.descriptions += [flow.identifier, String(describing: flow.style)]
            bits.add(flow.frame)
            bits.add(flow.title)
            bits.bits.append(UInt64(bitPattern: Int64(flow.paletteSlot)))
        }
        for node in layout.nodes {
            bits.descriptions += [node.identifier, String(describing: node.shape), String(describing: node.kind), String(describing: node.style)]
            bits.add(node.frame)
            bits.add(node.text)
            bits.bits += [UInt64(bitPattern: Int64(node.paletteSlot)), node.isCollapsedFlow ? 1 : 0, node.isBold ? 1 : 0, node.isItalic ? 1 : 0]
        }
        for edge in layout.edges {
            bits.descriptions += [edge.identifier, String(describing: edge.semantic), String(describing: edge.style)]
            bits.bits.append(edge.isDotted ? 1 : 0)
            bits.add(edge.path)
            bits.add(edge.targetMark)
            bits.add(edge.text)
        }
        return bits
    }
}

/// Agent flows made to be hard: long labels, many nodes and edges, flows nested deep, many flows, edges between nodes and
/// the flows around them (held back), collapsed flows, styles and metadata on every node.
enum AgentFlowHostileTexts {
    static let all: [String] = [longLabels, manyNodes, deepFlows, manyFlows, heldAndCollapsed]

    static var longLabels: String {
        "agentflow-beta LR\n  a[\"\(String(repeating: "word ", count: 2_000))\"] --> b[\(String(repeating: "x", count: 600))]\n  b -->|\(String(repeating: "label ", count: 500))| c"
    }

    static var manyNodes: String {
        var lines = ["agentflow-beta TB"]
        for node in 0..<300 { lines.append("  n\(node)[Step \(node)] --> n\((node * 7 + 3) % 300)") }
        return lines.joined(separator: "\n")
    }

    static var deepFlows: String {
        var lines = ["agentflow-beta RL"]
        for depth in 0..<40 { lines.append(String(repeating: " ", count: depth) + "  flow f\(depth)[Flow \(depth)]\n    m\(depth)[Member \(depth)]") }
        for _ in 0..<40 { lines.append("  end") }
        for depth in 0..<39 { lines.append("  m\(depth) --> m\(depth + 1)\n  m\(depth) --> f\(depth + 1)") }
        return lines.joined(separator: "\n")
    }

    static var manyFlows: String {
        var lines = ["agentflow-beta"]
        for flow in 0..<60 { lines.append("  flow g\(flow)[Group \(flow)]\n    k\(flow)[Task]@{ shape: \(flow.isMultiple(of: 2) ? "diamond" : "hexagon") }\n  end") }
        for flow in 0..<59 { lines.append("  k\(flow) -.- k\(flow + 1)\n  g\(flow) --x g\((flow * 5) % 60)") }
        return lines.joined(separator: "\n")
    }

    static var heldAndCollapsed: String {
        var lines = ["agentflow-beta LR", "  classDef hot fill:#f96,font-weight:bold,font-style:italic"]
        for flow in 0..<20 {
            lines.append("  flow c\(flow)[Collapsed \(flow)]@{ view: \(flow.isMultiple(of: 3) ? "collapsed" : "open") }")
            lines.append("    inner\(flow)[Inner]:::hot --> c\(flow)\n    c\(flow) --> other\(flow)[Other]\n  end")
            lines.append("  style inner\(flow) font-size:\(10 + flow)px")
        }
        for flow in 0..<19 { lines.append("  other\(flow) --> inner\(flow + 1)") }
        return lines.joined(separator: "\n")
    }
}
