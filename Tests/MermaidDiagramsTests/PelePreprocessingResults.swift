/**
 * File: PelePreprocessingResults.swift
 * ------------------------------------
 * Layer: Tests
 * Description: What Pele's own YAML reader and preprocessing made of the texts scripts/pele/preprocessing-recorder.ts
 *              gave them, for the package's ports to be compared with.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 23/11/2026
 */

import Foundation
@testable import MermaidDiagrams
@testable import MermaidDiagramsBenchmark

/// `pele-preprocessing.json`: YAML texts as Pele's util/yaml.ts read them, and diagram texts as its preprocess.ts and
/// encodeEntities left them, each with the error when Pele refused it.
struct PelePreprocessingResults: Decodable {
    struct YAMLText: Decodable {
        let source: String
        /// What the text holds; JSON's null for a YAML null, and also when Pele refused it (then `error` is set).
        let value: DirectiveValue?
        let error: String?
    }

    struct DiagramText: Decodable {
        let source: String
        /// The text a diagram's parser is given: without front matter, directives and comment lines, trimmed at its
        /// start, a colour's last semicolon dropped and entity codes hidden.
        let text: String?
        let title: String?
        let config: DirectiveValue?
        let error: String?
    }

    let yaml: [YAMLText]
    let preprocessing: [DiagramText]
}

extension PeleResults {
    static func preprocessing() throws -> PelePreprocessingResults {
        try JSONDecoder().decode(PelePreprocessingResults.self, from: resource(named: "pele-preprocessing", extension: "json"))
    }
}
