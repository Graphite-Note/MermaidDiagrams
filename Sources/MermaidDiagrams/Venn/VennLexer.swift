/**
 * File: VennLexer.swift
 * ---------------------
 * Layer: Core
 * Description: Reads a Venn diagram's tokens one at a time, as Mermaid's Jison lexer for Venn diagrams does (Pele's
 *              lexer.ts): keywords in any case, bracket labels, numbers, colors, and the indented `text` that continues
 *              a set.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 19/11/2026
 */

/// The kinds of a Venn diagram's tokens, in the order of Mermaid's grammar (`venn.jison`).
enum VennTokenKind: Equatable {
    case end
    /// Text no rule reads.
    case error
    case endOfText
    case newline
    /// A second `venn-beta`, which no statement takes.
    case venn
    case title
    case set
    case union
    case text
    /// `text` indented under a set or a union: the indentation stands for the set.
    case indentedText
    case style
    case bracketLabel
    case number
    case hexadecimalColor
    case rgbColor
    case rgbaColor
    case identifier
    case string
    case comma
    case colon

    /// A style's value may be made of these and identifiers.
    var isStyleValuePiece: Bool {
        self == .identifier || self == .number || self == .hexadecimalColor || self == .rgbColor || self == .rgbaColor
    }
}

/// A token: its kind, its text, and where it starts in the diagram's bytes.
struct VennToken {
    let kind: VennTokenKind
    let text: String
    let start: Int
}

/// Reads tokens one at a time, as Mermaid's lexer does: every rule ignores case, the first rule that matches wins, and a
/// keyword ends at a word boundary. An indented `text` is a token of its own only while the parser says the line before
/// it was a set or a union (`indentMode`), and a line that starts without indentation ends that.
struct VennLexer {
    private let bytes: [UInt8]
    private var position: Int
    private var isAtLineStart = false
    private var hasEnded = false

    /// A lexer from `position`, just after the `venn-beta` keyword.
    init(bytes: [UInt8], position: Int) {
        self.bytes = bytes
        self.position = position
    }

    private func byte(_ index: Int) -> UInt8? {
        index < bytes.count ? bytes[index] : nil
    }

    mutating func next(indentMode: inout Bool) -> VennToken {
        while true {
            let start = position
            guard let current = byte(start) else {
                if hasEnded { return VennToken(kind: .end, text: "", start: start) }
                hasEnded = true
                return VennToken(kind: .endOfText, text: "", start: start)
            }
            if current == PlaneMapByte.percent, byte(start + 1) == PlaneMapByte.percent, byte(start + 2) != PlaneMapByte.openingBrace {
                position = lineEnd(from: start + 2)
                continue
            }
            if isAtLineStart {
                if skipsBareTitle(at: start) { continue }
                if PlaneMapByte.isBlank(current) {
                    if let indented = readIndentation(at: start, indentMode: indentMode) { return indented }
                    continue
                }
                if !PlaneMapByte.isLineBreak(current) {
                    indentMode = false
                    isAtLineStart = false
                }
            }
            if PlaneMapByte.isLineBreak(current) {
                isAtLineStart = true
                return token(.newline, from: start, to: endOfRun(from: start, where: PlaneMapByte.isLineBreak))
            }
            if current == PlaneMapByte.percent, byte(start + 1) == PlaneMapByte.percent {
                position = lineEnd(from: start)
            } else if PlaneMapByte.isBlank(current) {
                position = endOfRun(from: start, where: PlaneMapByte.isBlank)
            } else {
                return readToken(startingWith: current, at: start)
            }
        }
    }

    /// The indentation at the start of a line, skipped; an indented `text` while a set or a union is open is a token, the
    /// indentation standing for the word.
    private mutating func readIndentation(at start: Int, indentMode: Bool) -> VennToken? {
        let end = endOfRun(from: start, where: PlaneMapByte.isBlank)
        position = end
        guard indentMode, isKeyword("text", at: end) else { return nil }
        position = end + 4
        isAtLineStart = false
        return VennToken(kind: .indentedText, text: text(from: start, to: end), start: start)
    }

