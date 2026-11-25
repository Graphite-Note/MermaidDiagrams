/**
 * File: FirstMatchTokenizerEquivalenceTests.swift
 * -----------------------------------------------
 * Layer: Tests
 * Description: The compiled first-match tokenizer splits every event model and railroad text (every corpus input,
 *              every other corpus's inputs, texts made of the grammars' pieces at random, mutated examples, hostile
 *              texts) into the same tokens, or fails at the same byte, as MermaidDiagrams 0.7.0's frozen tokenizer.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 24/11/2026
 */

import XCTest
@testable import MermaidDiagrams
@testable import MermaidDiagramsBenchmark

final class FirstMatchTokenizerEquivalenceTests: XCTestCase {
    /// Each grammar's tokenizer and its frozen reference, as functions from a text's bytes to its tokens' kinds and
    /// places, or the place of the failure.
    private struct Grammar {
        let name: String
        let tokens: ([UInt8], Int) -> String
        let reference: ([UInt8], Int) -> String
    }

    private static func describe<Kind>(_ tokens: () throws(FirstMatchTokenizerFailure) -> [FirstMatchToken<Kind>]) -> String {
        do { return try tokens().map { token in "\(token.kind)@\(token.start)-\(token.end)" }.joined(separator: " ") } catch {
            return "fails at \(error.position)"
        }
    }

    private static func describeReference<Kind>(_ tokens: () throws(ReferenceFirstMatchTokenizerFailure) -> [ReferenceFirstMatchToken<Kind>]) -> String {
        do { return try tokens().map { token in "\(token.kind)@\(token.start)-\(token.end)" }.joined(separator: " ") } catch {
            return "fails at \(error.position)"
        }
    }

    private static var grammars: [Grammar] { [
        Grammar(name: "event model", tokens: { bytes, start in describe { () throws(FirstMatchTokenizerFailure) in try EventModelLexer.tokenizer.tokens(of: bytes, from: start) } },
                reference: { bytes, start in
                    describeReference { () throws(ReferenceFirstMatchTokenizerFailure) in try ReferenceEventModelLexer.tokenizer.tokens(of: bytes, from: start) }
                }),
        Grammar(name: "railroad", tokens: { bytes, start in describe { () throws(FirstMatchTokenizerFailure) in try RailroadLexers.constructorNotation.tokens(of: bytes, from: start) } },
                reference: { bytes, start in
                    describeReference { () throws(ReferenceFirstMatchTokenizerFailure) in try ReferenceRailroadLexers.constructorNotation.tokens(of: bytes, from: start) }
                }),
        Grammar(name: "EBNF", tokens: { bytes, start in describe { () throws(FirstMatchTokenizerFailure) in try RailroadLexers.extendedBackusNaurForm.tokens(of: bytes, from: start) } },
                reference: { bytes, start in
                    describeReference { () throws(ReferenceFirstMatchTokenizerFailure) in try ReferenceRailroadLexers.extendedBackusNaurForm.tokens(of: bytes, from: start) }
                }),
        Grammar(name: "ABNF", tokens: { bytes, start in describe { () throws(FirstMatchTokenizerFailure) in try RailroadLexers.augmentedBackusNaurForm.tokens(of: bytes, from: start) } },
                reference: { bytes, start in
                    describeReference { () throws(ReferenceFirstMatchTokenizerFailure) in try ReferenceRailroadLexers.augmentedBackusNaurForm.tokens(of: bytes, from: start) }
                }),
        Grammar(name: "PEG", tokens: { bytes, start in describe { () throws(FirstMatchTokenizerFailure) in try RailroadLexers.parsingExpressionGrammar.tokens(of: bytes, from: start) } },
                reference: { bytes, start in
                    describeReference { () throws(ReferenceFirstMatchTokenizerFailure) in try ReferenceRailroadLexers.parsingExpressionGrammar.tokens(of: bytes, from: start) }
                }),
    ] }

    /// The texts on which some grammar's tokens differ from its reference's, at most five, with the start of each.
    private func differences(in sources: [String]) -> [String] {
        var found: [String] = []
        let grammars = Self.grammars
        for source in sources {
            let bytes = Array(source.utf8)
            let starts = [0, bytes.firstIndex(of: MermaidByte.newline).map { index in index + 1 } ?? bytes.count]
            for grammar in grammars {
                for start in starts where grammar.tokens(bytes, start) != grammar.reference(bytes, start) {
                    found.append("\(grammar.name) from \(start) in \(String(source.prefix(120)).debugDescription)")
                    if found.count == 5 { return found }
                }
            }
        }
        return found
    }

