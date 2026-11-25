/**
 * File: RequirementDirectionStatements.swift
 * ------------------------------------------
 * Layer: Core
 * Description: The direction statements of a requirement diagram's text, found in one pass over its borrowed bytes as
 *              Pele's lexer finds them, and the one that makes a position's text its token.
 *
 * Authors: Bahey Shalash
 * Version: 0.2
 * Date: 25/11/2026
 */

/// The direction statements of a requirement diagram's text, as Pele's lexer finds them: every match of
/// `/direction\s+(?:(TB)|(BT)|(RL)|LR)/gi` in one pass (the whitespace JavaScript's, line breaks included), by kind. Mermaid's
/// rules for them are tried before the others and match from anywhere on a line, so at a position the last such statement
/// of each kind that starts on the position's line, at or after it, makes the rest of that line and of the line it ends on
/// one token, the kinds tried in Mermaid's order. A text without one keeps no list.
struct RequirementDirectionStatements {
    /// The kinds in the order Mermaid's rules try them.
    static let kinds: [FlowchartDirection] = [.topToBottom, .bottomToTop, .rightToLeft, .leftToRight]

    /// A statement found: its kind's index, where it starts and where its direction's two letters end.
    private struct Statement {
        var kind: Int
        var start: Int
        var keywordEnd: Int
    }

    /// The statements in the order they start.
    private var statements: [Statement] = []
    /// How many statements start at or before `lineEnd`, and, by kind, the last of them, or -1.
    private var seenCount = 0
    private var lastSeenByKind: SIMD4<Int32> = SIMD4(repeating: -1)
    /// The end of the line the last position asked about is on.
    private var lineEnd = -1
    private let bytes: UnsafeBufferPointer<UInt8>

    /// Whether the text holds any direction statement: when it holds none, no position needs asking about.
    var isEmpty: Bool { statements.isEmpty }

    init(bytes: UnsafeBufferPointer<UInt8>, from start: Int) {
        self.bytes = bytes
        var position = start
        // A statement needs `direction`, a space and two letters: no later byte starts one.
        let lastStart = bytes.count - Self.keywordLength - 3
        while position <= lastStart {
            // Sixteen bytes without a `d` in either case are passed at once.
            if position + 16 <= bytes.count, let base = bytes.baseAddress,
               !any(UnsafeRawPointer(base + position).loadUnaligned(as: SIMD16<UInt8>.self) | Self.caseBit .== Self.letterD) {
                position += 16
                continue
            }
            guard bytes[position] | 0x20 == UInt8(ascii: "d") else {
                position += 1
                continue
            }
            if let (kind, end) = match(at: position) {
                statements.append(Statement(kind: kind, start: position, keywordEnd: end))
                position = end
            } else {
                position += 1
            }
        }
    }

    private static let keywordLength = "direction".utf8.count
    private static let caseBit = SIMD16<UInt8>(repeating: 0x20)
    private static let letterD = SIMD16<UInt8>(repeating: UInt8(ascii: "d"))

    /// The match of `direction`, whitespace and a direction starting at `position`: the kind's index and where the
    /// direction's two letters end.
    private func match(at position: Int) -> (Int, Int)? {
        guard RequirementLexer.hasLowercased("direction", in: bytes, at: position) else { return nil }
        let afterWord = position + Self.keywordLength
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
            lineEnd = RequirementLexer.lineEnd(in: bytes, from: position)
            while seenCount < statements.count, statements[seenCount].start <= lineEnd {
                lastSeenByKind[statements[seenCount].kind] = Int32(seenCount)
                seenCount += 1
            }
        }
        for kind in 0..<4 {
            let last = Int(lastSeenByKind[kind])
            guard last >= 0, statements[last].start >= position else { continue }
            return (Self.kinds[kind], RequirementLexer.lineBreak(in: bytes, from: statements[last].keywordEnd))
        }
        return nil
    }
}

extension MermaidByte {
    static func uppercased(_ byte: UInt8) -> UInt8 {
        byte >= UInt8(ascii: "a") && byte <= UInt8(ascii: "z") ? byte - 32 : byte
    }
}
