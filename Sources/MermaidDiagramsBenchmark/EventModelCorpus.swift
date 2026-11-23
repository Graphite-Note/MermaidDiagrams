/**
 * File: EventModelCorpus.swift
 * ----------------------------
 * Layer: Benchmark
 * Description: The event models the benchmark and the tests run on: Mermaid's documentation examples, as Pele
 *              collects them, and generated models of many frames.
 *
 * Authors: Bahey Shalash
 * Version: 0.2
 * Date: 23/11/2026
 */

import Foundation

/// The event models the benchmark times: Mermaid's twelve documentation examples, as Pele's corpus collects them
/// (`tests/corpus/eventmodeling-docs.json`), and models of many frames generated in turn through the five kinds.
enum EventModelCorpus {
    static func documentationExamples() throws -> [String] {
        guard let location = Bundle.module.url(forResource: "eventmodeling-docs", withExtension: "json", subdirectory: "BenchmarkResources") else {
            throw FlowchartCorpus.MissingResource()
        }
        return try JSONDecoder().decode([String].self, from: Data(contentsOf: location))
    }

    /// `frameCount` frames whose kinds go round the user interface, the command, the event, the read model and the
    /// processor, every fifth one in a namespace of its own, every seventh with data, and a note and a specification
    /// per ten frames.
    static func generated(frameCount: Int) -> String {
        let kinds = ["ui", "cmd", "evt", "rmo", "pcr"]
        var source = "eventmodeling\n"
        for frame in 0..<frameCount {
            let namespace = frame % 5 == 4 ? "Area\(frame % 3)." : ""
            let data = frame % 7 == 0 ? " { id: \(frame), name: \"item \(frame)\" }" : ""
            source += "tf \(frame % 1_000) \(kinds[frame % kinds.count]) \(namespace)Step\(frame)\(data)\n"
        }
        for frame in stride(from: 0, to: frameCount, by: 10) {
            source += "note \(frame) {\n  Frame \(frame) starts a stretch of ten.\n}\n"
            source += "gwt \(frame) given evt Step\(frame) when cmd Step\(frame + 1) then evt Step\(frame + 2)\n"
        }
        return source
    }
}
