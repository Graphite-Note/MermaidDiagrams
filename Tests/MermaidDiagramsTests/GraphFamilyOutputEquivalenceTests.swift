/**
 * File: GraphFamilyOutputEquivalenceTests.swift
 * ---------------------------------------------
 * Layer: Tests
 * Description: What preparing random and changed state, class, entity relationship and requirement texts gives (the
 *              SVG, the narrow scenes' SVGs, what a screen reader says, or why a text is refused), digested as the
 *              output digest digests the corpora, against the digest main dad6fb8 gives for the same texts: the byte
 *              readers, the class member bytes and the Markdown decoder's shortcut on texts no corpus holds.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 25/11/2026
 */

import XCTest
@testable import MermaidDiagrams
@testable import MermaidDiagramsBenchmark

final class GraphFamilyOutputEquivalenceTests: XCTestCase {
    /// The digest of every text's line, made by main dad6fb8, whose state, class, entity relationship and requirement
    /// code is 0.7.0's readers.
    static let expectedDigest = "496efff0c4d49a88"

    func testRandomAndChangedTextsArePreparedAsBefore() throws {
        let sources = try Self.sources()
        var everyLine = FowlerNollVoDigest()
        var drawnCountByKind: [String: Int] = [:]
        for (index, source) in sources.enumerated() {
            let outcome = OutputDigest.Outcome(source: source, typography: DiagramSceneSamples.typography,
                                               narrowColumnWidths: OutputDigest.narrowColumnWidths)
            everyLine.add("\(index) \(outcome.summaryLine)\n")
            if let kind = outcome.summaryLine.split(separator: " ").first, kind != "refused" { drawnCountByKind[String(kind), default: 0] += 1 }
        }
        XCTAssertEqual(everyLine.hexadecimal, Self.expectedDigest, "drawn: \(drawnCountByKind.sorted { $0.key < $1.key })")
        for kind in ["state", "class", "er", "requirement"] { XCTAssertGreaterThan(drawnCountByKind[kind, default: 0], 500, kind) }
    }

    /// Random texts of each type, and the documentation examples and compatibility inputs of each changed one to four
    /// times, every other change kept to ASCII so that the readers' byte paths and their String paths are both taken.
    static func sources() throws -> [String] {
        var sources: [String] = []
        var states = StateRandomTexts(seed: 51)
        var classes = ClassRandomTexts(seed: 52)
        var entities = EntityRelationshipRandomTexts(seed: 53)
        var requirements = RequirementRandomTexts(seed: 54)
        for round in 0..<600 {
            let count = 4 + round % 12
            sources += [states.text(statementCount: count), classes.text(statementCount: count), entities.text(statementCount: count),
                        requirements.text(statementCount: count)]
        }
        var mutations = GraphTextMutations(seed: 55)
        let pieces = GraphTextMutations.commonPieces + ["-->", "[*]", "state ", "note left of ", "end note", "<<fork>>", "+get(int)$", "List~int~",
                                                        "||--o{", "}|..|{", "PK", "FK", "requirement ", "element ", "satisfies", "id: 1", "text: x",
                                                        "checkout_req", "  a_b", "color:red", "fill:#f00", "\u{0B}", "\u{0C}"]
        for prefix in ["state", "class", "er", "requirement"] {
            let originals = try PeleResults.sources(ofCorpus: "\(prefix)-docs")
                + PeleResults.compatInputs().filter { $0.key.hasPrefix("\(prefix)/") }.sorted { $0.key < $1.key }.flatMap(\.value)
            for round in 0..<1_200 {
                let mutated = mutations.mutated(originals[round % originals.count], pieces: pieces)
                sources.append(round % 2 == 0 ? mutated : GraphTextMutations.ascii(mutated))
            }
        }
        return sources
    }
}
