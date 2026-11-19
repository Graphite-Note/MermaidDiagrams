/**
 * File: RequirementDirectionStatements.swift
 * ------------------------------------------
 * Layer: Core
 * Description: Where a requirement diagram's direction statements are, found in one pass, and which of them decides the
 *              token a line starts, as Mermaid's lexer rules `.*direction\s+TB[^\n]*` and the others decide it.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 19/11/2026
 */

/// The direction statements of a requirement diagram's text, as Pele's lexer finds them: every match of
/// `/direction\s+(?:(TB)|(BT)|(RL)|LR)/gi` in one pass (the whitespace JavaScript's, line breaks included), by kind. Mermaid's
/// rules for them are tried before the others and match from anywhere on a line, so at a position the last such statement
/// that starts on the position's line, at or after it, makes the rest of that line and of the line it ends on one token.
struct RequirementDirectionStatements {
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

    /// Whether the text holds any direction statement: when it holds none, no position needs asking about.
    var isEmpty: Bool { starts.allSatisfy(\.isEmpty) }

    init(bytes: [UInt8], from start: Int) {
        self.bytes = bytes
        var position = start
        while position < bytes.count {
            if let (kind, end) = match(at: position) {
                starts[kind].append(position)
                keywordEnds[kind].append(end)
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
        let letters = [MermaidByte.uppercased(bytes[afterSpace]), MermaidByte.uppercased(bytes[afterSpace + 1])]
        let kind: Int? = switch letters {
        case Array("TB".utf8): 0
        case Array("BT".utf8): 1
        case Array("RL".utf8): 2
        case Array("LR".utf8): 3
        default: nil
        }
        return kind.map { kind in (kind, afterSpace + 2) }
    }

    /// The direction of the statement that makes the text at `position` its token, and where that token ends (the line
    /// break after the statement's direction, or the text's end), or nil when no statement does.
    mutating func statement(at position: Int) -> (FlowchartDirection, Int)? {
        if lineEnd < position {
            lineEnd = RequirementLexer.lineEnd(in: bytes, from: position)
            for kind in 0..<4 {
                var seen = seenCounts[kind]
                while seen < starts[kind].count, starts[kind][seen] <= lineEnd { seen += 1 }
                seenCounts[kind] = seen
            }
        }
        for kind in 0..<4 {
            let last = seenCounts[kind] - 1
            guard last >= 0, starts[kind][last] >= position else { continue }
            return (Self.kinds[kind], RequirementLexer.lineBreak(in: bytes, from: keywordEnds[kind][last]))
        }
        return nil
    }
}

extension MermaidByte {
    static func uppercased(_ byte: UInt8) -> UInt8 {
        byte >= UInt8(ascii: "a") && byte <= UInt8(ascii: "z") ? byte - 32 : byte
    }
}