    func testEveryCorpusInputSplitsAsTheReferenceSplitsIt() throws {
        let sources = try OutputDigest.corpora().flatMap(\.sources)
        XCTAssertGreaterThan(sources.count, 800)
        XCTAssertEqual(differences(in: sources), [])
    }

    /// The grammars' pieces put together at random: words, signs, names, strings, comments, front matter, directives,
    /// data blocks, accessibility statements, numbers and white space of every kind.
    func testRandomTextsOfTheGrammarsPiecesSplitAsTheReferenceSplitsThem() {
        let pieces = ["eventmodeling", "tf", "01", "123", "1234", "evt", "cmd", "rmo", "ui", "pcr", "Order", "Order.Placed", "->>", "[[", "]]", "`", ".",
                      "{", "}", "{\n", "\n}", "\n}\n", "{ \"a\": 1 }", "\"q\"", "'q'", "\"a\\\"b\"", "\"open", "data", "note", "gwt", "given", "when",
                      "then", "resetframe", "rf", "md", "json", "jsobj", "accTitle: t", "accTitle:", "accDescr: d", "accDescr { d }", "accDescr {",
                      "title", "title x", "titled", "%%", "%% c\n", "%%{init: {}}%%\n", "%%{", "}%%", "---\n", "---\na: 1\n---\n", "/*", "*/", "/* c */",
                      "//", "// c\n", "(*", "*)", "(* c *)", "#", "# c\n", ";", "; c\n", "::=", "=", "<-", "|", "/", "&", "!", "?", "? s ?", "*", "+",
                      "-", ",", "(", ")", "[", "]", "terminal", "nonterminal", "sequence", "choice", "optional", "zeroOrMore", "oneOrMore", "special",
                      "%x41", "%d65.66", "%x30-39", "%b", "2*4", "*", "3", "rule-name", "_x", "x_1", "é", "中", "\u{2028}", "\u{00A0}", "\u{3000}",
                      "\u{FEFF}", "\t", " ", "  ", "\n", "\r\n", "\r", "\\", "\u{0}", "~"]
        var random = SplitMix(seed: 0x70_CE_4E_12)
        var sources: [String] = []
        for _ in 0..<6_000 {
            var text = ""
            for _ in 0..<(1 + random.below(24)) { text += pieces[random.below(pieces.count)] + (random.below(3) == 0 ? " " : "") }
            sources.append(text)
        }
        XCTAssertEqual(differences(in: sources), [])
    }

    /// The event model and railroad documentation examples cut, spliced and with pieces inserted.
    func testMutatedExamplesSplitAsTheReferenceSplitsThem() throws {
        let examples = try PeleResults.sources(ofCorpus: "eventmodeling-docs") + PeleResults.sources(ofCorpus: "railroad-docs")
        var mutations = FlowchartReadingMutations(seed: 0x70_CE_4E_13)
        var sources: [String] = []
        for index in 0..<6_000 { sources.append(mutations.mutated(examples[index % examples.count])) }
        XCTAssertEqual(differences(in: sources), [])
    }

    /// Long runs of openers without their closers, deep runs of one sign and long lines split the same, in time that
    /// grows with the text.
    func testHostileTextsSplitAsTheReferenceSplitsThemInLinearTime() {
        let sources = [String(repeating: "/*", count: 20_000), String(repeating: "%%{", count: 20_000), String(repeating: "{\n", count: 20_000),
                       String(repeating: "\"a", count: 20_000), String(repeating: "(*", count: 20_000), String(repeating: "---\n", count: 20_000),
                       String(repeating: "accDescr {", count: 5_000), String(repeating: "x", count: 200_000), String(repeating: "[[", count: 50_000)]
        let clock = ContinuousClock()
        let started = clock.now
        XCTAssertEqual(differences(in: sources), [])
        XCTAssertLessThan(clock.now - started, .seconds(20))
    }

    private struct SplitMix {
        private var state: UInt64

        init(seed: UInt64) {
            state = seed
        }

        mutating func below(_ bound: Int) -> Int {
            state &+= 0x9E37_79B9_7F4A_7C15
            var mixed = state
            mixed = (mixed ^ (mixed >> 30)) &* 0xBF58_476D_1CE4_E5B9
            mixed = (mixed ^ (mixed >> 27)) &* 0x94D0_49BB_1331_11EB
            return Int((mixed ^ (mixed >> 31)) % UInt64(bound))
        }
    }
}
