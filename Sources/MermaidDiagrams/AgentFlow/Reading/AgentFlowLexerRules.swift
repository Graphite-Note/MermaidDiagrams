/**
 * File: AgentFlowLexerRules.swift
 * -------------------------------
 * Layer: Core
 * Description: The rules several of an agent flow's start conditions share, as Pele's lexer.ts writes them: runs of
 *              white space, links and arrows, comments, quotation marks, the brackets that open a node's text, and
 *              node strings.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 19/11/2026
 */

extension AgentFlowLexer {
    private typealias Unit = AgentFlowCharacter

    /// The end of the run of white space starting at `start`. The last run is kept, so asking again from inside it
    /// costs nothing.
    mutating func whitespaceEnd(from start: Int) -> Int {
        if start >= whitespaceRun.from, start <= whitespaceRun.to { return whitespaceRun.to }
        var end = start
        while end < count, Unit.isSpace(Int(units[end])) { end += 1 }
        whitespaceRun = (start, end)
        return end
    }

    /// The end of the run of spaces and tabs starting at `start`, kept as the white space's is.
    mutating func blankEnd(from start: Int) -> Int {
        if start >= blankRun.from, start <= blankRun.to { return blankRun.to }
        let end = blanks(from: start)
        blankRun = (start, end)
        return end
    }

    func blanks(from start: Int) -> Int {
        var end = start
        while end < count, units[end] == UInt16(Unit.space) || units[end] == UInt16(Unit.tab) { end += 1 }
        return end
    }

    /// The end of `\s*--+[x>]\s*` starting at `start`, or -1.
    mutating func arrowEnd(from start: Int) -> Int {
        let dashes = whitespaceEnd(from: start)
        if dashes == noArrowAt || character(at: dashes) != Unit.hyphen || character(at: dashes + 1) != Unit.hyphen { return -1 }
        var index = dashes + 2
        while character(at: index) == Unit.hyphen { index += 1 }
        let head = character(at: index)
        if head == Unit.lowercaseX || head == Unit.greaterThan { return whitespaceEnd(from: index + 1) }
        noArrowAt = dashes
        return -1
    }

    /// A link at the position, after white space: `--` then more dashes and `x` or `>` (a whole link), `--` alone (the
    /// start of a link with text), or `-.` then dots and `-`.
    mutating func readLink() -> Bool {
        let start = whitespaceEnd(from: position)
        if start == noLinkAt || character(at: start) != Unit.hyphen { return false }
        let second = character(at: start + 1)
        var index = start + 2
        if second == Unit.hyphen {
            while character(at: index) == Unit.hyphen { index += 1 }
            let head = character(at: index)
            if head == Unit.lowercaseX || head == Unit.greaterThan {
                emit(.link, to: whitespaceEnd(from: index + 1))
            } else {
                push(.edgeText)
                emit(.startLink, to: whitespaceEnd(from: start + 2))
            }
            return true
        }
        if second == Unit.fullStop {
            while character(at: index) == Unit.fullStop { index += 1 }
            if character(at: index) == Unit.hyphen {
                emit(.link, to: whitespaceEnd(from: index + 1))
                return true
            }
        }
        noLinkAt = start
        return false
    }

    /// `%%` not followed by `{`, through the end of its line: where it ends, or -1.
    func commentEnd(from start: Int) -> Int {
        guard character(at: start) == Unit.percentSign, character(at: start + 1) == Unit.percentSign,
              character(at: start + 2) != Unit.openingBrace else { return -1 }
        var index = start + 2
        while index < count, units[index] != UInt16(Unit.lineFeed) { index += 1 }
        return index
    }

    /// A quotation mark: a Markdown string when a backtick follows it, else a string.
    mutating func readQuotationMark() {
        if character(at: position + 1) == Unit.graveAccent {
            push(.markdownString)
            advance(to: position + 2)
        } else {
            push(.string)
            advance(to: position + 1)
        }
    }

    /// The bracket that opens a node's text at the position, by its first character: `(`, `[`, `|` or `{`.
    mutating func readOpener(_ first: Int) -> Bool {
        let second = character(at: position + 1)
        switch first {
        case Unit.openingParenthesis:
            if second == Unit.hyphen {
                open(.ellipseStart, length: 2, then: .ellipseText)
            } else if second == Unit.openingBracket {
                open(.stadiumStart, length: 2, then: .text)
            } else if second == Unit.openingParenthesis, character(at: position + 2) == Unit.openingParenthesis {
                open(.doubleCircleStart, length: 3, then: .text)
            } else {
                open(.parenthesisStart, length: 1, then: .text)
            }
        case Unit.openingBracket:
            switch second {
            case Unit.openingBracket: open(.subroutineStart, length: 2, then: .text)
            case Unit.openingParenthesis: open(.cylinderStart, length: 2, then: .text)
            case Unit.solidus: open(.trapezoidStart, length: 2, then: .trapezoidText)
            case Unit.reverseSolidus: open(.invertedTrapezoidStart, length: 2, then: .trapezoidText)
            default: open(.squareStart, length: 1, then: .text)
            }
        case Unit.verticalLine: open(.pipe, length: 1, then: .text)
        case Unit.openingBrace: open(.diamondStart, length: 1, then: .text)
        default: return false
        }
        return true
    }

    private mutating func open(_ kind: AgentFlowTokenKind, length: Int, then next: StartCondition) {
        push(next)
        emitFlat(kind, to: position + length)
    }

    /// A node string: the characters of `NODE_STRING`, and `-` when no `>`, `-` or `.` follows it.
    mutating func readNodeString() -> Bool {
        var index = position
        while index < count {
            let unit = Int(units[index])
            if Unit.isNodeStringCharacter(unit) {
                index += 1
            } else if unit == Unit.hyphen, index + 1 < count {
                let next = Int(units[index + 1])
                if next == Unit.greaterThan || next == Unit.hyphen || next == Unit.fullStop { break }
                index += 1
            } else {
                break
            }
        }
        guard index > position else { return false }
        emitFlat(.nodeString, to: index)
        return true
    }
}