    /// The end of the run of bytes from `start` that `isInRun` takes.
    private func endOfRun(from start: Int, where isInRun: (UInt8) -> Bool) -> Int {
        var end = start
        while let next = byte(end), isInRun(next) { end += 1 }
        return end
    }

    /// A bare `title` at the start of a line, with nothing after it, is skipped with the line breaks after it, like a
    /// comment, so that it does not end indented text.
    private mutating func skipsBareTitle(at start: Int) -> Bool {
        guard matchesWord("title", at: start), followsLineFeed(start) else { return false }
        let end = lineEnd(from: start + 5)
        guard text(from: start + 5, to: end).allSatisfy(\.isWhitespace) else { return false }
        var next = end
        while let following = byte(next), PlaneMapByte.isLineBreak(following) { next += 1 }
        position = next
        return true
    }

    private mutating func readToken(startingWith current: UInt8, at start: Int) -> VennToken {
        if PlaneMapByte.isLetter(current) || current == PlaneMapByte.underscore { return readWord(at: start) }
        switch current {
        case PlaneMapByte.openingBracket: return readBracketLabel(at: start)
        case PlaneMapByte.hash:
            var end = start + 1
            while end < start + 9, let next = byte(end), PlaneMapByte.isHexadecimalDigit(next) { end += 1 }
            return end >= start + 4 ? token(.hexadecimalColor, from: start, to: end) : error(at: start)
        case PlaneMapByte.quotationMark:
            guard let quote = index(of: PlaneMapByte.quotationMark, from: start + 1) else { return error(at: start) }
            return token(.string, from: start, to: quote + 1)
        case PlaneMapByte.comma: return token(.comma, from: start, to: start + 1)
        case PlaneMapByte.colon: return token(.colon, from: start, to: start + 1)
        default:
            if PlaneMapByte.isDigit(current) || current == PlaneMapByte.period || current == PlaneMapByte.plus || current == PlaneMapByte.hyphen {
                return readNumber(at: start)
            }
            return error(at: start)
        }
    }

    /// A title, a keyword, an `rgb(…)` or `rgba(…)` color, or an identifier of word characters and hyphens.
    private mutating func readWord(at start: Int) -> VennToken {
        if matchesWord("title", at: start), let separator = byte(start + 5), PlaneMapByte.isSpace(separator), !PlaneMapByte.isLineBreak(separator) {
            var end = start + 6
            while let next = byte(end), next != PlaneMapByte.hash, !PlaneMapByte.isLineBreak(next), next != PlaneMapByte.semicolon { end += 1 }
            if end > start + 6 { return token(.title, from: start, to: end) }
        }
        for (word, kind) in Self.keywords where isKeyword(word, at: start) && byte(start + word.utf8.count) != PlaneMapByte.hyphen {
            return token(kind, from: start, to: start + word.utf8.count)
        }
        if matchesWord("rgb", at: start) {
            let hasAlpha = byte(start + 3).map(PlaneMapByte.lowercased) == UInt8(ascii: "a")
            let opening = start + (hasAlpha ? 4 : 3)
            if byte(opening) == PlaneMapByte.openingParenthesis, let end = colorEnd(opening: opening, partCount: hasAlpha ? 4 : 3) {
                return token(hasAlpha ? .rgbaColor : .rgbColor, from: start, to: end)
            }
        }
        var end = start + 1
        while let next = byte(end), PlaneMapByte.isWord(next) || next == PlaneMapByte.hyphen { end += 1 }
        return token(.identifier, from: start, to: end)
    }

