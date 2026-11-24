/**
 * File: TypeReaderBytesTests.swift
 * --------------------------------
 * Layer: Tests
 * Description: Checks the agent flow, use case, requirement, Git graph, Gantt, XY chart, architecture and radar readers
 *              that read UTF-8 bytes where they read characters, UTF-16 code units or Unicode scalars: the models they
 *              make of their documentation examples, cut, mixed with white space beyond ASCII, combining marks and the
 *              punctuation and keywords of their grammars, against a digest of the models the readers made before.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 23/11/2026
 */

import Foundation
@testable import MermaidDiagrams
@testable import MermaidDiagramsBenchmark
import XCTest

final class TypeReaderBytesTests: XCTestCase {
    /// The keywords and punctuation of the eight grammars, put into the examples beside the pieces of
    /// `TypeReaderSpeedTests`: arrows, separators, brackets, quotation marks, numbers and the words that open statements.
    private static let grammarPieces = ["-->", "--", "->", "<--", "-.->", "==>", "|", ";", "=", ":", "::", "{", "}", "[", "]", "(", ")",
                                        "<<", ">>", "\"", "'", "`", "@", "$", "*", "+", "-", "/", ",", ".", "#", "%%", "%%{", "}%%",
                                        "commit", "branch", "merge", "checkout", "id:", "tag:", "type:", "section", "title", "dateFormat",
                                        "excludes", "after", "x-axis", "y-axis", "bar", "line", "[1, 2.5]", "-1", "1e3", "0.5", "requirement",
                                        "element", "satisfies", "risk:", "group", "service", "junction", "L", "R", "T", "B", "in", "axis",
                                        "curve", "actor", "usecase", "system", "agent", "tool", "flow", "classDef", "style", "direction",
                                        "TB", "LR", "accTitle", "accDescr", "\u{A0}", "\u{3000}", "\u{2028}", "é", "\u{301}", "\u{1F600}",
                                        "\t", "  ", "\n", "\r\n", "\r", "\\", "&", "<", ">"]

    /// The digests of the models (or the errors) the readers made, by corpus, before they read bytes (origin/main
    /// 3015de9): a change that alters what a reader makes of any of these texts changes its digest.
    private static let modelDigests: [String: String] = [
        "agentflow-docs": "8b59701316950a79",
        "agentflow-reference": "ce89fe88050636e2",
        "architecture-docs": "330db307d08298ae",
        "gantt-docs": "8cee22063f963e49",
        "git-docs": "8f3bde50008d6129",
        "radar-docs": "297c1303ff4a6bff",
        "requirement-docs": "4ad3088c0fb79e7e",
        "usecase-docs": "37a847eac1e6beba",
        "xychart-docs": "f06b575b0f7158",
    ]

    func testTheReadersMakeTheModelsTheyMadeOfEveryExampleCutAndMixed() throws {
        var digests: [String: String] = [:]
        for corpus in Self.modelDigests.keys.sorted() {
            let sources = try PeleResults.sources(ofCorpus: corpus)
            var digest = TypeReaderSpeedTests.offsetBasis
            for text in TypeReaderSpeedTests.variants(of: sources, seed: 0x5EED_0201) + Self.grammarVariants(of: sources, seed: 0x5EED_0202) {
                let model: String
                do {
                    model = TypeReaderSpeedTests.canonicalDescription(of: try MermaidDiagramReader.read(text, limits: .standard))
                } catch {
                    model = "refused: " + TypeReaderSpeedTests.canonicalDescription(of: error)
                }
                digest = TypeReaderSpeedTests.digest(model + "\u{0}", from: digest)
            }
            digests[corpus] = String(digest, radix: 16)
        }
        print("type reader bytes model digests: \(digests.sorted { first, second in first.key < second.key })")
        XCTAssertEqual(digests, Self.modelDigests)
    }

    /// Copies of each text with one to four of the grammar's pieces put in at character boundaries, at the start of a
    /// line or anywhere, and copies with one character taken out.
    private static func grammarVariants(of sources: [String], seed: UInt64) -> [String] {
        var state = seed
        func next(_ bound: Int) -> Int {
            state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            return bound > 0 ? Int((state >> 33) % UInt64(bound)) : 0
        }
        var variants: [String] = []
        for source in sources {
            let characters = Array(source)
            let lineStarts = [0] + characters.indices.filter { index in characters[index] == "\n" }.map { index in index + 1 }
            for round in 0..<48 {
                var mixed = characters
                for _ in 0...next(4) {
                    let piece = grammarPieces[next(grammarPieces.count)]
                    let place = round.isMultiple(of: 2) ? lineStarts[next(lineStarts.count)] : next(mixed.count + 1)
                    mixed.insert(contentsOf: piece + (round.isMultiple(of: 3) ? " " : ""), at: min(place, mixed.count))
                }
                variants.append(String(mixed))
            }
            for _ in 0..<8 where !characters.isEmpty {
                var cut = characters
                cut.remove(at: next(cut.count))
                variants.append(String(cut))
            }
        }
        return variants
    }
}
