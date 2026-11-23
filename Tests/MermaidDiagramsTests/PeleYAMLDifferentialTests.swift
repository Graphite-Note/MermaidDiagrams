/**
 * File: PeleYAMLDifferentialTests.swift
 * -------------------------------------
 * Layer: Tests
 * Description: The package's port of Pele's YAML reader compared with Pele's own reader on the texts of its YAML tests
 *              and on front matter and node data written in the ways those leave out.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 23/11/2026
 */

import XCTest
@testable import MermaidDiagrams
@testable import MermaidDiagramsBenchmark

/// `pele-preprocessing.json`'s `yaml` (scripts/pele/preprocessing-recorder.ts): each text as Pele's util/yaml.ts read
/// it, or refused it.
final class PeleYAMLDifferentialTests: XCTestCase {
    func testEveryTextIsReadAsPelesReaderReadsItOrRefusedAsItRefusesIt() throws {
        let texts = try PeleResults.preprocessing().yaml
        XCTAssertGreaterThan(texts.count, 40)
        for text in texts {
            let mine = MermaidYAMLDocument.value(of: text.source)
            if text.error != nil {
                XCTAssertNil(mine, "Pele refuses \(text.source.debugDescription): \(text.error ?? "")")
            } else {
                XCTAssertEqual(mine, text.value ?? .null, text.source.debugDescription)
            }
        }
    }
}
