/**
 * File: TreemapCorpus.swift
 * ----------------------
 * Layer: Benchmark
 * Description: The treemaps the benchmark times: Mermaid's documentation examples and generated trees.
 *
 * Authors: Bahey Shalash
 * Version: 0.2
 * Date: 23/11/2026
 */

import Foundation

/// The treemaps the benchmark times: Mermaid's eight documentation examples, as Pele's corpus collects them
/// (`tests/corpus/treemap-docs.json`), and trees of many leaves in sections nested three deep, with values from 1 to 1,000
/// from the seed of Pele's generated graphs.
enum TreemapCorpus {
    static func documentationExamples() throws -> [String] {
        guard let location = Bundle.module.url(forResource: "treemap-docs", withExtension: "json", subdirectory: "BenchmarkResources") else {
            throw FlowchartCorpus.MissingResource()
        }
        return try JSONDecoder().decode([String].self, from: Data(contentsOf: location))
    }

    /// A treemap of `leafCount` leaves: sections of eight leaves, grouped by eight into sections of sections, under a title.
    static func generated(leafCount: Int) -> String {
        var seed: UInt32 = 7
        var source = "treemap\ntitle Generated leaves\n"
        for leaf in 0..<leafCount {
            if leaf % 64 == 0 { source += "\"Group \(leaf / 64 + 1)\"\n" }
            if leaf % 8 == 0 { source += "  \"Section \(leaf / 8 + 1)\"\n" }
            seed = seed &* 1_664_525 &+ 1_013_904_223
            source += "    \"Leaf \(leaf + 1)\": \(1 + Int(Double(seed) / 4_294_967_296 * 1_000))\n"
        }
        return source
    }
}
