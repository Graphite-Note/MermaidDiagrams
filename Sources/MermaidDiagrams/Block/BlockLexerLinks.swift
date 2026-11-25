/**
 * File: BlockLexerLinks.swift
 * ---------------------------
 * Layer: Core
 * Description: The rules of Pele's block lexer inside a shape and an arrow, and for links: a shape's closing bracket,
 *              an arrow's directions, a link whole or around its text.
 *
 * Authors: Bahey Shalash
 * Version: 0.2
 * Date: 24/11/2026
 */

extension BlockLexer {
    /// Pele's `nodeEnd`: a string, or the bracket that closes the shape.
    mutating func nodeEnd(_ current: UInt8) -> Bool {
        let next = byte(at: position + 1)
        let length: Int
        switch current {
        case PlaneMapByte.quotationMark:
            openQuotation()
            return true
        case PlaneMapByte.openingParenthesis:
            length = next == PlaneMapByte.hyphen ? 2
                : next == PlaneMapByte.openingParenthesis ? (byte(at: position + 2) == PlaneMapByte.openingParenthesis ? 3 : 2) : 1
        case PlaneMapByte.closingParenthesis:
            length = next == PlaneMapByte.closingParenthesis ? (byte(at: position + 2) == PlaneMapByte.closingParenthesis ? 3 : 2)
                : next == PlaneMapByte.closingBracket ? 2 : 1
        case PlaneMapByte.closingBrace: length = next == PlaneMapByte.closingBrace ? 2 : 1
        case PlaneMapByte.hyphen: length = next == PlaneMapByte.closingParenthesis ? 2 : 0
        case PlaneMapByte.closingBracket:
            length = next == PlaneMapByte.closingBracket || next == PlaneMapByte.closingParenthesis || next == PlaneMapByte.greaterThan ? 2 : 1
        case PlaneMapByte.backslash, PlaneMapByte.slash: length = next == PlaneMapByte.closingBracket ? 2 : 0
        default: length = 0
        }
        guard length > 0 else { return false }
        pop()
        emit(.nodeEnd, end: position + length)
        return true
    }

    /// Inside `<[`: a string, or `]>`, white space and `(`.
    mutating func blockArrow(_ current: UInt8) -> Bool {
        if current == PlaneMapByte.quotationMark {
            openQuotation()
            return true
        }
        guard current == PlaneMapByte.closingBracket, byte(at: position + 1) == PlaneMapByte.greaterThan else { return false }
        let parenthesis = skippingWhitespace(from: position + 2)
        guard byte(at: parenthesis) == PlaneMapByte.openingParenthesis else { return false }
        push(.arrowDirection)
        position = parenthesis + 1
        return true
    }

    /// Pele's `arrowDir`: `)`, which closes the arrow, or a direction after an optional comma, with the white space
    /// around it.
    mutating func arrowDirection(_ current: UInt8) -> Bool {
        if current == PlaneMapByte.closingParenthesis {
            pop()
            pop()
            put(.arrowEnd, literal: .arrowEnd, end: skippingWhitespace(from: position + 1))
            return true
        }
        let afterComma = current == PlaneMapByte.comma
        let from = skippingWhitespace(from: afterComma ? position + 1 : position)
        for direction in Self.arrowDirections where hasPrefix(direction, at: from) {
            let end = skippingWhitespace(from: from + direction.utf8.count)
            put(.direction, from: afterComma ? from : position, to: end, end: end)
            return true
        }
        return false
    }

    /// After `--`, `==` or `-.` that open a link's text: a string, or the rest of the link.
    mutating func linkLabel(_ current: UInt8) -> Bool {
        if current == PlaneMapByte.quotationMark {
            if byte(at: position + 1) == BlockByte.backtick {
                openQuotation()
            } else {
                emit(.linkLabel, end: position + 1)
                push(.string)
            }
            return true
        }
        let end = linkEnd(from: skippingWhitespace(from: position))
        guard end >= 0 else { return false }
        pop()
        emit(.link, end: skippingWhitespace(from: end))
        return true
    }

    /// A whole link, with the white space after it, or the start of a link's text (`--`, `-.`, `==`, after an
    /// optional `<`).
    mutating func link() -> Bool {
        let end = linkEnd(from: position)
        if end >= 0 {
            emit(.link, end: skippingWhitespace(from: end))
            return true
        }
        let start = byte(at: position) == PlaneMapByte.lessThan ? position + 1 : position
        let first = byte(at: start)
        let second = byte(at: start + 1)
        let opensText = (first == PlaneMapByte.hyphen && (second == PlaneMapByte.hyphen || second == PlaneMapByte.period))
            || (first == BlockByte.equals && second == BlockByte.equals)
        guard opensText else { return false }
        push(.linkLabel)
        emit(.startLink, end: skippingWhitespace(from: start + 2))
        return true
    }

    /// Pele's `linkEnd`: where a complete link from `start` ends, before its white space, or -1: an optional `x`, `o`
    /// or `<`, then `.+-` and a head, or a run of `-` or `=` of three or more, or of two and a head.
    func linkEnd(from start: Int) -> Int {
        var index = start
        if let first = byte(at: index), first == BlockByte.letterX || first == BlockByte.letterO || first == PlaneMapByte.lessThan { index += 1 }
        guard let line = byte(at: index) else { return -1 }
        if line == PlaneMapByte.period { return dottedLinkEnd(from: index) }
        guard line == PlaneMapByte.hyphen || line == BlockByte.equals else { return -1 }
        var end = index + 1
        while byte(at: end) == line { end += 1 }
        if end - index == 1 { return line == PlaneMapByte.hyphen ? dottedLinkEnd(from: end) : -1 }
        if isHead(byte(at: end)) { return end + 1 }
        return end - index >= 3 ? end : -1
    }

    /// The end of `.+-` and an optional head from `start`, or -1.
    private func dottedLinkEnd(from start: Int) -> Int {
        guard byte(at: start) == PlaneMapByte.period else { return -1 }
        var index = start + 1
        while byte(at: index) == PlaneMapByte.period { index += 1 }
        guard byte(at: index) == PlaneMapByte.hyphen else { return -1 }
        return isHead(byte(at: index + 1)) ? index + 2 : index + 1
    }

    private func isHead(_ candidate: UInt8?) -> Bool {
        candidate == BlockByte.letterX || candidate == BlockByte.letterO || candidate == PlaneMapByte.greaterThan
    }

    /// Pele's `DIRECTIONS`, in the order it tries them.
    private static let arrowDirections = ["right", "left", "x", "y", "up", "down"]
}
