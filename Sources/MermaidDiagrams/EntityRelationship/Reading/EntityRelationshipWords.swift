/**
 * File: EntityRelationshipWords.swift
 * -----------------------------------
 * Layer: Core
 * Description: The words and symbols Mermaid's entity relationship lexer reads as cardinalities, lines and keywords
 *              wherever they stand, found on the text's borrowed bytes by their first byte.
 *
 * Authors: felixchvl, Bahey Shalash
 * Version: 0.2
 * Date: 25/11/2026
 */

/// The words and symbols that Mermaid's entity relationship lexer reads as cardinalities, lines and statement keywords
/// wherever they stand, before it reads a name, matched without regard to case. Where two start alike the first listed
/// is tried first, as in Mermaid's lexer.
enum EntityRelationshipWords {
    /// A word or symbol and its token.
    struct Entry: Sendable {
        /// The word in lowercase ASCII bytes.
        let word: [UInt8]
        let token: EntityRelationshipToken
        /// Whether a letter, digit or `_` may not follow it, so that `toy` is a name and `to` a line.
        let endsAtWordBoundary: Bool

        init(_ word: String, _ token: EntityRelationshipToken, endsAtWordBoundary: Bool) {
            self.word = Array(word.utf8)
            self.token = token
            self.endsAtWordBoundary = endsAtWordBoundary
        }
    }

    static let entries: [Entry] = [
        Entry("erdiagram", .keyword(.diagram), endsAtWordBoundary: true),
        Entry("end", .keyword(.end), endsAtWordBoundary: true),
        Entry("style", .keyword(.style), endsAtWordBoundary: true),
        Entry("subgraph", .keyword(.subgraph), endsAtWordBoundary: true),
        Entry("classdef", .keyword(.classDefinition), endsAtWordBoundary: true),
        Entry("class", .keyword(.classAssignment), endsAtWordBoundary: true),
        Entry("one or zero", .cardinality(.zeroOrOne), endsAtWordBoundary: true),
        Entry("one or more", .cardinality(.oneOrMore), endsAtWordBoundary: true),
        Entry("one or many", .cardinality(.oneOrMore), endsAtWordBoundary: true),
        Entry("one", .cardinality(.exactlyOne), endsAtWordBoundary: true),
        Entry("only one", .cardinality(.exactlyOne), endsAtWordBoundary: true),
        Entry("o|", .cardinality(.zeroOrOne), endsAtWordBoundary: false),
        Entry("o{", .cardinality(.zeroOrMore), endsAtWordBoundary: false),
        Entry("optionally to", .identification(.nonIdentifying), endsAtWordBoundary: true),
        Entry("zero or one", .cardinality(.zeroOrOne), endsAtWordBoundary: true),
        Entry("zero or more", .cardinality(.zeroOrMore), endsAtWordBoundary: true),
        Entry("zero or many", .cardinality(.zeroOrMore), endsAtWordBoundary: true),
        Entry("many(0)", .cardinality(.zeroOrMore), endsAtWordBoundary: false),
        Entry("many(1)", .cardinality(.oneOrMore), endsAtWordBoundary: false),
        Entry("many", .cardinality(.zeroOrMore), endsAtWordBoundary: true),
        Entry("to", .identification(.identifying), endsAtWordBoundary: true),
        Entry("|o", .cardinality(.zeroOrOne), endsAtWordBoundary: true),
        Entry("||", .cardinality(.exactlyOne), endsAtWordBoundary: false),
        Entry("|{", .cardinality(.oneOrMore), endsAtWordBoundary: false),
        Entry("}o", .cardinality(.zeroOrMore), endsAtWordBoundary: true),
        Entry("}|", .cardinality(.oneOrMore), endsAtWordBoundary: false),
        Entry("..", .identification(.nonIdentifying), endsAtWordBoundary: false),
        Entry(".-", .identification(.nonIdentifying), endsAtWordBoundary: false),
        Entry("--", .identification(.identifying), endsAtWordBoundary: false),
        Entry("-.", .identification(.nonIdentifying), endsAtWordBoundary: false),
    ]

    /// Reads the first entry that matches at the cursor and returns its token, or nil when none does. `u` before `.`,
    /// `-` or `|` is the parent cardinality; the character after it stays for the line.
    static func readToken(_ bytes: inout GraphDiagramBytes) -> EntityRelationshipToken? {
        guard let first = bytes.peek().map(MermaidByte.lowercased) else { return nil }
        if first == letterU, let next = bytes.peek(1), next == MermaidByte.period || next == MermaidByte.hyphen || next == MermaidByte.verticalBar {
            bytes.advance()
            return .cardinality(.parent)
        }
        guard first < 0x80, case let candidates = entryIndicesByFirstByte[Int(first)], !candidates.isEmpty else { return nil }
        for index in candidates where bytes.hasCaseInsensitivePrefix(entries[index].word) {
            let entry = entries[index]
            if entry.endsAtWordBoundary, let next = bytes.peek(entry.word.count), isWordByte(next) { continue }
            bytes.advance(by: entry.word.count)
            return entry.token
        }
        return nil
    }

    /// The indexes of `entries` by their word's first byte, in their order, so that a name's first byte is looked up
    /// once instead of compared with every entry.
    private static let entryIndicesByFirstByte: [[Int]] = {
        var indices = [[Int]](repeating: [], count: 128)
        for (index, entry) in entries.enumerated() { indices[Int(entry.word[0])].append(index) }
        return indices
    }()

    /// A letter, a digit or `_`: what a word boundary has on one side only.
    static func isWordByte(_ byte: UInt8) -> Bool {
        MermaidByte.isLetter(byte) || MermaidByte.isDigit(byte) || byte == MermaidByte.underscore
    }

    private static let letterU = UInt8(ascii: "u")
}
