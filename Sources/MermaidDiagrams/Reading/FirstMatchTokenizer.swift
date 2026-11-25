/**
 * File: FirstMatchTokenizer.swift
 * -------------------------------
 * Layer: Core
 * Description: Splits a diagram's text into tokens as the lexers Mermaid generates for its Langium grammars do: rules
 *              tried in order, the first that matches wins, unless a longer alternative matches more. The rules are
 *              compiled once into a table of the rules each first byte allows and flat records of their matchers.
 *
 * Authors: Bahey Shalash
 * Version: 0.2
 * Date: 24/11/2026
 */

/// What a token rule found at a position.
enum FirstMatchTokenMatch {
    case matched(end: Int)
    case none
    /// No match here, and none at any later position: what would close the token is nowhere further on, so the rule is
    /// not tried again in this text.
    case noneFurtherOn
}

/// One token rule: its name (for longer alternatives and diagnostics), its kind (nil for text that is skipped, such as
/// whitespace and comments), the ASCII bytes a match can start with (nil for any), the rules tried at the same place
/// once it matches, the first of which that matches more text gives the token, and how it matches.
struct FirstMatchTokenRule<Kind: Sendable>: Sendable {
    let name: String
    let kind: Kind?
    let firstBytes: [UInt8]?
    let longerAlternativeNames: [String]
    let matcher: FirstMatchTokenMatcher

    init(_ name: String, kind: Kind?, firstBytes: [UInt8]? = nil, longerAlternatives: [String] = [], match matcher: FirstMatchTokenMatcher) {
        self.name = name
        self.kind = kind
        self.firstBytes = firstBytes
        self.longerAlternativeNames = longerAlternatives
        self.matcher = matcher
    }
}

/// A token of the text: its kind and where its bytes are.
struct FirstMatchToken<Kind: Sendable>: Sendable {
    let kind: Kind
    let start: Int
    let end: Int
}

/// The position of the first byte no rule matches.
struct FirstMatchTokenizerFailure: Error {
    let position: Int
}

/// The bytes being split, and where each closing sequence the rules search ahead for was last found, so that a rule
/// that looks ahead for one (`*/`, `}`) reads each part of the text once, whatever the number of openers before it. The
/// searches are kept in a short list of the few closing sequences a grammar has.
struct FirstMatchTokenizerText {
    let bytes: [UInt8]
    private var searches: [(needle: [UInt8], from: Int, found: Int?)] = []

    init(bytes: [UInt8]) {
        self.bytes = bytes
    }

    /// The position of the first `needle` at or after `position`, or nil.
    mutating func firstOccurrence(of needle: [UInt8], from position: Int) -> Int? {
        let slot = searches.firstIndex { search in search.needle == needle }
        if let slot, searches[slot].from <= position {
            guard let found = searches[slot].found else { return nil }
            if found >= position { return found }
        }
        let found = Self.search(bytes, for: needle, from: position)
        if let slot { searches[slot] = (needle, position, found) } else { searches.append((needle, position, found)) }
        return found
    }

    private static func search(_ bytes: [UInt8], for needle: [UInt8], from position: Int) -> Int? {
        guard let first = needle.first else { return position <= bytes.count ? position : nil }
        var index = max(position, 0)
        while index + needle.count <= bytes.count {
            if bytes[index] == first {
                var offset = 1
                while offset < needle.count, bytes[index + offset] == needle[offset] { offset += 1 }
                if offset == needle.count { return index }
            }
            index += 1
        }
        return nil
    }
}

