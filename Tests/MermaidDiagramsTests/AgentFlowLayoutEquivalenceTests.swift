/**
 * File: AgentFlowLayoutEquivalenceTests.swift
 * -------------------------------------------
 * Layer: Tests
 * Description: Every agent flow of the corpora laid out by the agent flow layout and by the 0.7.0 engine kept as the
 *              reference, as it runs and turned to run down, alike to the bit.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 24/11/2026
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

    /// Every number, text and choice of an agent flow's layout as bit patterns, or the error laying it out threw.
    private static func bits(_ laying: () throws -> AgentFlowLayout) -> FlowchartLayoutBits {
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
