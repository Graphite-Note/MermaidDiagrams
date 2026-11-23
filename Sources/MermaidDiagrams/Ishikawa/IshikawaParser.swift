/**
 * File: IshikawaParser.swift
 * --------------------------
 * Layer: Core
 * Description: Reads an Ishikawa diagram's lines as the parser Jison builds from Mermaid's grammar reads them, and nests
 *              its causes by their indentation as Mermaid's database does.
 *
 * Authors: Bahey Shalash
 * Version: 0.3
 * Date: 23/11/2026
 */

import Foundation

/// Reads an Ishikawa diagram from its keyword as Pele's lexer and parser read it, on the text's UTF-16 units as
/// JavaScript does: white space up to a `%%` comment, or up to the last line break in it, is a blank line; a single line
/// break before text is a new line; other white space is indentation; and the rest of a line is text, unless it is the
/// keyword again. A statement is a line of text, indented or not, or a blank line, each ended by a blank line, a line
/// break or the end.
enum IshikawaParser {
    private enum TokenKind: Equatable {
        case blankLine
        case newLine
        case keyword
        case indentation
        case text
        /// The parser's end of file, then its end of input.
        case endOfFile
        case endOfInput
    }

    private struct Token {
        let kind: TokenKind
        let start: Int
        let end: Int
    }

    /// Reads the diagram whose type keyword, as the reader took it (letters, digits and `-`), ends at the cursor. Pele's
    /// lexer takes `ishikawa-beta`, or failing that `ishikawa`, when no letter, digit or `_` follows it, and the rest of the
    /// line as text (`ishikawa-notes` is `ishikawa` then the effect `-notes`); a keyword it does not take is no Ishikawa
    /// diagram (`ishikawa_x`, `ishikawa2`).
    static func parse(keyword: String, endingAt cursor: MermaidTextCursor, limits: MermaidDiagramLimits) throws(MermaidDiagramReadError) -> IshikawaDiagram {
        let units = Array(cursor.text(from: cursor.position - keyword.utf8.count, to: cursor.bytes.count).utf16)
        guard keywordLength(in: units, at: 0) != nil else {
            let word = units.prefix { unit in isWordUnit(unit) || unit == hyphen }
            throw .unsupportedDiagramType(keyword: String(decoding: word, as: UTF16.self))
        }
        let tokens = tokenize(units)
        func line(at index: Int) -> Int {
            cursor.line + units[..<min(tokens[index].start, units.count)].count { unit in unit == newline }
        }
        func failure(at index: Int) -> MermaidDiagramReadError {
            let token = tokens[index]
            let excerpt = String(decoding: units[token.start..<min(token.end, token.start + 24)], as: UTF16.self)
            return .invalidSyntax(line: line(at: index), problem: token.kind == .endOfFile ? .expectedNode : .unexpectedText(excerpt))
        }
        func isStop(_ index: Int) -> Bool { Self.isStop(tokens[index].kind) }
        var builder = IshikawaTreeBuilder(limits: limits)
        // The first token is the keyword, as the text starts with it.
        var index = tokens[1].kind == .newLine ? 2 : 1
        while true {
            let token = tokens[index]
            if token.kind == .text || (token.kind == .indentation && tokens[index + 1].kind == .text) {
                let textIndex = token.kind == .text ? index : index + 1
                index = textIndex + 1
                guard isStop(index) else { throw failure(at: index) }
                let text = UnicodeScalarText.string(utf16: units[tokens[textIndex].start..<tokens[textIndex].end])
                try builder.add(text.trimmingCharacters(in: .whitespacesAndNewlines), indentation: token.kind == .text ? 0 : token.end - token.start)
            } else if token.kind == .blankLine || token.kind == .indentation {
                index += 1
                guard isStop(index) else { throw failure(at: index) }
            } else {
                throw failure(at: index)
            }
            index += 1
            while tokens[index].kind == .newLine || tokens[index].kind == .endOfFile { index += 1 }
            if tokens[index].kind == .endOfInput { break }
        }
        return builder.diagram
    }

