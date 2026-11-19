/**
 * File: InfoDiagramCorpus.swift
 * --------------------------
 * Layer: Benchmark
 * Description: The info diagrams the benchmark times: Mermaid's two documentation examples, and one with titles.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 19/11/2026
 */

import Foundation

/// The info diagrams the benchmark times: Mermaid's two documentation examples, as Pele's corpus collects them
/// (`tests/corpus/info-docs.json`), and one with a title and the accessibility statements.
enum InfoDiagramCorpus {
    static func documentationExamples() throws -> [String] {
        guard let location = Bundle.module.url(forResource: "info-docs", withExtension: "json", subdirectory: "Resources") else {
            throw FlowchartCorpus.MissingResource()
        }
        return try JSONDecoder().decode([String].self, from: Data(contentsOf: location))
    }

    /// An info diagram with a title, `accTitle` and `accDescr`.
    static let titled = "info showInfo\ntitle Mermaid Diagrams\naccTitle: About this package\naccDescr: The version of the package that drew this page.\n"
}
