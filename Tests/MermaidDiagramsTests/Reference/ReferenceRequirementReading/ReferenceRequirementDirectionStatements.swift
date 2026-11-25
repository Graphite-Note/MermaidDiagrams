/**
 * File: ReferenceRequirementDirectionStatements.swift
 * ---------------------------------------------------
 * Layer: Tests
 * Description: 0.7.0's RequirementDirectionStatements, kept unchanged but for its names as the reference the
 *              requirement reader on bytes is compared with (RequirementReadingEquivalenceTests).
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 25/11/2026
 */

@testable import MermaidDiagrams

/// The direction statements of a requirement diagram's text, as Pele's lexer finds them: every match of
/// `/direction\s+(?:(TB)|(BT)|(RL)|LR)/gi` in one pass (the whitespace JavaScript's, line breaks included), by kind. Mermaid's
/// rules for them are tried before the others and match from anywhere on a line, so at a position the last such statement
/// that starts on the position's line, at or after it, makes the rest of that line and of the line it ends on one token.
struct ReferenceRequirementDirectionStatements {
    /// The kinds in the order Mermaid's rules try them.
    static let kinds: [FlowchartDirection] = [.topToBottom, .bottomToTop, .rightToLeft, .leftToRight]
    private static let keyword = Array("direction".utf8)

    private var starts: [[Int]] = [[], [], [], []]
    private var keywordEnds: [[Int]] = [[], [], [], []]
    /// For each kind, how many of its statements start at or before `lineEnd`.
    private var seenCounts = [0, 0, 0, 0]
    /// The end of the line the last position asked about is on.
    private var lineEnd = -1
    private let bytes: [UInt8]

    /// Whether the text holds any direction statement: when it holds none, no position needs asking about. Found once, as
    /// the lexer asks at every token.
    private(set) var isEmpty = true

    init(bytes: [UInt8], from start: Int) {
        self.bytes = bytes
        var position = start
        // A statement needs `direction`, a space and two letters: no later byte starts one.
        let lastStart = bytes.count - Self.keyword.count - 3
        while position <= lastStart {
            guard bytes[position] | 0x20 == UInt8(ascii: "d") else {
                position += 1
                continue
            }
            if let (kind, end) = match(at: position) {
                starts[kind].append(position)
                keywordEnds[kind].append(end)
                isEmpty = false
                position = end
            } else {
                position += 1
            }
        }
    }

    /// The match of `direction`, whitespace and a direction starting at `position`: the kind's index and where the
    /// direction's two letters end.
    private func match(at position: Int) -> (Int, Int)? {
        let word = Self.keyword
        guard MermaidByte.lowercased(bytes[position]) == word[0], position + word.count <= bytes.count else { return nil }
        for (offset, byte) in word.enumerated() where MermaidByte.lowercased(bytes[position + offset]) != byte { return nil }
        let afterWord = position + word.count
        let afterSpace = JavaScriptWhitespace.endOfRun(in: bytes, from: afterWord)
        guard afterSpace > afterWord, afterSpace + 2 <= bytes.count else { return nil }
        let kind: Int? = switch (MermaidByte.uppercased(bytes[afterSpace]), MermaidByte.uppercased(bytes[afterSpace + 1])) {
        case (UInt8(ascii: "T"), UInt8(ascii: "B")): 0
        case (UInt8(ascii: "B"), UInt8(ascii: "T")): 1
        case (UInt8(ascii: "R"), UInt8(ascii: "L")): 2
        case (UInt8(ascii: "L"), UInt8(ascii: "R")): 3
        default: nil
        }
        return kind.map { kind in (kind, afterSpace + 2) }
    }

    /// The direction of the statement that makes the text at `position` its token, and where that token ends (the line
    /// break after the statement's direction, or the text's end), or nil when no statement does.
    mutating func statement(at position: Int) -> (FlowchartDirection, Int)? {
        if lineEnd < position {
            lineEnd = ReferenceRequirementLexer.lineEnd(in: bytes, from: position)
            for kind in 0..<4 {
                var seen = seenCounts[kind]
                while seen < starts[kind].count, starts[kind][seen] <= lineEnd { seen += 1 }
                seenCounts[kind] = seen
            }
        }
        for kind in 0..<4 {
            let last = seenCounts[kind] - 1
            guard last >= 0, starts[kind][last] >= position else { continue }
            return (Self.kinds[kind], ReferenceRequirementLexer.lineBreak(in: bytes, from: keywordEnds[kind][last]))
        }
        return nil
    }
}