/// Rules tried in order at each position, as Chevrotain tries them: only those whose first bytes allow the byte there
/// (any rule at a byte beyond ASCII), the first that matches makes the token, unless one of its longer alternatives
/// matches more text. Each rule that reports no match further on is skipped for the rest of the text. The rules are
/// compiled when the tokenizer is made: the rules each byte allows into one list with a range per byte, the longer
/// alternatives into another, and the matchers into `FirstMatchCompiledMatchers`.
struct FirstMatchTokenizer<Kind: Sendable>: Sendable {
    let rules: [FirstMatchTokenRule<Kind>]
    private let kinds: [Kind?]
    private let matchers: FirstMatchCompiledMatchers
    /// The rules to try, by first byte: `ruleRanges[byte]` for an ASCII byte, `ruleRanges[128]` (every rule) beyond.
    private let ruleIndices: [UInt8]
    private let ruleRanges: [Range<Int>]
    private let alternativeIndices: [UInt8]
    private let alternativeRanges: [Range<Int>]

    /// The most rules a tokenizer has: the rules that report no match further on are kept as bits of one word.
    static var largestRuleCount: Int { 64 }

    init(rules: [FirstMatchTokenRule<Kind>]) {
        precondition(rules.count <= Self.largestRuleCount, "a first-match tokenizer has at most 64 rules")
        self.rules = rules
        kinds = rules.map(\.kind)
        matchers = FirstMatchCompiledMatchers(rules.map(\.matcher))
        var indices: [UInt8] = []
        var ranges: [Range<Int>] = []
        for byte in 0...128 {
            let start = indices.count
            for (index, rule) in rules.enumerated() where byte == 128 || (rule.firstBytes.map { bytes in bytes.contains(UInt8(byte)) } ?? true) {
                indices.append(UInt8(index))
            }
            ranges.append(start..<indices.count)
        }
        ruleIndices = indices
        ruleRanges = ranges
        var alternatives: [UInt8] = []
        var alternativeRanges: [Range<Int>] = []
        for rule in rules {
            let start = alternatives.count
            for name in rule.longerAlternativeNames {
                if let index = rules.firstIndex(where: { candidate in candidate.name == name }) { alternatives.append(UInt8(index)) }
            }
            alternativeRanges.append(start..<alternatives.count)
        }
        alternativeIndices = alternatives
        self.alternativeRanges = alternativeRanges
    }

    /// The tokens of `bytes` from `start` to the end, those of rules without a kind left out.
    func tokens(of bytes: [UInt8], from start: Int) throws(FirstMatchTokenizerFailure) -> [FirstMatchToken<Kind>] {
        var text = FirstMatchTokenizerText(bytes: bytes)
        var exhausted: UInt64 = 0
        var tokens: [FirstMatchToken<Kind>] = []
        tokens.reserveCapacity(max(0, bytes.count - start) / 8)
        var position = max(start, 0)
        scanning: while position < bytes.count {
            let byte = bytes[position]
            for slot in ruleRanges[byte < 128 ? Int(byte) : 128] {
                let index = Int(ruleIndices[slot])
                guard let end = end(of: index, at: position, text: &text, exhausted: &exhausted) else { continue }
                var kindIndex = index
                var tokenEnd = end
                for alternativeSlot in alternativeRanges[index] {
                    let alternative = Int(alternativeIndices[alternativeSlot])
                    if let alternativeEnd = self.end(of: alternative, at: position, text: &text, exhausted: &exhausted), alternativeEnd > tokenEnd {
                        kindIndex = alternative
                        tokenEnd = alternativeEnd
                        break
                    }
                }
                if let kind = kinds[kindIndex] { tokens.append(FirstMatchToken(kind: kind, start: position, end: tokenEnd)) }
                position = tokenEnd
                continue scanning
            }
            throw FirstMatchTokenizerFailure(position: position)
        }
        return tokens
    }

    /// Where the rule's match at `position` ends, when it matches at least one byte.
    @inline(__always)
    private func end(of index: Int, at position: Int, text: inout FirstMatchTokenizerText, exhausted: inout UInt64) -> Int? {
        let bit: UInt64 = 1 << UInt64(index)
        guard exhausted & bit == 0 else { return nil }
        switch matchers.match(index, in: &text, at: position) {
        case .matched(let end): return end > position ? end : nil
        case .none: return nil
        case .noneFurtherOn:
            exhausted |= bit
            return nil
        }
    }
}
