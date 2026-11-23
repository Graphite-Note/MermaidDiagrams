/**
 * File: PeleResults.swift
 * -----------------------
 * Layer: Benchmark
 * Description: What Pele itself drew for every input of the corpora and how long it took, as scripts/pele/run.sh
 *              recorded it on this Mac, and the inputs it was given, for the differential tests and the benchmark.
 *
 * Authors: Bahey Shalash
 * Version: 0.2
 * Date: 23/11/2026
 */

import Foundation

/// How Pele was run: its version, the text measurer it fell back to outside a browser, and the machine.
struct PeleRun: Decodable {
    let pele: String
    let measurer: String
    let deno: String
    let os: String
    let arch: String
    /// The date of a benchmark run; a corpus run has none.
    let date: String?
}

/// One input as Pele drew it (`pele-corpus.json`): its page, its `<text>` elements and `<g>` groups counted by Pele's
/// classes (`pele-label` as `label`), and the subpaths of its shapes by class; or the error it threw.
struct PeleRenderedInput: Decodable {
    let corpus: String
    let index: Int
    /// FNV-1a of the source's UTF-8 bytes, 32 bits in hexadecimal (`PeleResults.sourceHash(of:)`).
    let sourceHash: String
    let type: String?
    let error: String?
    let width: Double?
    let height: Double?
    let texts: [String: Int]?
    let groups: [String: Int]?
    let subpaths: [String: Int]?
    let medianMicroseconds: Double?
    let percentile99Microseconds: Double?
}

struct PeleCorpusResults: Decodable {
    let run: PeleRun
    let inputs: [PeleRenderedInput]
}

/// What Pele drew for the random flat flowcharts its runner generates (`--random-flat`, `pele-random-flat.json`), whose
/// sources it writes beside them (`random-flat.json`).
struct PeleGeneratedResults: Decodable {
    let inputs: [PeleRenderedInput]
}

/// One case of Pele's benchmark (`scripts/bench.mjs`'s cases, then each type's documentation examples), timed as it
/// times them: the whole case per run, the median and the 99th percentile divided by its diagrams.
struct PeleTimedCase: Decodable {
    let name: String
    let diagramCount: Int
    let renderedCount: Int
    let medianMillisecondsPerCase: Double
    let medianMicrosecondsPerDiagram: Double
    let percentile99MicrosecondsPerDiagram: Double
    let runs: Int
}

struct PeleBenchResults: Decodable {
    let run: PeleRun
    let cases: [PeleTimedCase]
    let perType: [PeleTimedCase]
}

/// Pele's own results, checked in as resources (`pele-corpus.json`, `pele-bench.json`), and the inputs they are of.
enum PeleResults {
    /// The generated graphs of Pele's benchmark, in the order its runner records them (`bench-generated`).
    static let generatedBenchmarkInputs: [(name: String, source: String)] = [
        ("tree: 50 nodes", FlowchartCorpus.tree(nodeCount: 50)),
        ("mesh: 50 nodes, 20 extra labelled edges", FlowchartCorpus.mesh(nodeCount: 50, extraEdgeCount: 20)),
        ("tree: 500 nodes", FlowchartCorpus.tree(nodeCount: 500)),
        ("mesh: 500 nodes, 200 extra labelled edges", FlowchartCorpus.mesh(nodeCount: 500, extraEdgeCount: 200)),
    ]

    static func corpus() throws -> PeleCorpusResults {
        try JSONDecoder().decode(PeleCorpusResults.self, from: resource(named: "pele-corpus", extension: "json"))
    }

    /// Pele's drawings of the random flat flowcharts (`random-flat`), for the layered layout.
    static func randomFlat() throws -> PeleGeneratedResults {
        try JSONDecoder().decode(PeleGeneratedResults.self, from: resource(named: "pele-random-flat", extension: "json"))
    }

    /// Every input Pele's runner drew: its corpora and the random flat flowcharts.
    static func everyInput() throws -> [PeleRenderedInput] {
        try corpus().inputs + randomFlat().inputs
    }

    static func bench() throws -> PeleBenchResults {
        try JSONDecoder().decode(PeleBenchResults.self, from: resource(named: "pele-bench", extension: "json"))
    }

    /// The inputs differing from Pele beyond the tests' tolerance, with why (`PeleKnownDifferences.md`).
    static func knownDifferences() throws -> String {
        String(decoding: try resource(named: "PeleKnownDifferences", extension: "md"), as: UTF8.self)
    }

    /// The sources of a corpus Pele's runner read: a documentation corpus, the agent flow reference's inputs, the
    /// generated graphs of Pele's benchmark, or the random flat flowcharts.
    static func sources(ofCorpus name: String) throws -> [String] {
        if name == "bench-generated" { return generatedBenchmarkInputs.map(\.source) }
        let data = try resource(named: name, extension: "json")
        if let strings = try? JSONDecoder().decode([String].self, from: data) { return strings }
        return try JSONDecoder().decode([ReferenceInput].self, from: data).map(\.src)
    }

    /// FNV-1a over the UTF-8 bytes, 32 bits, as Pele's runner writes it.
    static func sourceHash(of source: String) -> String {
        var hash: UInt32 = 0x811c_9dc5
        for byte in source.utf8 { hash = (hash ^ UInt32(byte)) &* 0x0100_0193 }
        let digits = String(hash, radix: 16)
        return String(repeating: "0", count: 8 - digits.count) + digits
    }

    private struct ReferenceInput: Decodable {
        let src: String
    }

    static func resource(named name: String, extension fileExtension: String) throws -> Data {
        guard let location = Bundle.module.url(forResource: name, withExtension: fileExtension, subdirectory: "Resources") else {
            throw FlowchartCorpus.MissingResource()
        }
        return try Data(contentsOf: location)
    }
}

/// A text one of Mermaid's flowchart specs parses (`tests/compat/flowchart`), with what Pele's flowchart database made of
/// it, as scripts/pele/compat-recorder.ts records it (`pele-flowchart-compat.json`): the error it threw, or the
/// direction, the nodes in the order first named, the edges and the groups.
struct PeleParsedFlowchart: Decodable {
    struct Node: Decodable {
        let id: String
        let text: String
        let type: String
    }

    struct Edge: Decodable {
        let start: String
        let end: String
        /// `arrow_point`, `arrow_open`, `arrow_circle`, `arrow_cross`, or `double_` and one of those three marks.
        let type: String
        /// `normal`, `thick`, `dotted` or `invisible`.
        let stroke: String
        let length: Int
        let text: String
    }

    struct Group: Decodable {
        let id: String
        let title: String
        /// The nodes and groups directly inside it.
        let nodes: [String]
    }

    let spec: String
    let test: String
    let source: String
    let error: String?
    let direction: String?
    let nodes: [Node]?
    let edges: [Edge]?
    let subgraphs: [Group]?
}

extension PeleResults {
    static func flowchartSpecTexts() throws -> [PeleParsedFlowchart] {
        try JSONDecoder().decode([PeleParsedFlowchart].self, from: resource(named: "pele-flowchart-compat", extension: "json"))
    }
}

extension PeleResults {
    /// The copy of tests/compat's inputs: each spec or test file (`type/file`) with the strings it writes that are diagram
    /// texts (`pele-compat-inputs.json`, written by `scripts/pele/compat-recorder.ts`).
    static func compatInputs() throws -> [String: [String]] {
        try JSONDecoder().decode([String: [String]].self, from: resource(named: "pele-compat-inputs", extension: "json"))
    }
}
