/**
 * File: RailroadCorpus.swift
 * --------------------------
 * Layer: Benchmark
 * Description: The railroad diagrams the benchmark and the tests run on: Mermaid's documentation examples in the four
 *              notations, as Pele collects them, and generated grammars.
 *
 * Authors: Bahey Shalash
 * Version: 0.2
 * Date: 23/11/2026
 */

import Foundation

/// The railroad diagrams the benchmark times: Mermaid's fourteen documentation examples, as Pele's corpus collects them
/// (`tests/corpus/railroad-docs.json`), and EBNF grammars of many rules generated to use every kind of part.
enum RailroadCorpus {
    static func documentationExamples() throws -> [String] {
        guard let location = Bundle.module.url(forResource: "railroad-docs", withExtension: "json", subdirectory: "BenchmarkResources") else {
            throw FlowchartCorpus.MissingResource()
        }
        return try JSONDecoder().decode([String].self, from: Data(contentsOf: location))
    }

    /// `ruleCount` EBNF rules, each a sequence of a terminal, a choice of the next two rules, an option, a repetition
    /// and a special sequence; the last rules refer to names no rule defines.
    static func generated(ruleCount: Int) -> String {
        var source = "railroad-ebnf-beta\ntitle \"Generated grammar\"\n"
        for rule in 0..<ruleCount {
            source += "rule\(rule) = \"t\(rule)\" , ( rule\(rule + 1) | rule\(rule + 2) | \"alternative\" ) , [ \"opt\" ] , { \"more\" , rule\(rule + 3) } , ? anything ? ;\n"
        }
        return source
    }
}
