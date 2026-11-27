/**
 * File: EntityRelationshipWords.swift
 * -----------------------------------
 * Layer: Core
 * Description: The words and symbols Mermaid's entity relationship lexer reads as cardinalities, lines and keywords
 *              wherever they stand, found on the text's borrowed bytes by their first byte and compared with literals.
 *
 * Authors: felixchvl, Bahey Shalash
 * Version: 0.3
 * Date: 26/11/2026
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
    /// `-` or `|` is the parent cardinality; the character after it stays for the line. The entries that start with the
    /// cursor's byte are tried in their order (`entries`), each compared with a literal of its word.
    static func readToken(_ bytes: inout GraphDiagramBytes) -> EntityRelationshipToken? {
        guard let first = bytes.peek().map(MermaidByte.lowercased) else { return nil }
        if first == letterU, let next = bytes.peek(1), next == MermaidByte.period || next == MermaidByte.hyphen || next == MermaidByte.verticalBar {
            bytes.advance()
            return .cardinality(.parent)
        }
        switch first {
        case UInt8(ascii: "e"):
            return read("erdiagram", .keyword(.diagram), true, &bytes) ?? read("end", .keyword(.end), true, &bytes)
        case UInt8(ascii: "s"):
            return read("style", .keyword(.style), true, &bytes) ?? read("subgraph", .keyword(.subgraph), true, &bytes)
        case UInt8(ascii: "c"):
            return read("classdef", .keyword(.classDefinition), true, &bytes) ?? read("class", .keyword(.classAssignment), true, &bytes)
        case UInt8(ascii: "o"): return readStartingWithO(&bytes)
        case UInt8(ascii: "z"):
            return read("zero or one", .cardinality(.zeroOrOne), true, &bytes) ?? read("zero or more", .cardinality(.zeroOrMore), true, &bytes)
                ?? read("zero or many", .cardinality(.zeroOrMore), true, &bytes)
        case UInt8(ascii: "m"):
            return read("many(0)", .cardinality(.zeroOrMore), false, &bytes) ?? read("many(1)", .cardinality(.oneOrMore), false, &bytes)
                ?? read("many", .cardinality(.zeroOrMore), true, &bytes)
        case UInt8(ascii: "t"): return read("to", .identification(.identifying), true, &bytes)
        case MermaidByte.verticalBar:
            return read("|o", .cardinality(.zeroOrOne), true, &bytes) ?? read("||", .cardinality(.exactlyOne), false, &bytes)
                ?? read("|{", .cardinality(.oneOrMore), false, &bytes)
        case MermaidByte.closingBrace:
            return read("}o", .cardinality(.zeroOrMore), true, &bytes) ?? read("}|", .cardinality(.oneOrMore), false, &bytes)
        case MermaidByte.period:
            return read("..", .identification(.nonIdentifying), false, &bytes) ?? read(".-", .identification(.nonIdentifying), false, &bytes)
        case MermaidByte.hyphen:
            return read("--", .identification(.identifying), false, &bytes) ?? read("-.", .identification(.nonIdentifying), false, &bytes)
        default: return nil
        }
    }

    /// The entries that start with `o`, in their order.
    private static func readStartingWithO(_ bytes: inout GraphDiagramBytes) -> EntityRelationshipToken? {
        read("one or zero", .cardinality(.zeroOrOne), true, &bytes) ?? read("one or more", .cardinality(.oneOrMore), true, &bytes)
            ?? read("one or many", .cardinality(.oneOrMore), true, &bytes) ?? read("one", .cardinality(.exactlyOne), true, &bytes)
            ?? read("only one", .cardinality(.exactlyOne), true, &bytes) ?? read("o|", .cardinality(.zeroOrOne), false, &bytes)
            ?? read("o{", .cardinality(.zeroOrMore), false, &bytes) ?? read("optionally to", .identification(.nonIdentifying), true, &bytes)
    }

    /// `token` when `word` (lowercase) is written at the cursor in any case, and, when `endsAtWordBoundary`, no letter,
    /// digit or `_` follows it: the cursor then moves past it. Nil otherwise, the cursor left.
    @inline(__always)
    private static func read(_ word: StaticString, _ token: EntityRelationshipToken, _ endsAtWordBoundary: Bool,
                             _ bytes: inout GraphDiagramBytes) -> EntityRelationshipToken? {
        guard bytes.hasCaseInsensitivePrefix(word) else { return nil }
        let count = word.utf8CodeUnitCount
        if endsAtWordBoundary, let next = bytes.peek(count), isWordByte(next) { return nil }
        bytes.advance(by: count)
        return token
    }

    /// A letter, a digit or `_`: what a word boundary has on one side only.
    static func isWordByte(_ byte: UInt8) -> Bool {
        MermaidByte.isLetter(byte) || MermaidByte.isDigit(byte) || byte == MermaidByte.underscore
    }

    private static let letterU = UInt8(ascii: "u")
}
