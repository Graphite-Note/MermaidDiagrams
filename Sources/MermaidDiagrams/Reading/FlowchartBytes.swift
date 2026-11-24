/**
 * File: FlowchartBytes.swift
 * --------------------------
 * Layer: Core
 * Description: A flowchart's text as Pele's lexer tests it where a token starts in its initial state, on a pointer to
 *              the text's bytes: keywords, links, node strings, white space, and the far look-aheads answered by the
 *              index made only for texts that need it.
 *
 * Authors: Bahey Shalash
 * Version: 0.3
 * Date: 24/11/2026
 */

/// A flowchart's bytes, borrowed for one reading, as Pele's lexer (flowchart/lexer.ts) tests them. Every position
/// outside the text reads as 0, which no test looks for; a 0 written in the text is told apart by `count`.
struct FlowchartBytes {
    let base: UnsafePointer<UInt8>
    let count: Int
    /// Where a direction statement or a link's identifier may start, found when the text holds `direction` or such
    /// an `@` (`FlowchartLookAheadIndex`); empty for every other text.
    let lookAhead: FlowchartLookAheadIndex

    var buffer: UnsafeBufferPointer<UInt8> { UnsafeBufferPointer(start: base, count: count) }

    @inline(__always) subscript(_ position: Int) -> UInt8 {
        position >= 0 && position < count ? base[position] : 0
    }

    /// Whether `literal` stands at `position`, whole.
    @inline(__always) func hasText(_ literal: StaticString, at position: Int) -> Bool {
        let length = literal.utf8CodeUnitCount
        guard position >= 0, position + length <= count else { return false }
        let literalBytes = literal.utf8Start
        for offset in 0..<length where base[position + offset] != literalBytes[offset] { return false }
        return true
    }

    /// A character of `\w`: an ASCII letter, a digit or an underscore.
    @inline(__always) static func isWord(_ byte: UInt8) -> Bool {
        (byte >= 0x61 && byte <= 0x7A) || (byte >= 0x41 && byte <= 0x5A) || (byte >= 0x30 && byte <= 0x39) || byte == 0x5F
    }

    /// The lexer's `kw`: `word` at `position`, not followed by a character of `\w`.
    @inline(__always) func isKeyword(_ word: StaticString, at position: Int) -> Bool {
        hasText(word, at: position) && !Self.isWord(self[position + word.utf8CodeUnitCount])
    }

    /// The length in bytes of the JavaScript white space (`\s`, line breaks included) at `position`, 0 for none.
    @inline(__always) func whitespaceLength(at position: Int) -> Int {
        let byte = self[position]
        if byte == 0x20 || (byte >= 0x09 && byte <= 0x0D) { return 1 }
        guard byte >= 0xC2, position < count else { return 0 }
        return JavaScriptWhitespace.length(in: buffer, at: position)
    }

    /// The position after the run of JavaScript white space from `position`.
    func endOfSpaces(from position: Int) -> Int {
        var end = position
        while case let length = whitespaceLength(at: end), length > 0 { end += length }
        return end
    }

    /// Whether `word` and then at least one white space character stand at `position` (`call\s+`, `click\s+`).
    private func isWordAndSpace(_ word: StaticString, at position: Int) -> Bool {
        hasText(word, at: position) && whitespaceLength(at: position + word.utf8CodeUnitCount) > 0
    }

    /// Whether the lexer's initial state reads a token that is no part of an identifier at `position` before its
    /// direction and link identifier checks: `accTitle:`, `accDescr:` or `accDescr {`, shape data `@{`, `call `,
    /// `classDef`, `class`, `click `, `style`, `swimlane-beta`, `subgraph`, `linkStyle`, `interpolate`, `href `,
    /// `flowchart-elk`, `flowchart`, `graph`, `end`, `_self`, `_blank`, `_parent` or `_top`.
    func startsKeywordOrAccessibility(at position: Int) -> Bool {
        switch self[position] {
        case 0x61: // a
            if hasText("accTitle", at: position) { return self[endOfSpaces(from: position + 8)] == MermaidByte.colon }
            if hasText("accDescr", at: position) {
                let after = self[endOfSpaces(from: position + 8)]
                return after == MermaidByte.colon || after == MermaidByte.openingBrace
            }
            return false
        case MermaidByte.atSign: return self[position + 1] == MermaidByte.openingBrace
        case 0x63: // c
            return isWordAndSpace("call", at: position) || isKeyword("classDef", at: position) || isKeyword("class", at: position)
                || isWordAndSpace("click", at: position)
        case 0x73: return isKeyword("style", at: position) || isKeyword("swimlane-beta", at: position) || isKeyword("subgraph", at: position)
        case 0x6C: return isKeyword("linkStyle", at: position)
        case 0x69: return isKeyword("interpolate", at: position)
        case 0x68: return hasText("href", at: position) && whitespaceLength(at: position + 4) > 0
        case 0x66: return isKeyword("flowchart-elk", at: position) || isKeyword("flowchart", at: position)
        case 0x67: return isKeyword("graph", at: position)
        case 0x65: return isKeyword("end", at: position)
        case MermaidByte.underscore:
            return isKeyword("_self", at: position) || isKeyword("_blank", at: position) || isKeyword("_parent", at: position)
                || isKeyword("_top", at: position)
        default: return false
        }
    }

