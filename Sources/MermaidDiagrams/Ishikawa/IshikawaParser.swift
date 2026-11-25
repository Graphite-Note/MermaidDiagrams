/**
 * File: IshikawaParser.swift
 * --------------------------
 * Layer: Core
 * Description: Reads an Ishikawa diagram's lines on its text's bytes as the parser Jison builds from Mermaid's grammar
 *              reads them on UTF-16 units, and nests its causes by their indentation as Mermaid's database does.
 *
 * Authors: Bahey Shalash
 * Version: 0.4
 * Date: 24/11/2026
 */

import Foundation

/// Reads an Ishikawa diagram from its keyword as Pele's lexer and parser read it, on the text's bytes, its positions
/// and white space told as JavaScript tells them on UTF-16 units: white space up to a `%%` comment, or up to the last
/// line break in it, is a blank line; a single line break before text is a new line; other white space is indentation,
/// as long as its UTF-16 units (every white space character of JavaScript is one unit); and the rest of a line is text,
/// unless it is the keyword again. A statement is a line of text, indented or not, or a blank line, each ended by a
/// blank line, a line break or the end.
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

    /// A token's bytes, and for an indentation its length in UTF-16 units.
    private struct Token {
        let kind: TokenKind
        let start: Int
        let end: Int
        var unitCount = 0
    }

    /// Reads the diagram whose type keyword, as the reader took it (letters, digits and `-`), ends at the cursor. Pele's
    /// lexer takes `ishikawa-beta`, or failing that `ishikawa`, when no letter, digit or `_` follows it, and the rest of the
    /// line as text (`ishikawa-notes` is `ishikawa` then the effect `-notes`); a keyword it does not take is no Ishikawa
    /// diagram (`ishikawa_x`, `ishikawa2`).
    static func parse(keyword: String, endingAt cursor: MermaidTextCursor, limits: MermaidDiagramLimits) throws(MermaidDiagramReadError) -> IshikawaDiagram {
        let bytes = cursor.bytes[(cursor.position - keyword.utf8.count)...]
        guard keywordLength(in: bytes, at: bytes.startIndex) != nil else {
            let word = bytes.prefix { byte in isWordByte(byte) || byte == hyphen }
            throw .unsupportedDiagramType(keyword: String(decoding: word, as: UTF8.self))
        }
        let tokens = tokenize(bytes)
        func failure(at index: Int) -> MermaidDiagramReadError {
            let token = tokens[index]
            let line = cursor.line + bytes[bytes.startIndex..<min(token.start, bytes.endIndex)].count { byte in byte == newline }
            let tokenUnits = String(decoding: bytes[token.start..<token.end], as: UTF8.self).utf16.prefix(24)
            let excerpt = String(decoding: Array(tokenUnits), as: UTF16.self)
            return .invalidSyntax(line: line, problem: token.kind == .endOfFile ? .expectedNode : .unexpectedText(excerpt))
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
                try builder.add(trimmed(bytes[tokens[textIndex].start..<tokens[textIndex].end]), indentation: token.kind == .text ? 0 : token.unitCount)
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

    /// A line's text without the white space and line breaks at its ends, as Foundation trims it: on the bytes when they
    /// are ASCII, whose white space is a tab, a line feed, a vertical tab, a form feed, a carriage return or a space.
    private static func trimmed(_ text: ArraySlice<UInt8>) -> String {
        guard text.allSatisfy({ byte in byte < 0x80 }) else {
            return String(decoding: text, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        var start = text.startIndex
        var end = text.endIndex
        while start < end, isASCIIWhitespace(text[start]) { start += 1 }
        while end > start, isASCIIWhitespace(text[end - 1]) { end -= 1 }
        return String(decoding: text[start..<end], as: UTF8.self)
    }

    private static func isASCIIWhitespace(_ byte: UInt8) -> Bool {
        byte == 32 || (9...13).contains(byte)
    }

    /// The tokens, ended by the end of the text twice: the parser's end of file and end of input.
    private static func tokenize(_ bytes: ArraySlice<UInt8>) -> [Token] {
        var tokens: [Token] = []
        var start = bytes.startIndex
        while start < bytes.endIndex {
            var afterSpace = start
            var unitCount = 0
            var lastBreak: Int?
            while afterSpace < bytes.endIndex, let length = spaceLength(in: bytes, at: afterSpace) {
                if bytes[afterSpace] == newline { lastBreak = afterSpace }
                afterSpace += length
                unitCount += 1
            }
            let token: Token
            if afterSpace + 1 < bytes.endIndex, bytes[afterSpace] == percent, bytes[afterSpace + 1] == percent {
                var end = afterSpace + 2
                while end < bytes.endIndex, !isCommentEnd(bytes, at: end) { end += 1 }
                token = Token(kind: .blankLine, start: start, end: end)
            } else if afterSpace == start {
                if let keywordLength = keywordLength(in: bytes, at: start) {
                    token = Token(kind: .keyword, start: start, end: start + keywordLength)
                } else {
                    token = Token(kind: .text, start: start, end: bytes[start...].firstIndex(of: newline) ?? bytes.endIndex)
                }
            } else if let lastBreak, lastBreak > start {
                token = Token(kind: .blankLine, start: start, end: lastBreak + 1)
            } else if lastBreak == start {
                token = Token(kind: .newLine, start: start, end: start + 1)
            } else {
                token = Token(kind: .indentation, start: start, end: afterSpace, unitCount: unitCount)
            }
            tokens.append(token)
            start = token.end
        }
        return tokens + [Token(kind: .endOfFile, start: bytes.endIndex, end: bytes.endIndex), Token(kind: .endOfInput, start: bytes.endIndex, end: bytes.endIndex)]
    }

    /// The length in bytes of the white space character at `index`, as JavaScript's `\s` sees it, else nil.
    private static func spaceLength(in bytes: ArraySlice<UInt8>, at index: Int) -> Int? {
        let byte = bytes[index]
        if byte < 0x80 { return byte == 32 || (9...13).contains(byte) ? 1 : nil }
        if byte == 0xC2 { return index + 1 < bytes.endIndex && bytes[index + 1] == 0xA0 ? 2 : nil }
        guard byte == 0xE1 || byte == 0xE2 || byte == 0xE3 || byte == 0xEF, index + 2 < bytes.endIndex else { return nil }
        let scalar = UInt32(byte & 0x0F) << 12 | UInt32(bytes[index + 1] & 0x3F) << 6 | UInt32(bytes[index + 2] & 0x3F)
        return isNonASCIISpace(scalar) ? 3 : nil
    }

    /// The white space of JavaScript past ASCII and past U+00A0, each three bytes in UTF-8.
    private static func isNonASCIISpace(_ scalar: UInt32) -> Bool {
        scalar == 0x1680 || (0x2000...0x200A).contains(scalar) || scalar == 0x2028 || scalar == 0x2029 || scalar == 0x202F || scalar == 0x205F
            || scalar == 0x3000 || scalar == 0xFEFF
    }

    /// Whether a comment ends at `index`: a line feed, a carriage return, a line or a paragraph separator.
    private static func isCommentEnd(_ bytes: ArraySlice<UInt8>, at index: Int) -> Bool {
        let byte = bytes[index]
        if byte == newline || byte == carriageReturn { return true }
        return byte == 0xE2 && index + 2 < bytes.endIndex && bytes[index + 1] == 0x80 && (bytes[index + 2] == 0xA8 || bytes[index + 2] == 0xA9)
    }

    private static let keywordBytes = Array("ishikawa-beta".utf8)

    /// Whether a token of `kind` ends an entry's line: a blank line, a line break or the end of the file.
    private static func isStop(_ kind: TokenKind) -> Bool {
        kind == .blankLine || kind == .newLine || kind == .endOfFile
    }

    /// `ishikawa-beta`, or failing that `ishikawa`, in any case and ending at a word's end: its length, else nil.
    private static func keywordLength(in bytes: ArraySlice<UInt8>, at start: Int) -> Int? {
        let word = keywordBytes
        var matched = 0
        while matched < word.count, start + matched < bytes.endIndex, MermaidByte.lowercased(bytes[start + matched]) == word[matched] { matched += 1 }
        let endsWord = { (end: Int) in end >= bytes.endIndex || !isWordByte(bytes[end]) }
        if matched == word.count, endsWord(start + matched) { return matched }
        return matched >= 8 && endsWord(start + 8) ? 8 : nil
    }

    private static func isWordByte(_ byte: UInt8) -> Bool {
        (48...57).contains(byte) || (65...90).contains(byte) || (97...122).contains(byte) || byte == 95
    }

    private static let newline: UInt8 = 10
    private static let carriageReturn: UInt8 = 13
    private static let percent: UInt8 = 37
    private static let hyphen: UInt8 = 45
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
