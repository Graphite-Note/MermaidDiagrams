/**
 * File: AgentFlowReferenceTests.swift
 * -----------------------------------
 * Layer: Tests
 * Description: Compares the agent flow model with what Mermaid 12.1.0 itself built for Pele's 239 reference inputs:
 *              which texts are refused, and the nodes, edges, flows, graph, palette slots, positions and diagnostics.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 19/11/2026
 */

import Foundation
@testable import MermaidDiagramsBenchmark
import XCTest
@testable import MermaidDiagrams

/// Pele's `tests/agentflow/reference.test.ts`: the reference holds Mermaid's own model of each input, taken from its
/// browser build with a palette of twelve colors and `basis` as the configured curve.
final class AgentFlowReferenceTests: XCTestCase {
    /// js-yaml's errors for an alias and for a lone colon in metadata: Pele's YAML reader has neither and takes both as
    /// text, so it accepts these diagrams where Mermaid does not.
    private static let lenientYAML = try? NSRegularExpression(pattern: "alias|explicit mapping pair")

    private static func reference() throws -> [[String: Any]] {
        try XCTUnwrap(JSONSerialization.jsonObject(with: AgentFlowCorpus.referenceData()) as? [[String: Any]])
    }

    func testTheReferenceHasInputsToCompare() throws {
        let reference = try Self.reference()
        XCTAssertGreaterThan(reference.count, 200)
        XCTAssertGreaterThan(reference.filter { entry in entry["model"] != nil }.count, 150)
    }

    func testAcceptsAndRefusesTheSameInputsAsMermaid() throws {
        var disagreements: [String] = []
        for entry in try Self.reference() {
            let source = try XCTUnwrap(entry["src"] as? String)
            let mine = AgentFlowReading.readError(source)
            if let error = entry["error"] as? String {
                let isLenient = Self.lenientYAML?.firstMatch(in: error, range: NSRange(error.startIndex..., in: error)) != nil
                if isLenient ? mine != nil : mine == nil { disagreements.append("Mermaid: \(error); \(String(reflecting: source))") }
            } else if let mine {
                disagreements.append("refused \(mine); \(String(reflecting: source))")
            }
        }
        XCTAssertEqual(disagreements, [])
    }

    func testBuildsTheSameModelAsMermaid() throws {
        var differences: [String] = []
        var comparedCount = 0
        for entry in try Self.reference() {
            guard let model = entry["model"] as? [String: Any], let source = entry["src"] as? String,
                  let diagram = try? AgentFlowReading.diagram(source) else { continue }
            comparedCount += 1
            let mine = AgentFlowReferenceProjection.model(of: diagram)
            for (key, expected) in model {
                let ours = mine[key] ?? NSNull()
                if !AgentFlowReferenceProjection.same(AgentFlowReferenceProjection.comparable(expected), AgentFlowReferenceProjection.comparable(ours)) {
                    differences.append("\(key) of \(String(reflecting: source)):\n  Mermaid \(expected)\n  ours    \(ours)")
                }
            }
        }
        XCTAssertGreaterThan(comparedCount, 150)
        XCTAssertEqual(differences.count, 0, differences.prefix(12).joined(separator: "\n"))
    }
}
