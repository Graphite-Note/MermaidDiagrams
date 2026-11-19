/**
 * File: RequirementCorpus.swift
 * -----------------------------
 * Layer: Benchmark
 * Description: The requirement diagrams the benchmark and the tests run on: Mermaid's documentation examples, as Pele
 *              collects them, and generated diagrams of many requirements and elements.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 19/11/2026
 */

import Foundation

/// The requirement diagrams the benchmark times: Mermaid's nine documentation examples, as Pele's corpus collects them
/// (`tests/corpus/requirement-docs.json`), and diagrams of many requirements generated in turn through the six kinds.
enum RequirementCorpus {
    static func documentationExamples() throws -> [String] {
        guard let location = Bundle.module.url(forResource: "requirement-docs", withExtension: "json", subdirectory: "Resources") else {
            throw FlowchartCorpus.MissingResource()
        }
        return try JSONDecoder().decode([String].self, from: Data(contentsOf: location))
    }

    /// `requirementCount` requirements whose kinds, risks and verification methods go round theirs, an element per three
    /// requirements, each requirement contained in the one before it in threes and derived from the third before it, each
    /// element satisfying a requirement, and every seventh requirement tracing itself.
    static func generated(requirementCount: Int, direction: String = "TB") -> String {
        let kinds = ["requirement", "functionalRequirement", "interfaceRequirement", "performanceRequirement", "physicalRequirement", "designConstraint"]
        let risks = ["low", "medium", "high"]
        let methods = ["analysis", "inspection", "test", "demonstration"]
        var source = "requirementDiagram\ndirection \(direction)\n"
        for index in 0..<requirementCount {
            source += "\(kinds[index % kinds.count]) req_\(index) {\nid: \(index / 10).\(index % 10)\ntext: The part numbered \(index) holds.\n"
                + "risk: \(risks[index % risks.count])\nverifymethod: \(methods[index % methods.count])\n}\n"
        }
        for index in stride(from: 0, to: requirementCount, by: 3) { source += "element part_\(index) {\ntype: module\ndocref: docs/part_\(index).md\n}\n" }
        for index in 1..<max(1, requirementCount) {
            source += index % 3 == 0 ? "req_\(index - 3) - derives -> req_\(index)\n" : "req_\(index - 1) - contains -> req_\(index)\n"
        }
        for index in stride(from: 0, to: requirementCount, by: 3) { source += "part_\(index) - satisfies -> req_\(index)\n" }
        for index in stride(from: 0, to: requirementCount, by: 7) { source += "req_\(index) - traces -> req_\(index)\n" }
        return source
    }
}