    /// The lexer's direction statement, `.*direction\s+(TB|BT|RL|LR|TD)[^\n]*` from `position`.
    @inline(__always) func startsDirectionStatement(at position: Int) -> Bool {
        lookAhead.hasDirectionStatements && lookAhead.startsDirectionStatement(at: position)
    }

    /// The position after the `@` that ends a link's identifier starting at `position` (the lexer's `LINK_ID`, which runs
    /// to the last `@` of the word that neither `{` nor `"` follows), or nil.
    @inline(__always) func endOfLinkIdentifier(at position: Int) -> Int? {
        guard lookAhead.hasLinkAtSigns, position < count, self[position] != MermaidByte.quotationMark, whitespaceLength(at: position) == 0 else { return nil }
        return lookAhead.lastLinkAtSign(inWordFrom: position).map { atSign in atSign + 1 }
    }

    /// Whether the lexer's `link` reads a link at `position`: `--`, `---`, `-->` and the other solid ones, `-.` and the
    /// dotted ones, `==` and the thick ones, each with a mark (`x`, `o`, `<`) before it.
    func startsLink(at position: Int) -> Bool {
        var start = position
        let mark = self[start]
        if mark == MermaidByte.letterX || mark == MermaidByte.letterO || mark == MermaidByte.lessThan { start += 1 }
        switch self[start] {
        case MermaidByte.hyphen:
            return run(of: MermaidByte.hyphen, at: start) >= 2 || isDottedLink(markedAt: position) || self[start + 1] == MermaidByte.period
        case MermaidByte.equals: return run(of: MermaidByte.equals, at: start) >= 2
        case MermaidByte.period: return isDottedLink(markedAt: position)
        default: return false
        }
    }

    /// `[xo<]?-?\.+-` at `position`: a dotted link with no text, its mark optional.
    private func isDottedLink(markedAt position: Int) -> Bool {
        let mark = self[position]
        if mark == MermaidByte.letterX || mark == MermaidByte.letterO || mark == MermaidByte.lessThan, isDotted(from: position + 1) { return true }
        return isDotted(from: position)
    }

    private func isDotted(from start: Int) -> Bool {
        var index = start
        if self[index] == MermaidByte.hyphen { index += 1 }
        let periods = run(of: MermaidByte.period, at: index)
        return periods > 0 && self[index + periods] == MermaidByte.hyphen
    }

    /// How many `sign`s stand in a row from `position`.
    @inline(__always) func run(of sign: UInt8, at position: Int) -> Int {
        var length = 0
        while self[position + length] == sign { length += 1 }
        return length
    }

    /// The lexer's `nodeString`: ASCII letters, digits and ``!"#$%&'*+.`?\_/``, and a `-` not followed by `>`, `-` or
    /// `.`; the position after it, or nil when it is empty.
    @inline(__always) func endOfNodeString(at position: Int) -> Int? {
        var end = position
        while end < count {
            let byte = base[end]
            if Self.isNodeStringByte(byte) {
                end += 1
            } else if byte == MermaidByte.hyphen, case let next = end + 1 < count ? base[end + 1] : MermaidByte.newline,
                      next != MermaidByte.greaterThan, next != MermaidByte.hyphen, next != MermaidByte.period {
                end += 1
            } else {
                break
            }
        }
        return end > position ? end : nil
    }

    /// `A-Za-z0-9!"#$%&'*+.`?\_/` as two masks.
    @inline(__always) static func isNodeStringByte(_ byte: UInt8) -> Bool {
        byte < 64 ? (lowNodeStringBytes &>> UInt64(byte)) & 1 != 0 : byte < 128 && (highNodeStringBytes &>> UInt64(byte - 64)) & 1 != 0
    }

    private static let lowNodeStringBytes: UInt64 = Array("0123456789!\"#$%&'*+./?".utf8).reduce(0) { mask, byte in mask | 1 &<< UInt64(byte) }
    private static let highNodeStringBytes: UInt64 = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz`\\_".utf8).reduce(0) { mask, byte in
        mask | 1 &<< UInt64(byte - 64)
    }

    /// The Unicode scalar at `position` and its length in bytes, or nil for bytes that are not one.
    func scalar(at position: Int) -> (Unicode.Scalar, Int)? {
        guard position < count else { return nil }
        var iterator = buffer[position...].makeIterator()
        var decoder = UTF8()
        guard case .scalarValue(let scalar) = decoder.decode(&iterator) else { return nil }
        return (scalar, UTF8.width(scalar))
    }

    /// The text of the bytes from `start` to `end`.
    func string(from start: Int, to end: Int) -> String {
        String(decoding: UnsafeBufferPointer(rebasing: buffer[start..<end]), as: UTF8.self)
    }

    /// The 1-based line of `position`, as `MermaidTextCursor.line` counts it: for an error.
    func line(at position: Int) -> Int {
        MermaidSourceText.line(at: position, in: buffer)
    }

    /// The first characters at `position`, for an error (`MermaidTextCursor.excerpt`).
    func excerpt(at position: Int) -> String {
        MermaidSourceText.excerpt(at: position, in: buffer)
    }
}
