/**
 * File: C4Corpus.swift
 * --------------------
 * Layer: Benchmark
 * Description: The C4 diagrams the benchmark and the tests run on: Mermaid's documentation examples as Pele's corpus
 *              collects them, and generated diagrams of many shapes, boundaries and relations.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 19/11/2026
 */

import Foundation

/// The C4 diagrams the benchmark times: Mermaid's six documentation examples, as Pele's corpus collects them
/// (`tests/corpus/c4-docs.json`), and diagrams of many systems in boundaries with relations between them, made with the
/// seed of Pele's generated graphs.
enum C4Corpus {
    static func documentationExamples() throws -> [String] {
        guard let location = Bundle.module.url(forResource: "c4-docs", withExtension: "json", subdirectory: "Resources") else {
            throw FlowchartCorpus.MissingResource()
        }
        return try JSONDecoder().decode([String].self, from: Data(contentsOf: location))
    }

    /// `shapeCount` systems, a person first, spread over `boundaryCount` boundaries in turn (none for zero), and a
    /// relation from each to one picked by the same linear congruential generator and seed as `FlowchartCorpus.mesh`, every
    /// third a database and every fifth a queue.
    static func generated(shapeCount: Int, boundaryCount: Int, relationCount: Int) -> String {
        var seed: UInt32 = 7
        func next(below count: Int) -> Int {
            seed = seed &* 1_664_525 &+ 1_013_904_223
            return Int(Double(seed) / 4_294_967_296 * Double(count))
        }
        func shape(_ index: Int) -> String {
            let macro = index == 0 ? "Person" : index % 5 == 0 ? "SystemQueue" : index % 3 == 0 ? "SystemDb" : "System"
            return "  \(macro)(s\(index), \"System \(index)\", \"Generated system number \(index)\")\n"
        }
        var source = "C4Context\n  title Generated systems\n"
        let looseCount = boundaryCount == 0 ? shapeCount : min(shapeCount, 2)
        for index in 0..<looseCount { source += shape(index) }
        for boundary in 0..<boundaryCount {
            source += "  Enterprise_Boundary(b\(boundary), \"Boundary \(boundary)\") {\n"
            for index in stride(from: looseCount + boundary, to: shapeCount, by: boundaryCount) { source += "  " + shape(index) }
            source += "  }\n"
        }
        for relation in 0..<relationCount {
            let from = relation % shapeCount
            let to = next(below: shapeCount)
            source += "  Rel(s\(from), s\(to), \"Uses \(relation)\", \"HTTPS\")\n"
        }
        return source
    }
}
