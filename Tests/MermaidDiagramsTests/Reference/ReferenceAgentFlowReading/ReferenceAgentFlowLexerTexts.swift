/**
 * File: ReferenceAgentFlowLexerTexts.swift
 * ----------------------------------------
 * Layer: Tests
 * Description: 0.7.0's agent flow reader on UTF-16 code units (AgentFlowLexerTexts.swift), kept unchanged but for its
 *              names as the reference the reader on bytes is compared with (AgentFlowReadingEquivalenceTests).
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 26/11/2026
 */

@testable import MermaidDiagrams

extension ReferenceAgentFlowLexer {
    private typealias Unit = AgentFlowCharacter

    /// Inside a node's brackets: a quotation mark, a nested opening bracket, a closing bracket, a comment, or text up
    /// to any of them. Jison drops the lone `%` from Mermaid's text pattern, so only a comment may start with one.
    mutating func readText(_ character: Int) -> Bool {
        let next = self.character(at: position + 1)
        switch character {
        case Unit.quotationMark: readQuotationMark()
        case Unit.openingParenthesis, Unit.openingBracket, Unit.openingBrace: _ = readOpener(character)
        case Unit.closingBracket:
            pop()
            if next == Unit.closingParenthesis { emitFlat(.stadiumEnd, to: position + 2) }
            else if next == Unit.closingBracket { emitFlat(.subroutineEnd, to: position + 2) }
            else { emitFlat(.squareEnd, to: position + 1) }
        case Unit.closingParenthesis:
            pop()
            if next == Unit.closingBracket { emitFlat(.cylinderEnd, to: position + 2) }
            else if next == Unit.closingParenthesis, self.character(at: position + 2) == Unit.closingParenthesis { emitFlat(.doubleCircleEnd, to: position + 3) }
            else { emitFlat(.parenthesisEnd, to: position + 1) }
        case Unit.verticalLine:
            pop()
            emitFlat(.pipe, to: position + 1)
        case Unit.closingBrace:
            pop()
            emitFlat(.diamondStop, to: position + 1)
        case Unit.percentSign:
            let end = commentEnd(from: position)
            guard end >= 0 else { return false }
            advance(to: end)
        default:
            var end = position + 1
            while end < count, !Self.textStops.contains(Int(units[end])) { end += 1 }
            emit(.text, to: end)
        }
        return true
    }

    /// Inside `(-` … `-)`: the end is `-)`, `/)` or `))`.
    mutating func readEllipseText(_ character: Int) -> Bool {
        let next = self.character(at: position + 1)
        if character == Unit.quotationMark {
            readQuotationMark()
        } else if character == Unit.percentSign, commentEnd(from: position) >= 0 {
            advance(to: commentEnd(from: position))
        } else if character == Unit.hyphen || character == Unit.solidus || character == Unit.closingParenthesis, next == Unit.closingParenthesis {
            pop()
            emitFlat(.ellipseEnd, to: position + 2)
        } else if character == Unit.openingParenthesis || character == Unit.openingBracket || character == Unit.openingBrace {
            _ = readOpener(character)
        } else if character == Unit.closingParenthesis || character == Unit.closingBracket || character == Unit.closingBrace {
            return false
        } else {
            emitCharacters(.text, to: ellipseTextEnd())
        }
        return true
    }

    private func ellipseTextEnd() -> Int {
        var end = position + 1
        while end < count {
            let unit = Int(units[end])
            if Self.ellipseStops.contains(unit) { break }
            if unit == Unit.hyphen || unit == Unit.solidus, character(at: end + 1) == Unit.closingParenthesis { break }
            if unit == Unit.percentSign, character(at: end + 1) == Unit.percentSign, character(at: end + 2) != Unit.openingBrace { break }
            end += 1
        }
        return end
    }

    /// Inside `[/` or `[\`: the ends `\]`, `/]`, `]]`, `)]`, `(]`, `?]` and `=]`, single slashes as text, and text.
    mutating func readTrapezoidText(_ character: Int) -> Bool {
        let next = self.character(at: position + 1)
        switch character {
        case Unit.quotationMark: readQuotationMark()
        case Unit.openingParenthesis:
            let opensMore = next == Unit.hyphen || next == Unit.openingBracket
                || (next == Unit.openingParenthesis && self.character(at: position + 2) == Unit.openingParenthesis)
            if !opensMore, next == Unit.closingBracket { closeTrapezoid(.trapezoidEnd) } else { _ = readOpener(character) }
        case Unit.openingBracket, Unit.openingBrace: _ = readOpener(character)
        case Unit.reverseSolidus:
            if next == Unit.closingBracket { closeTrapezoid(.trapezoidEnd) } else { emitFlat(.text, to: position + 1) }
        case Unit.solidus:
            if next == Unit.closingBracket { closeTrapezoid(.invertedTrapezoidEnd) } else { emitFlat(.text, to: position + 1) }
        case Unit.closingBracket, Unit.closingParenthesis:
            guard next == Unit.closingBracket else { return false }
            closeTrapezoid(.trapezoidEnd)
        case Unit.closingBrace: return false
        case Unit.percentSign:
            let end = commentEnd(from: position)
            guard end >= 0 else { return false }
            advance(to: end)
        default:
            if character == Unit.questionMark || character == Unit.equalsSign, next == Unit.closingBracket {
                closeTrapezoid(.trapezoidEnd)
                break
            }
            var end = position + 1
            while end < count, !Self.trapezoidStops.contains(Int(units[end])) { end += 1 }
            emit(.text, to: end)
        }
        return true
    }

    private mutating func closeTrapezoid(_ kind: ReferenceAgentFlowTokenKind) {
        pop()
        emitFlat(kind, to: position + 2)
    }

    /// After `--`: a quoted string, the arrow that ends the link, or the text up to a quotation mark, `--` or an arrow
    /// after white space.
    mutating func readEdgeText(_ character: Int) -> Bool {
        if character == Unit.quotationMark {
            readQuotationMark()
            return true
        }
        let arrow = arrowEnd(from: position)
        if arrow >= 0 {
            pop()
            emit(.link, to: arrow)
            return true
        }
        if character == Unit.hyphen, self.character(at: position + 1) == Unit.hyphen { return false }
        var end = position + 1
        while end < count {
            let unit = Int(units[end])
            if unit == Unit.quotationMark { break }
            if unit == Unit.hyphen {
                if self.character(at: end + 1) == Unit.hyphen { break }
            } else if Unit.isSpace(unit), arrowEnd(from: end) >= 0 {
                break
            }
            end += 1
        }
        emitCharacters(.edgeText, to: end)
        return true
    }

    static let textStops: Set<Int> = [91, 93, 40, 41, 123, 125, 124, 34, 37]
    static let ellipseStops: Set<Int> = [34, 40, 41, 91, 93, 123, 125]
    static let trapezoidStops: Set<Int> = [92, 91, 93, 40, 41, 123, 125, 47, 37]
}
