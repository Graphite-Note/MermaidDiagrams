/**
 * File: FirstMatchTokenizer.swift
 * -------------------------------
 * Layer: Core
 * Description: Splits a diagram's text into tokens as the lexers Mermaid generates for its Langium grammars do: rules
 *              tried in order, the first that matches wins, unless a longer alternative matches more.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 19/11/2026
 */

/// What a token rule found at a position.
enum FirstMatchTokenMatch {
    case matched(end: Int)
    case none
    /// No match here, and none at any later position: what would close the token is nowhere further on, so the rule is
    /// not tried again in this text.
    case noneFurtherOn
}

/// One token rule: its kind (nil for text that is skipped, such as whitespace and comments), the ASCII bytes a match
/// can start with (nil for any), the rules tried at the same place once it matches, the first of which that matches
/// more text gives the token, and how it matches.
struct FirstMatchTokenRule<Kind: Sendable>: Sendable {
    let name: String
    let kind: Kind?
    let firstBytes: [UInt8]?
    let longerAlternativeNames: [String]
    let match: @Sendable (inout FirstMatchTokenizerText, Int) -> FirstMatchTokenMatch

    init(_ name: String, kind: Kind?, firstBytes: [UInt8]? = nil, longerAlternatives: [String] = [],
         match: @escaping @Sendable (inout FirstMatchTokenizerText, Int) -> FirstMatchTokenMatch) {
        self.name = name
        self.kind = kind
        self.firstBytes = firstBytes
        self.longerAlternativeNames = longerAlternatives
        self.match = match
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
/// that looks ahead for one (`*/`, `}`) reads each part of the text once, whatever the number of openers before it.
struct FirstMatchTokenizerText {
    let bytes: [UInt8]
    private var searches: [[UInt8]: (from: Int, found: Int?)] = [:]

    init(bytes: [UInt8]) {
        self.bytes = bytes
    }

    /// The position of the first `needle` at or after `position`, or nil.
    mutating func firstOccurrence(of needle: [UInt8], from position: Int) -> Int? {
        if let search = searches[needle], search.from <= position {
            guard let found = search.found else { return nil }
            if found >= position { return found }
        }
        var index = position
        var found: Int?
        while index + needle.count <= bytes.count {
            if bytes[index] == needle[0], needle.indices.allSatisfy({ offset in bytes[index + offset] == needle[offset] }) {
                found = index
                break
            }
            index += 1
        }
        searches[needle] = (position, found)
        return found
    }
}

/// Rules tried in order at each position, as Chevrotain tries them: only those whose first bytes allow the byte there
/// (any rule at a byte beyond ASCII), the first that matches makes the token, unless one of its longer alternatives
/// matches more text. Each rule that reports no match further on is skipped for the rest of the text.
struct FirstMatchTokenizer<Kind: Sendable>: Sendable {
    let rules: [FirstMatchTokenRule<Kind>]
    private let rulesByFirstByte: [[Int]]
    private let longerAlternatives: [[Int]]

    init(rules: [FirstMatchTokenRule<Kind>]) {
        self.rules = rules
        rulesByFirstByte = (0..<128).map { byte in
            rules.indices.filter { index in rules[index].firstBytes.map { bytes in bytes.contains(UInt8(byte)) } ?? true }
        }
        longerAlternatives = rules.map { rule in
            rule.longerAlternativeNames.compactMap { name in rules.firstIndex { candidate in candidate.name == name } }
        }
    }

    /// The tokens of `bytes` from `start` to the end, those of rules without a kind left out.
    func tokens(of bytes: [UInt8], from start: Int) throws(FirstMatchTokenizerFailure) -> [FirstMatchToken<Kind>] {
        var text = FirstMatchTokenizerText(bytes: bytes)
        var exhausted = [Bool](repeating: false, count: rules.count)
        var tokens: [FirstMatchToken<Kind>] = []
        var position = start
        let allRules = Array(rules.indices)
        scanning: while position < bytes.count {
            let byte = bytes[position]
            for index in byte < 128 ? rulesByFirstByte[Int(byte)] : allRules {
                guard let end = Self.end(of: index, at: position, rules: rules, text: &text, exhausted: &exhausted) else { continue }
                var kindIndex = index
                var tokenEnd = end
                for alternative in longerAlternatives[index] {
                    if let alternativeEnd = Self.end(of: alternative, at: position, rules: rules, text: &text, exhausted: &exhausted),
                       alternativeEnd > tokenEnd {
                        kindIndex = alternative
                        tokenEnd = alternativeEnd
                        break
                    }
                }
                if let kind = rules[kindIndex].kind { tokens.append(FirstMatchToken(kind: kind, start: position, end: tokenEnd)) }
                position = tokenEnd
                continue scanning
            }
            throw FirstMatchTokenizerFailure(position: position)
        }
        return tokens
    }

    /// Where the rule's match at `position` ends, when it matches at least one byte.
    private static func end(of index: Int, at position: Int, rules: [FirstMatchTokenRule<Kind>], text: inout FirstMatchTokenizerText,
                            exhausted: inout [Bool]) -> Int? {
        guard !exhausted[index] else { return nil }
        switch rules[index].match(&text, position) {
        case .matched(let end): return end > position ? end : nil
        case .none: return nil
        case .noneFurtherOn:
            exhausted[index] = true
            return nil
        }
    }
}
