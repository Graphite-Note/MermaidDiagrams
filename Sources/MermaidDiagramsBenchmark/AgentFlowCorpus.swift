/**
 * File: AgentFlowCorpus.swift
 * ---------------------------
 * Layer: Benchmark
 * Description: The agent flows the benchmark and the tests run on: Mermaid's documentation examples as Pele's corpus
 *              collects them, what Mermaid itself built for Pele's reference inputs, and generated flows.
 *
 * Authors: Bahey Shalash
 * Version: 0.2
 * Date: 23/11/2026
 */

import Foundation

/// The agent flows the benchmark times: Mermaid's twelve documentation examples, as Pele's corpus collects them
/// (`tests/corpus/agentflow-docs.json`), and generated flows of tasks, tools, decisions and inputs in nested flows.
enum AgentFlowCorpus {
    static func documentationExamples() throws -> [String] {
        try strings(named: "agentflow-docs")
    }

    /// Pele's reference inputs with what Mermaid 12.1.0's browser build made of each (`tests/corpus/agentflow-reference.json`),
    /// cut to the fields the tests compare: the JSON text of the whole list.
    static func referenceData() throws -> Data {
        guard let location = Bundle.module.url(forResource: "agentflow-reference", withExtension: "json", subdirectory: "BenchmarkResources") else {
            throw FlowchartCorpus.MissingResource()
        }
        return try Data(contentsOf: location)
    }

    private static func strings(named name: String) throws -> [String] {
        guard let location = Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "BenchmarkResources") else {
            throw FlowchartCorpus.MissingResource()
        }
        return try JSONDecoder().decode([String].self, from: Data(contentsOf: location))
    }

    /// `flowCount` flows of `nodesPerFlow` nodes each, every second flow inside the one before it and every third
    /// collapsed, each node a task, a tool, a decision or an input in turn, each node linked to the next and every fifth
    /// to a node of another flow picked by the same linear congruential generator and seed as `FlowchartCorpus.mesh`.
    static func generated(flowCount: Int, nodesPerFlow: Int) -> String {
        var seed: UInt32 = 7
        func next(below count: Int) -> Int {
            seed = seed &* 1_664_525 &+ 1_013_904_223
            return Int(Double(seed) / 4_294_967_296 * Double(count))
        }
        let shapes = ["task", "tool", "decision", "input"]
        var source = "agentflow-beta TB\n"
        var links = ""
        for flow in 0..<flowCount {
            let isNested = flow % 2 == 1
            let indent = isNested ? "    " : "  "
            source += indent + "flow f\(flow)[\"Flow \(flow)\"]\n"
            for node in 0..<nodesPerFlow {
                let identifier = "n\(flow)_\(node)"
                source += indent + "  \(identifier)[\"Step \(node) of flow \(flow)\"]@{ shape: \(shapes[node % shapes.count]) }\n"
                if node > 0 { source += indent + "  n\(flow)_\(node - 1) --> \(identifier)\n" }
                if node % 5 == 4 { links += "  \(identifier) -.- n\(next(below: flowCount))_0\n" }
            }
            if isNested { source += "    end\n  end\n" } else if flow == flowCount - 1 { source += "  end\n" }
            if flow % 3 == 2 { links += "  f\(flow)@{ view: collapsed }\n" }
        }
        return source + links
    }
}
