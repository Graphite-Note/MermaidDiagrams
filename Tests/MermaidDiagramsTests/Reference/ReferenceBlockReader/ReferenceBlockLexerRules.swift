/**
 * File: ReferenceBlockLexerRules.swift
 * ------------------------------------
 * Layer: Tests
 * Description: MermaidDiagrams 0.7.0's BlockLexerRules, frozen as main 2a0cc65 had it: the reference the block reader is
 *              proven against (BlockReadingEquivalenceTests).
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 24/11/2026
 */

@testable import MermaidDiagrams
extension ReferenceBlockLexer {
    /// Pele's `initial`: white space, a keyword, a string, an opening bracket, a link, a size, else an identifier up to
    /// `( ) [ { } < > - : =` or white space.
    mutating func initial(_ current: UInt8) -> Bool {
        let whitespace = JavaScriptWhitespace.length(in: bytes, at: position)
        if whitespace > 0 {
            position = skippingWhitespace(from: position)
            return true
        }
        if let read = keywordOrSymbol(current) { return read }
        var end = position
        while end < bytes.count {
            let next = bytes[end]
            if next < 0x80 ? Self.endsIdentifier[Int(next)] : JavaScriptWhitespace.length(in: bytes, at: end) > 0 { break }
            end += 1
        }
        guard end > position else { return false }
        emit(.nodeIdentifier, end: end)
        return true
    }

    /// What a keyword or a symbol at the position reads: true or false when a rule decided, nil when the text is left to
    /// be an identifier, as Pele's `break` out of its switch leaves it.
    private mutating func keywordOrSymbol(_ current: UInt8) -> Bool? {
        switch current {
        case UInt8(ascii: "b"): return blockKeyword()
        case UInt8(ascii: "c"): return columnsOrClass()
        case PlaneMapByte.quotationMark:
            openQuotation()
            return true
        case UInt8(ascii: "s"): return spaceOrStyle()
        case UInt8(ascii: "d"): return word("default", .defaultKeyword)
        case UInt8(ascii: "l"): return word("linkStyle", .linkStyle)
        case UInt8(ascii: "i"): return word("interpolate", .interpolate)
        case UInt8(ascii: "a"): return accessibilityStatement()
        case UInt8(ascii: "e"):
            guard isKeyword("end") else { return nil }
            emit(.end, end: skippingWhitespace(from: position + 3))
            return true
        default: return symbol(current)
        }
    }

    /// The brackets and links.
    private mutating func symbol(_ current: UInt8) -> Bool? {
        let next = byte(at: position + 1)
        switch current {
        case PlaneMapByte.hyphen:
            if next == PlaneMapByte.closingParenthesis { return openNode(length: 2) }
            return link()
        case ReferenceBlockByte.equals: return link()
        case PlaneMapByte.lessThan:
            guard next == PlaneMapByte.openingBracket else { return link() }
            push(.blockArrow)
            emit(.arrowStart, end: position + 2)
            return true
        case PlaneMapByte.openingParenthesis:
            let length = next == PlaneMapByte.hyphen || next == PlaneMapByte.openingBracket ? 2
                : next == PlaneMapByte.openingParenthesis ? (byte(at: position + 2) == PlaneMapByte.openingParenthesis ? 3 : 2) : 1
            return openNode(length: length)
        case PlaneMapByte.closingParenthesis, PlaneMapByte.openingBrace: return openNode(length: next == current ? 2 : 1)
        case PlaneMapByte.greaterThan: return openNode(length: 1)
        case PlaneMapByte.openingBracket:
            let doubled = [PlaneMapByte.openingBracket, ReferenceBlockByte.pipe, PlaneMapByte.openingParenthesis, PlaneMapByte.backslash, PlaneMapByte.slash]
            return openNode(length: next.map(doubled.contains) == true ? 2 : 1)
        case PlaneMapByte.colon:
            let end = skippingDigits(from: position + 1)
            guard end > position + 1 else { return false }
            put(.size, text(from: position + 1, to: end), end: end)
            return true
        default: return nil
        }
    }

