/**
 * File: ReferenceUseCaseLexerOperators.swift
 * ------------------------------------------
 * Layer: Tests
 * Description: The tokens of a use case diagram that start with a quotation mark, a dash, a point or an angle bracket:
 *              strings, relationship operators, numbers and stereotypes, as Pele's lexer.ts reads them.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 25/11/2026
 */

@testable import MermaidDiagrams

extension ReferenceUseCaseLexer {
    /// A Markdown string (`"`…`"`, which may run over lines, and to the end of the text when unclosed), or a plain
    /// string closed on its line; an unclosed plain string is an error at its quotation mark.
    mutating func readString(_ quote: UInt16) throws(Failure) -> (ReferenceUseCaseTokenKind, Int) {
        if quote == 0x22, text[position + 1] == UInt16(ascii: "`") {
            var close = position + 2
            while close + 1 < text.count, !(text.units[close] == UInt16(ascii: "`") && text.units[close + 1] == 0x22) { close += 1 }
            return close + 1 < text.count ? (.markdownString, close + 2) : (.unclosedMarkdownString, text.count)
        }
        var index = position + 1
        while let unit = text[index], !ReferenceUseCaseCharacters.isLineBreak(unit) {
            if unit == quote { return (.plainString, index + 1) }
            index += 1
        }
        throw Failure(offset: position)
    }

    /// `-`, or a run of dashes: `--|>`, `-->` and longer, `--o`, `--x`, or a line without marks.
    func readDashes() -> (ReferenceUseCaseTokenKind, Int) {
        guard text[position + 1] == 0x2D else { return (.dash, position + 1) }
        var end = position + 1
        while text[end] == 0x2D { end += 1 }
        let next = text[end]
        let isTwo = end - position == 2
        if isTwo, next == UInt16(ascii: "|"), text[end + 1] == UInt16(ascii: ">") { return (.generalization, end + 2) }
        if next == UInt16(ascii: ">") { return (.forwardSolid, end + 1) }
        if isTwo, next == UInt16(ascii: "o") || next == UInt16(ascii: "x") { return (next == UInt16(ascii: "o") ? .forwardCircle : .forwardCross, end + 1) }
        return (.markerlessSolid, end)
    }

    /// `..>`, a number that starts with its point (`.5`), or a point.
    func readDot() -> (ReferenceUseCaseTokenKind, Int) {
        let next = text[position + 1]
        if next == UInt16(ascii: "."), text[position + 2] == UInt16(ascii: ">") { return (.dependencyArrow, position + 3) }
        guard ReferenceUseCaseCharacters.isDigit(next) else { return (.dot, position + 1) }
        var end = position + 1
        while ReferenceUseCaseCharacters.isDigit(text[end]) { end += 1 }
        while ReferenceUseCaseCharacters.isLetter(text[end]) { end += 1 }
        return (.number, end)
    }

    /// `<<` and the stereotype after it to its `>>` on the same line (or to the line's end when unclosed), `<--` and
    /// longer, or a `<` of a label. Nil when the text ends right after `<<`.
    mutating func readAngle() throws(Failure) -> (ReferenceUseCaseTokenKind, Int)? {
        let next = position + 1
        if text[next] == UInt16(ascii: "<") {
            tokens.append(.stereotypeStart, from: position, to: position + 2)
            isAtLineStart = false
            position += 2
            guard position < text.count else { return nil }
            return try readStereotype()
        }
        guard text[next] == 0x2D, text[next + 1] == 0x2D else { return (.labelPunctuation, next) }
        var end = next + 2
        while text[end] == 0x2D { end += 1 }
        return (.backwardSolid, end)
    }

    private mutating func readStereotype() throws(Failure) -> (ReferenceUseCaseTokenKind, Int) {
        let closing = UInt16(ascii: ">")
        if text[position] == closing, text[position + 1] == closing { return (.stereotypeEnd, position + 2) }
        var close = position
        var isFound = false
        while let unit = text[close], !ReferenceUseCaseCharacters.isLineBreak(unit) {
            if unit == closing, text[close + 1] == closing {
                isFound = true
                break
            }
            close += 1
        }
        if isFound, !ReferenceUseCaseCharacters.trimmed(text.text(from: position, to: close)).isEmpty {
            tokens.append(.stereotypeText, from: position, to: close)
            position = close
            return (.stereotypeEnd, close + 2)
        }
        close = text.lineEnd(from: close)
        guard close > position else { throw Failure(offset: position) }
        return (.unclosedStereotypeText, close)
    }
}
