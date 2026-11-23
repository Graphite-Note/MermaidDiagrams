/**
 * File: CynefinCorpus.swift
 * -------------------------
 * Layer: Benchmark
 * Description: The Cynefin frameworks the benchmark and the tests run on: Mermaid's documentation examples as Pele's
 *              corpus collects them, and generated frameworks of many items and transitions.
 *
 * Authors: Bahey Shalash
 * Version: 0.2
 * Date: 23/11/2026
 */

import Foundation

/// The Cynefin frameworks the benchmark times: Mermaid's three documentation examples, as Pele's corpus collects them
/// (`tests/corpus/cynefin-docs.json`), and frameworks of many items with the seed of Pele's generated graphs.
enum CynefinCorpus {
    static func documentationExamples() throws -> [String] {
        guard let location = Bundle.module.url(forResource: "cynefin-docs", withExtension: "json", subdirectory: "BenchmarkResources") else {
            throw FlowchartCorpus.MissingResource()
        }
        return try JSONDecoder().decode([String].self, from: Data(contentsOf: location))
    }

    /// `itemCount` items spread over the five domains by the same linear congruential generator and seed as
    /// `FlowchartCorpus.mesh`, and a transition, labelled, between each two domains that follow one another.
    static func generated(itemCount: Int) -> String {
        var seed: UInt32 = 7
        func nextDomain() -> Int {
            seed = seed &* 1_664_525 &+ 1_013_904_223
            return Int(Double(seed) / 4_294_967_296 * 5)
        }
        let domains = ["complex", "complicated", "clear", "chaotic", "confusion"]
        var items = [[String]](repeating: [], count: domains.count)
        for item in 0..<itemCount { items[nextDomain()].append("Item \(item + 1)") }
        var source = "cynefin-beta\n  title Generated items\n"
        for (index, domain) in domains.enumerated() {
            source += "  \(domain)\n" + items[index].map { item in "    \"\(item)\"\n" }.joined()
        }
        for index in 0..<(domains.count - 1) { source += "  \(domains[index]) --> \(domains[index + 1]) : \"Step \(index + 1)\"\n" }
        return source
    }
}
