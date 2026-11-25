/**
 * File: MapReadingEquivalence.swift
 * ---------------------------------
 * Layer: Tests
 * Description: What the reader equivalence tests of the Git graph, mindmap, architecture, tree view, Wardley map,
 *              Cynefin and Ishikawa readers share: the texts compared (every corpus input, every spec text, each
 *              changed at random), the cursor the reader hands a type's parser, and the comparison of a parser's
 *              model or error with the frozen 0.7.0 parser's.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 24/11/2026
 */

import XCTest
@testable import MermaidDiagrams
@testable import MermaidDiagramsBenchmark

enum MapReadingEquivalence {
    /// Every corpus input and every text of Pele's specs, each type's and the others'.
    static func everyText() throws -> [String] {
        let corpora = try OutputDigest.corpora().flatMap(\.sources)
        let specs = try PeleResults.compatInputs().sorted { first, second in first.key < second.key }.flatMap(\.value)
        return corpora + specs
    }

    /// The front end's cursor after the type's keyword, as the reader hands it to the type's parser, when `source` is
    /// read as `keyword`'s type; nil otherwise.
    static func cursor(of source: String, readAs keyword: MermaidTypeKeyword) -> MermaidTextCursor? {
        guard source.utf8.count <= MermaidDiagramLimits.standard.maximumSourceBytes, let frontEnd = try? MermaidFrontEnd.read(source),
              frontEnd.typeKeyword == keyword else { return nil }
        return MermaidTextCursor(frontEnd)
    }

    /// What a parser gives: its model, or the error it throws.
    static func outcome<Model>(_ parse: () throws(MermaidDiagramReadError) -> Model) -> Result<Model, MermaidDiagramReadError> {
        do { return .success(try parse()) } catch { return .failure(error) }
    }

    /// The texts of `keyword`'s type among `texts`, each also changed `mutationCount` times at random with `tokens`
    /// inserted, cut and spliced.
    static func texts(readAs keyword: MermaidTypeKeyword, among texts: [String], mutationCount: Int, tokens: [String], seed: UInt64) -> [String] {
        let own = texts.filter { text in cursor(of: text, readAs: keyword) != nil }
        var mutations = MapReadingMutations(seed: seed, tokens: tokens)
        var changed: [String] = []
        for text in own {
            for _ in 0..<mutationCount { changed.append(mutations.mutated(text)) }
        }
        return own + changed
    }
}

/// Changes made to a text to read it both ways: lines cut, pieces of the text spliced elsewhere, and tokens the type's
/// reader treats apart inserted at random places, with text beyond ASCII and Unicode white space.
struct MapReadingMutations {
    private var state: UInt64
    private let tokens: [String]

    static let sharedTokens = ["\n", "\r\n", "\r", "\t", " ", "  ", "    ", "%%", "%% comment\n", "%%{init: {}}%%\n", "é", "中", "🚀", "\u{2028}",
                               "\u{00A0}", "\u{3000}", "\u{FEFF}", "\"", "'", "\\", ":", ";", "(", ")", "[", "]", "{", "}", "<", ">", "#", ",", "-",
                               "0", "0.5", "12", "title t", "accTitle: t", "accDescr: d", "accDescr { d\n}", "<br>", "&amp;", "---\n"]

    init(seed: UInt64, tokens: [String]) {
        state = seed
        self.tokens = Self.sharedTokens + tokens
    }

    /// SplitMix64.
    private mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var mixed = state
        mixed = (mixed ^ (mixed >> 30)) &* 0xBF58_476D_1CE4_E5B9
        mixed = (mixed ^ (mixed >> 27)) &* 0x94D0_49BB_1331_11EB
        return mixed ^ (mixed >> 31)
    }

    mutating func below(_ bound: Int) -> Int {
        bound <= 1 ? 0 : Int(next() % UInt64(bound))
    }

    /// `source` changed one to three times.
    mutating func mutated(_ source: String) -> String {
        var scalars = Array(source.unicodeScalars)
        for _ in 0...below(3) {
            switch below(4) {
            case 0: cutLine(&scalars)
            case 1: splice(&scalars)
            default: scalars.insert(contentsOf: tokens[below(tokens.count)].unicodeScalars, at: below(scalars.count + 1))
            }
        }
        var text = String.UnicodeScalarView()
        text.append(contentsOf: scalars)
        return String(text)
    }

    private mutating func cutLine(_ scalars: inout [Unicode.Scalar]) {
        let lineStarts = [0] + scalars.indices.filter { index in scalars[index] == "\n" }.map { index in index + 1 }
        let start = lineStarts[below(lineStarts.count)]
        let end = scalars[start...].firstIndex(of: "\n").map { index in index + 1 } ?? scalars.count
        scalars.removeSubrange(start..<end)
    }

    private mutating func splice(_ scalars: inout [Unicode.Scalar]) {
        guard !scalars.isEmpty else { return }
        let start = below(scalars.count)
        let piece = Array(scalars[start..<min(scalars.count, start + 1 + below(12))])
        scalars.insert(contentsOf: piece, at: below(scalars.count + 1))
    }
}
