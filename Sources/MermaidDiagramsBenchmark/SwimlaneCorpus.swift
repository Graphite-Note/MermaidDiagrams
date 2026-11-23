/**
 * File: SwimlaneCorpus.swift
 * --------------------------
 * Layer: Benchmark
 * Description: The swimlane diagrams the benchmark and the tests run on: Mermaid's documentation examples, as Pele
 *              collects them, and generated processes of many steps handed from lane to lane.
 *
 * Authors: Bahey Shalash
 * Version: 0.2
 * Date: 23/11/2026
 */

import Foundation

/// The swimlane diagrams the benchmark times: Mermaid's thirteen documentation examples, as Pele's corpus collects them
/// (`tests/corpus/swimlane-docs.json`), and processes generated over a number of lanes.
enum SwimlaneCorpus {
    static func documentationExamples() throws -> [String] {
        guard let location = Bundle.module.url(forResource: "swimlane-docs", withExtension: "json", subdirectory: "BenchmarkResources") else {
            throw FlowchartCorpus.MissingResource()
        }
        return try JSONDecoder().decode([String].self, from: Data(contentsOf: location))
    }

    /// `stepCount` steps dealt round `laneCount` lanes (every fourth step a decision), each step handed to the next, every
    /// fourth handoff with text, every decision sending a step back two steps with text, and a loose start before them.
    static func process(laneCount: Int, stepCount: Int, direction: String = "LR") -> String {
        var source = "swimlane-beta \(direction)\n  start([Start]) --> s0\n"
        for lane in 0..<laneCount {
            source += "  subgraph lane\(lane) [Team \(lane + 1)]\n"
            for step in stride(from: lane, to: stepCount, by: laneCount) {
                source += step % 4 == 3 ? "    s\(step){Check \(step)?}\n" : "    s\(step)[Step \(step)]\n"
            }
            source += "  end\n"
        }
        for step in 1..<max(1, stepCount) {
            source += step % 4 == 0 ? "  s\(step - 1) -->|hand over| s\(step)\n" : "  s\(step - 1) --> s\(step)\n"
        }
        for step in stride(from: 3, to: stepCount, by: 4) { source += "  s\(step) -->|No| s\(step - 2)\n" }
        return source
    }
}
