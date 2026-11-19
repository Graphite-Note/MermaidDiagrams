/**
 * File: PacketDiagramCorpus.swift
 * ----------------------------
 * Layer: Benchmark
 * Description: The packet diagrams the benchmark times: Mermaid's documentation examples and generated packets.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 19/11/2026
 */

import Foundation

/// The packet diagrams the benchmark times: Mermaid's four documentation examples, as Pele's corpus collects them
/// (`tests/corpus/packet-docs.json`), and packets of many fields of 1 to 40 bits, with the seed of Pele's generated graphs.
enum PacketDiagramCorpus {
    static func documentationExamples() throws -> [String] {
        guard let location = Bundle.module.url(forResource: "packet-docs", withExtension: "json", subdirectory: "Resources") else {
            throw FlowchartCorpus.MissingResource()
        }
        return try JSONDecoder().decode([String].self, from: Data(contentsOf: location))
    }

    /// A packet of `fieldCount` fields of 1 to 40 bits each, from the same linear congruential generator and seed as
    /// `FlowchartCorpus.mesh`, so that some cross the end of a row.
    static func generated(fieldCount: Int) -> String {
        var seed: UInt32 = 7
        var source = "packet\ntitle Generated fields\n"
        for field in 0..<fieldCount {
            seed = seed &* 1_664_525 &+ 1_013_904_223
            source += "+\(1 + Int(Double(seed) / 4_294_967_296 * 40)): \"Field \(field + 1)\"\n"
        }
        return source
    }
}