    /// `["text"]` with the text as written, or `[text]` without the spaces at its ends; a quotation mark in a plain label,
    /// or a quoted one not closed by `"]`, is an error.
    private mutating func readBracketLabel(at start: Int) -> VennToken {
        if byte(start + 1) == PlaneMapByte.quotationMark {
            guard let quote = index(of: PlaneMapByte.quotationMark, from: start + 2), byte(quote + 1) == PlaneMapByte.closingBracket else { return error(at: start) }
            position = quote + 2
            return VennToken(kind: .bracketLabel, text: text(from: start + 2, to: quote), start: start)
        }
        var end = start + 1
        while let next = byte(end), next != PlaneMapByte.closingBracket, next != PlaneMapByte.quotationMark { end += 1 }
        guard end > start + 1, byte(end) == PlaneMapByte.closingBracket else { return error(at: start) }
        position = end + 1
        return VennToken(kind: .bracketLabel, text: text(from: start + 1, to: end).trimmingCharacters(in: .whitespacesAndNewlines), start: start)
    }

    /// A sign, then digits with a fraction (`1.5`), digits, or a fraction alone (`.5`).
    private mutating func readNumber(at start: Int) -> VennToken {
        var end = start
        if bytes[end] == PlaneMapByte.plus || bytes[end] == PlaneMapByte.hyphen { end += 1 }
        let digitsStart = end
        while let next = byte(end), PlaneMapByte.isDigit(next) { end += 1 }
        let hasFraction = byte(end) == PlaneMapByte.period && byte(end + 1).map(PlaneMapByte.isDigit) == true
        if end == digitsStart && !hasFraction { return error(at: start) }
        if hasFraction {
            end += 2
            while let next = byte(end), PlaneMapByte.isDigit(next) { end += 1 }
        }
        return token(.number, from: start, to: end)
    }

    /// The end of `rgb(1, 2, 3)` or `rgba(1, 2, 3, 0.5)` whose parenthesis opens at `opening`, or nil.
    private func colorEnd(opening: Int, partCount: Int) -> Int? {
        var index = opening + 1
        for part in 0..<partCount {
            while let next = byte(index), PlaneMapByte.isSpace(next) { index += 1 }
            let partStart = index
            while let next = byte(index), PlaneMapByte.isDigit(next) || next == PlaneMapByte.period { index += 1 }
            guard index > partStart else { return nil }
            while let next = byte(index), PlaneMapByte.isSpace(next) { index += 1 }
            guard byte(index) == (part == partCount - 1 ? PlaneMapByte.closingParenthesis : PlaneMapByte.comma) else { return nil }
            index += 1
        }
        return index
    }

    private mutating func token(_ kind: VennTokenKind, from start: Int, to end: Int) -> VennToken {
        position = end
        return VennToken(kind: kind, text: text(from: start, to: end), start: start)
    }

    /// No rule reads the text at `start`: the lexer stays there.
    private func error(at start: Int) -> VennToken {
        VennToken(kind: .error, text: "", start: start)
    }

    /// Whether `word` (lowercase) is at `start`, ASCII letters compared without regard to case.
    private func matchesWord(_ word: String, at start: Int) -> Bool {
        for (offset, expected) in word.utf8.enumerated() {
            guard let actual = byte(start + offset), PlaneMapByte.lowercased(actual) == expected else { return false }
        }
        return true
    }

    private func isKeyword(_ word: String, at start: Int) -> Bool {
        matchesWord(word, at: start) && byte(start + word.utf8.count).map(PlaneMapByte.isWord) != true
    }

    /// Whether only spaces and tabs lie between the last line feed and `start`.
    private func followsLineFeed(_ start: Int) -> Bool {
        var index = start - 1
        while index >= 0, PlaneMapByte.isBlank(bytes[index]) { index -= 1 }
        return index >= 0 && bytes[index] == PlaneMapByte.lineFeed
    }

    private func lineEnd(from start: Int) -> Int {
        index(of: PlaneMapByte.lineFeed, from: start) ?? bytes.count
    }

    private func index(of target: UInt8, from start: Int) -> Int? {
        guard start < bytes.count else { return nil }
        return bytes[start...].firstIndex(of: target)
    }

    private func text(from start: Int, to end: Int) -> String {
        String(decoding: bytes[min(start, end)..<end], as: UTF8.self)
    }

    private static let keywords: [(String, VennTokenKind)] = [("venn-beta", .venn), ("set", .set), ("union", .union), ("text", .text), ("style", .style)]
}
