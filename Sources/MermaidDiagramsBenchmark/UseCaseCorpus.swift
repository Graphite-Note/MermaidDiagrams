/**
 * File: UseCaseCorpus.swift
 * -------------------------
 * Layer: Benchmark
 * Description: The use case diagrams the benchmark and the tests read: Mermaid's documentation examples, and
 *              generated diagrams of many actors and use cases in boundaries with relationships between them.
 *
 * Authors: Bahey Shalash
 * Version: 0.2
 * Date: 23/11/2026
 */

import Foundation

/// The use case diagrams the benchmark times: Mermaid's 24 documentation examples, as Pele's corpus collects them
/// (`tests/corpus/usecase-docs.json`), and diagrams of many elements made with the seed of Pele's generated graphs.
enum UseCaseCorpus {
    static func documentationExamples() throws -> [String] {
        guard let location = Bundle.module.url(forResource: "usecase-docs", withExtension: "json", subdirectory: "BenchmarkResources") else {
            throw FlowchartCorpus.MissingResource()
        }
        return try JSONDecoder().decode([String].self, from: Data(contentsOf: location))
    }

    /// `actorCount` actors, `useCaseCount` use cases spread over `boundaryCount` boundaries in turn (none for zero), and
    /// `relationshipCount` relationships, each from an actor or a use case to a use case picked by the same linear
    /// congruential generator and seed as `FlowchartCorpus.mesh`; every fifth an include, every seventh labelled.
    static func generated(actorCount: Int, useCaseCount: Int, boundaryCount: Int, relationshipCount: Int) -> String {
        var seed: UInt32 = 7
        func next(below count: Int) -> Int {
            seed = seed &* 1_664_525 &+ 1_013_904_223
            return Int(Double(seed) / 4_294_967_296 * Double(count))
        }
        var source = "usecase-beta\n" + (0..<actorCount).map { index in "actor a\(index)(\"Actor \(index)\")\n" }.joined()
        let looseCount = boundaryCount == 0 ? useCaseCount : min(useCaseCount, 2)
        for index in 0..<looseCount { source += "u\(index)(\"Use case \(index)\")\n" }
        for boundary in 0..<boundaryCount {
            source += "systemBoundary b\(boundary)[\"Boundary \(boundary)\"]\n"
            for index in stride(from: looseCount + boundary, to: useCaseCount, by: boundaryCount) { source += "  u\(index)(\"Use case \(index)\")\n" }
            source += "end\n"
        }
        guard useCaseCount > 0 else { return source }
        for relationship in 0..<relationshipCount {
            let target = "u\(next(below: useCaseCount))"
            if relationship % 5 == 4 {
                source += "u\(relationship % useCaseCount) ..> : include \(target)\n"
            } else {
                let from = actorCount > 0 && relationship % 2 == 0 ? "a\(relationship % actorCount)" : "u\(relationship % useCaseCount)"
                source += relationship % 7 == 6 ? "\(from) -- \"uses \(relationship)\" --> \(target)\n" : "\(from) --> \(target)\n"
            }
        }
        return source
    }
}
