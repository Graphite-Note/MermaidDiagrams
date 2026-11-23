/**
 * File: VennCorpus.swift
 * ----------------------
 * Layer: Benchmark
 * Description: The Venn diagrams the benchmark and the tests run on: Mermaid's documentation examples as Pele's corpus
 *              collects them, and generated diagrams of many sets.
 *
 * Authors: Bahey Shalash
 * Version: 0.2
 * Date: 23/11/2026
 */

import Foundation

/// The Venn diagrams the benchmark times: Mermaid's eight documentation examples, as Pele's corpus collects them
/// (`tests/corpus/venn-docs.json`), and diagrams of many sets with the seed of Pele's generated graphs.
enum VennCorpus {
    static func documentationExamples() throws -> [String] {
        guard let location = Bundle.module.url(forResource: "venn-docs", withExtension: "json", subdirectory: "BenchmarkResources") else {
            throw FlowchartCorpus.MissingResource()
        }
        return try JSONDecoder().decode([String].self, from: Data(contentsOf: location))
    }

    /// `setCount` sets of sizes from 5 to 24 from the same linear congruential generator and seed as
    /// `FlowchartCorpus.mesh`, each overlapping the next, the first three overlapping all together, and a text in every
    /// other set.
    static func generated(setCount: Int) -> String {
        var seed: UInt32 = 7
        func nextSize() -> Int {
            seed = seed &* 1_664_525 &+ 1_013_904_223
            return 5 + Int(Double(seed) / 4_294_967_296 * 20)
        }
        var source = "venn-beta\n  title Generated sets\n"
        for set in 0..<setCount {
            source += "  set S\(set)[\"Set \(set)\"]:\(nextSize())\n"
            if set.isMultiple(of: 2) { source += "    text T\(set)[\"Item \(set)\"]\n" }
        }
        for set in 0..<max(0, setCount - 1) { source += "  union S\(set),S\(set + 1):2\n" }
        if setCount >= 3 { source += "  union S0,S1,S2[\"All three\"]:1\n" }
        return source
    }
}
