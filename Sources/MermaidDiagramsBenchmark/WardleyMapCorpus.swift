/**
 * File: WardleyMapCorpus.swift
 * ----------------------------
 * Layer: Benchmark
 * Description: The Wardley maps the benchmark and the tests run on: Mermaid's documentation examples as Pele's corpus
 *              collects them, and generated maps of many components.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 19/11/2026
 */

import Foundation

/// The Wardley maps the benchmark times: Mermaid's nineteen documentation examples, as Pele's corpus collects them
/// (`tests/corpus/wardley-docs.json`), and maps of many components with the seed of Pele's generated graphs.
enum WardleyMapCorpus {
    static func documentationExamples() throws -> [String] {
        guard let location = Bundle.module.url(forResource: "wardley-docs", withExtension: "json", subdirectory: "Resources") else {
            throw FlowchartCorpus.MissingResource()
        }
        return try JSONDecoder().decode([String].self, from: Data(contentsOf: location))
    }

    /// An anchor and `componentCount` components at coordinates from 0.05 to 0.94 from the same linear congruential
    /// generator and seed as `FlowchartCorpus.mesh`, each linked from the one before, every fifth evolving and every
    /// seventh with inertia, a note and an annotation.
    static func generated(componentCount: Int) -> String {
        var seed: UInt32 = 7
        func nextCoordinate() -> String {
            seed = seed &* 1_664_525 &+ 1_013_904_223
            return "0." + String(format: "%02d", 5 + Int(Double(seed) / 4_294_967_296 * 90))
        }
        var source = "wardley-beta\ntitle Generated map\nanchor User [0.97, 0.80]\n"
        for component in 0..<componentCount {
            source += "component C\(component) [\(nextCoordinate()), \(nextCoordinate())]" + (component % 7 == 3 ? " (inertia)" : "") + "\n"
        }
        if componentCount > 0 { source += "User -> C0\n" }
        for component in 0..<max(0, componentCount - 1) { source += "C\(component) -> C\(component + 1)\n" }
        for component in stride(from: 0, to: componentCount, by: 5) { source += "evolve C\(component) 0.95\n" }
        source += "note \"Generated\" [0.10, 0.10]\nannotation 1,[0.50, 0.50] \"Middle\"\n"
        return source
    }
}
