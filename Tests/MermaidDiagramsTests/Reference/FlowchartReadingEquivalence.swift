/**
 * File: FlowchartReadingEquivalence.swift
 * ---------------------------------------
 * Layer: Tests
 * Description: Reads a text with the package and with the frozen 0.7.0 reader and says how the two readings differ:
 *              the model field by field (labels read with or without markup included), or the error with its line;
 *              and the mutations of a text the equivalence tests read both ways.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 24/11/2026
 */

@testable import MermaidDiagrams

/// The package's reading of a text against the reference's (`ReferenceMermaidReader`).
enum FlowchartReadingEquivalence {
    /// How the two readings of `source` differ, in a few words, or nil when they agree: the same flowchart, the same
    /// error, or another type that neither reads as a flowchart.
    static func difference(_ source: String, limits: MermaidDiagramLimits = .standard) -> String? {
        let reference = Result { () throws(MermaidDiagramReadError) in try ReferenceMermaidReader.read(source, limits: limits) }
        let package = Result { () throws(MermaidDiagramReadError) in try MermaidDiagramReader.read(source, limits: limits) }
        switch (reference, package) {
        case (.success(.flowchart(let expected)), .success(.flowchart(let read))), (.success(.swimlane(let expected)), .success(.swimlane(let read))):
            return modelDifference(expected, ReferenceFlowchartDiagram(read))
        case (.success(.otherType), .success(let read)):
            switch read {
            case .flowchart, .swimlane: return "read as a flowchart where the reference reads another type"
            default: return nil
            }
        case (.success(.otherType), .failure): return nil
        case (.failure(let expected), .failure(let error)): return expected == error ? nil : "error \(error) where the reference throws \(expected)"
        case (.failure(let expected), .success): return "read where the reference throws \(expected)"
        case (.success, .failure(let error)): return "throws \(error) where the reference reads"
        case (.success, .success): return "read as another kind of diagram"
        }
    }

    /// The first field in which `read` differs from `expected`, or nil.
    static func modelDifference(_ writtenExpected: ReferenceFlowchartDiagram, _ writtenRead: ReferenceFlowchartDiagram) -> String? {
        let expected = writtenExpected.withComparableSizes
        let read = writtenRead.withComparableSizes
        if expected.direction != read.direction { return "direction \(read.direction), expected \(expected.direction)" }
        if expected.nodes.count != read.nodes.count { return "\(read.nodes.count) nodes, expected \(expected.nodes.count)" }
        if let index = expected.nodes.indices.first(where: { index in expected.nodes[index] != read.nodes[index] }) {
            return "node \(index): \(read.nodes[index]), expected \(expected.nodes[index])"
        }
        if expected.edges.count != read.edges.count { return "\(read.edges.count) edges, expected \(expected.edges.count)" }
        if let index = expected.edges.indices.first(where: { index in expected.edges[index] != read.edges[index] }) {
            return "edge \(index): \(read.edges[index]), expected \(expected.edges[index])"
        }
        if expected.subgraphs != read.subgraphs { return "groups \(read.subgraphs), expected \(expected.subgraphs)" }
        if expected != read {
            return "titles or unapplied count: \(read.title ?? "-") \(read.accessibilityTitle ?? "-") \(read.accessibilityDescription ?? "-") "
                + "\(read.unappliedStatementCount), expected \(expected.title ?? "-") \(expected.accessibilityTitle ?? "-") "
                + "\(expected.accessibilityDescription ?? "-") \(expected.unappliedStatementCount)"
        }
        return read.labelReadingDifferences(from: expected).first
    }
}

/// Changes made to a text to read it both ways: lines cut, pieces of the text spliced elsewhere, and the tokens the
/// reader treats apart inserted at random places.
struct FlowchartReadingMutations {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed
    }

    /// SplitMix64.
    private mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var mixed = state
        mixed = (mixed ^ (mixed >> 30)) &* 0xBF58_476D_1CE4_E5B9
        mixed = (mixed ^ (mixed >> 27)) &* 0x94D0_49BB_1331_11EB
        return mixed ^ (mixed >> 31)
    }

    private mutating func below(_ bound: Int) -> Int {
        bound <= 1 ? 0 : Int(next() % UInt64(bound))
    }

    /// The tokens inserted: the reader's special bytes and words, text beyond ASCII and Unicode white space.
    static let insertedTokens = ["@", "@{", "@{ shape: circle }", "e1@", "direction LR", "direction TB\n", "%%", "%% comment\n", "\r", "\r\n", "é",
                                 "中", "\u{2028}", "\u{00A0}", "\u{3000}", "\t", " ", "\n", ";", "\"", "\"`", "`\"", "|", "[", "]", "{", "}", "(", ")",
                                 "-->", "---", "-.->", "==>", "~~~", "-- text -->", "&", " & ", ":::", ":::name", "subgraph x", "subgraph",
                                 "end", "end\n", "classDef a fill:#f00;", "class A a", "style A fill:#f9f", "linkStyle 0 stroke:#f00",
                                 "click A call f()", "accTitle: t", "accDescr { d }", "<b>", "<br>", "&amp;", "#9829;", "fa:fa-car", "**",
                                 "_", "\\", "\\n", "default", "v", "x", "o", "<", ">", "#", ",", "*", "0", "12", "A", "graph", "---\n"]

    /// `source` changed one to three times.
    mutating func mutated(_ source: String) -> String {
        var scalars = Array(source.unicodeScalars)
        for _ in 0...below(3) {
            switch below(4) {
            case 0: cutLine(&scalars)
            case 1: splice(&scalars)
            default:
                let token = Self.insertedTokens[below(Self.insertedTokens.count)]
                scalars.insert(contentsOf: token.unicodeScalars, at: below(scalars.count + 1))
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