    private mutating func openNode(length: Int) -> Bool {
        push(.node)
        emit(.nodeStart, end: position + length)
        return true
    }

    /// `literal` as a keyword, else nil.
    private mutating func word(_ literal: String, _ kind: ReferenceBlockTokenKind) -> Bool? {
        guard isKeyword(literal) else { return nil }
        emit(kind, end: position + literal.utf8.count)
        return true
    }

    /// `block-beta` or `block` (the diagram's keyword, or a composite without a title), or `block:` before an identifier.
    private mutating func blockKeyword() -> Bool? {
        guard hasPrefix("block", at: position) else { return nil }
        if isKeyword("block-beta") {
            emit(.keyword, end: position + 10)
            return true
        }
        if byte(at: position + 5) == PlaneMapByte.colon {
            emit(.compositeKeyword, end: position + 6)
            return true
        }
        guard !isWord(at: position + 5) else { return nil }
        emit(.keyword, end: position + 5)
        return true
    }

    /// `columns` and white space then `auto` (written -1) or digits; `class` or `classDef` and white space.
    private mutating func columnsOrClass() -> Bool? {
        if hasPrefix("columns", at: position) {
            let start = skippingWhitespace(from: position + 7)
            guard start > position + 7 else { return nil }
            if hasPrefix("auto", at: start), !isWord(at: start + 4) {
                put(.columns, "-1", end: start + 4)
                return true
            }
            let end = skippingDigits(from: start)
            guard end > start else { return nil }
            put(.columns, text(from: start, to: end), end: end)
            return true
        }
        guard hasPrefix("class", at: position) else { return nil }
        let isDefinition = hasPrefix("Def", at: position + 5)
        let from = isDefinition ? position + 8 : position + 5
        let after = skippingWhitespace(from: from)
        guard after > from else { return nil }
        push(isDefinition ? .classDefinition : .classAssignment)
        emit(isDefinition ? .classDefinition : .classAssignment, end: after)
        return true
    }

    /// `space`, `space:` and digits; `style` and white space.
    private mutating func spaceOrStyle() -> Bool? {
        if hasPrefix("space", at: position) {
            if byte(at: position + 5) == PlaneMapByte.colon {
                let end = skippingDigits(from: position + 6)
                if end > position + 6 {
                    put(.space, text(from: position + 6, to: end), end: end)
                    return true
                }
            }
            guard !isWord(at: position + 5) else { return nil }
            put(.space, "1", end: position + 5)
            return true
        }
        guard hasPrefix("style", at: position) else { return nil }
        let after = skippingWhitespace(from: position + 5)
        guard after > position + 5 else { return nil }
        push(.styleStatement)
        emit(.style, end: after)
        return true
    }

    /// `accTitle :` and `accDescr :` to the end of their line, `accDescr {` to its brace.
    private mutating func accessibilityStatement() -> Bool? {
        if hasPrefix("accTitle", at: position) {
            let colon = skippingWhitespace(from: position + 8)
            guard byte(at: colon) == PlaneMapByte.colon else { return nil }
            push(.accessibilityTitle)
            emit(.accessibilityTitle, end: skippingWhitespace(from: colon + 1))
            return true
        }
        guard hasPrefix("accDescr", at: position) else { return nil }
        let after = skippingWhitespace(from: position + 8)
        if byte(at: after) == PlaneMapByte.colon {
            push(.accessibilityDescription)
            emit(.accessibilityDescription, end: skippingWhitespace(from: after + 1))
            return true
        }
        guard byte(at: after) == PlaneMapByte.openingBrace else { return nil }
        push(.accessibilityDescriptionBlock)
        position = skippingWhitespace(from: after + 1)
        return true
    }

    /// Pele's `ID_STOP`: the ASCII characters that end an identifier.
    private static let endsIdentifier: [Bool] = {
        var stops = [Bool](repeating: false, count: 128)
        for stop in [9, 10, 11, 12, 13, 32, 40, 41, 45, 58, 60, 61, 62, 91, 123, 125] { stops[stop] = true }
        return stops
    }()
}