    /// The tokens, ended by the end of the text twice: the parser's end of file and end of input.
    private static func tokenize(_ units: [UInt16]) -> [Token] {
        var tokens: [Token] = []
        var start = 0
        while start < units.count {
            var afterSpace = start
            var lastBreak: Int?
            while afterSpace < units.count, isSpace(units[afterSpace]) {
                if units[afterSpace] == newline { lastBreak = afterSpace }
                afterSpace += 1
            }
            let token: Token
            if afterSpace + 1 < units.count, units[afterSpace] == percent, units[afterSpace + 1] == percent {
                var end = afterSpace + 2
                while end < units.count, ![newline, carriageReturn, 0x2028, 0x2029].contains(units[end]) { end += 1 }
                token = Token(kind: .blankLine, start: start, end: end)
            } else if afterSpace == start {
                if let keywordLength = keywordLength(in: units, at: start) {
                    token = Token(kind: .keyword, start: start, end: start + keywordLength)
                } else {
                    token = Token(kind: .text, start: start, end: units[start...].firstIndex(of: newline) ?? units.count)
                }
            } else if let lastBreak, lastBreak > start {
                token = Token(kind: .blankLine, start: start, end: lastBreak + 1)
            } else if lastBreak == start {
                token = Token(kind: .newLine, start: start, end: start + 1)
            } else {
                token = Token(kind: .indentation, start: start, end: afterSpace)
            }
            tokens.append(token)
            start = token.end
        }
        return tokens + [Token(kind: .endOfFile, start: units.count, end: units.count), Token(kind: .endOfInput, start: units.count, end: units.count)]
    }

    private static let keywordUnits = Array("ishikawa-beta".utf16)

    /// Whether a token of `kind` ends an entry's line: a blank line, a line break or the end of the file.
    private static func isStop(_ kind: TokenKind) -> Bool {
        kind == .blankLine || kind == .newLine || kind == .endOfFile
    }

    /// `ishikawa-beta`, or failing that `ishikawa`, in any case and ending at a word's end: its length, else nil.
    private static func keywordLength(in units: [UInt16], at start: Int) -> Int? {
        let word = keywordUnits
        var matched = 0
        while matched < word.count, start + matched < units.count, lowercased(units[start + matched]) == word[matched] { matched += 1 }
        let endsWord = { (end: Int) in end >= units.count || !isWordUnit(units[end]) }
        if matched == word.count, endsWord(start + matched) { return matched }
        return matched >= 8 && endsWord(start + 8) ? 8 : nil
    }

    private static func lowercased(_ unit: UInt16) -> UInt16 {
        (65...90).contains(unit) ? unit + 32 : unit
    }

    private static func isWordUnit(_ unit: UInt16) -> Bool {
        (48...57).contains(unit) || (65...90).contains(unit) || (97...122).contains(unit) || unit == 95
    }

    /// White space as JavaScript's `\s` sees it.
    private static func isSpace(_ unit: UInt16) -> Bool {
        unit == 32 || (9...13).contains(unit) || unit == 0xA0 || unit == 0x1680 || (0x2000...0x200A).contains(unit) || unit == 0x2028
            || unit == 0x2029 || unit == 0x202F || unit == 0x205F || unit == 0x3000 || unit == 0xFEFF
    }

    private static let newline: UInt16 = 10
    private static let carriageReturn: UInt16 = 13
    private static let percent: UInt16 = 37
    private static let hyphen: UInt16 = 45
}

/// Nests the lines as Mermaid's Ishikawa database does: the first is the effect; each later one is a cause at its
/// indentation less the first cause's, plus one, at least one, under the last line before it nested less deep.
struct IshikawaTreeBuilder {
    private(set) var diagram = IshikawaDiagram()
    private let limits: MermaidDiagramLimits
    private var firstCauseIndentation: Int?
    /// The effect and the open causes, by strictly increasing level, the effect at level 0.
    private var openNodes: [(index: Int, level: Int)] = []

    init(limits: MermaidDiagramLimits) {
        self.limits = limits
    }

    mutating func add(_ text: String, indentation: Int) throws(MermaidDiagramReadError) {
        guard diagram.nodes.count < limits.maximumNodeCount else { throw .tooManyNodes(limit: limits.maximumNodeCount) }
        let index = diagram.nodes.count
        guard !diagram.nodes.isEmpty else {
            diagram.nodes.append(IshikawaNode(text: text, parentIndex: nil))
            openNodes = [(index, 0)]
            return
        }
        let base = firstCauseIndentation ?? indentation
        firstCauseIndentation = base
        let level = max(indentation - base + 1, 1)
        while openNodes.count > 1, let last = openNodes.last, last.level >= level { openNodes.removeLast() }
        let parentIndex = openNodes[openNodes.count - 1].index
        diagram.nodes.append(IshikawaNode(text: text, parentIndex: parentIndex))
        diagram.nodes[parentIndex].childIndices.append(index)
        openNodes.append((index, level))
    }
}
