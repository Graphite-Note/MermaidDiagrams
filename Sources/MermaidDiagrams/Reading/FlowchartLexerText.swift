/**
 * File: FlowchartLexerText.swift
 * ------------------------------
 * Layer: Core
 * Description: The tests Pele's flowchart lexer makes at the start of a token, over a flowchart's UTF-8 bytes: its
 *              keywords, its direction statement, a link's identifier, the start of a link and its node strings.
 *
 * Authors: Bahey Shalash
 * Version: 0.3
 * Date: 23/11/2026
 */

/// A flowchart's text as Pele's lexer (flowchart/lexer.ts) tests it where a token starts in its initial state. Past
/// the end it reads as the line break Pele appends to the text it parses. Made once per flowchart: its look-ahead index
/// is built over the whole text.
struct FlowchartLexerText {
    let bytes: [UInt8]
    private let lookAhead: FlowchartLookAheadIndex

    init(bytes: [UInt8]) {
        self.bytes = bytes
        lookAhead = FlowchartLookAheadIndex(bytes: bytes)
    }

    func byte(at position: Int) -> UInt8? {
        position >= 0 && position < bytes.count ? bytes[position] : nil
    }

    /// A character of `\w`: an ASCII letter, a digit or an underscore.
    static func isWord(_ byte: UInt8?) -> Bool {
        guard let byte else { return false }
        return MermaidByte.isLetter(byte) || MermaidByte.isDigit(byte) || byte == MermaidByte.underscore
    }

    func hasText(_ literal: [UInt8], at position: Int) -> Bool {
        guard position >= 0, position + literal.count <= bytes.count else { return false }
        for offset in literal.indices where bytes[position + offset] != literal[offset] { return false }
        return true
    }

    /// The lexer's `kw`: `word` at `position`, not followed by a character of `\w`.
    func isKeyword(_ word: [UInt8], at position: Int) -> Bool {
        hasText(word, at: position) && !Self.isWord(byte(at: position + word.count))
    }

    /// The position after the run of JavaScript whitespace (`\s`, line breaks included) from `position`.
    func endOfSpaces(from position: Int) -> Int {
        JavaScriptWhitespace.endOfRun(in: bytes, from: position)
    }

    /// Whether `word` and then at least one whitespace character stand at `position` (`call\s+`, `click\s+`).
    private func isWordAndSpace(_ word: [UInt8], at position: Int) -> Bool {
        hasText(word, at: position) && endOfSpaces(from: position + word.count) > position + word.count
    }

    /// Whether the lexer's initial state reads a token that is no part of an identifier at `position` before its
    /// direction and link identifier checks: `accTitle:`, `accDescr:` or `accDescr {`, shape data `@{`, `call `,
    /// `classDef`, `class`, `click `, `style`, `swimlane-beta`, `subgraph`, `linkStyle`, `interpolate`, `href `,
    /// `flowchart-elk`, `flowchart`, `graph`, `end`, `_self`, `_blank`, `_parent` or `_top`.
    func startsKeywordOrAccessibility(at position: Int) -> Bool {
        switch byte(at: position) {
        case UInt8(ascii: "a"):
            // `accTitle` and `accDescr` have the same length.
            let isTitle = hasText(Self.accessibilityTitle, at: position)
            guard isTitle || hasText(Self.accessibilityDescription, at: position) else { return false }
            let after = byte(at: endOfSpaces(from: position + Self.accessibilityTitle.count))
            return after == MermaidByte.colon || (!isTitle && after == MermaidByte.openingBrace)
        case MermaidByte.atSign: return byte(at: position + 1) == MermaidByte.openingBrace
        case UInt8(ascii: "c"):
            return isWordAndSpace(Self.call, at: position) || isKeyword(Self.classDefinition, at: position) || isKeyword(Self.classWord, at: position)
                || isWordAndSpace(Self.click, at: position)
        case UInt8(ascii: "s"): return isKeyword(Self.style, at: position) || isKeyword(Self.swimlane, at: position) || isKeyword(Self.subgraph, at: position)
        case UInt8(ascii: "l"): return isKeyword(Self.linkStyle, at: position)
        case UInt8(ascii: "i"): return isKeyword(Self.interpolate, at: position)
        case UInt8(ascii: "h"): return hasText(Self.hypertextReference, at: position) && JavaScriptWhitespace.length(in: bytes, at: position + 4) > 0
        case UInt8(ascii: "f"): return isKeyword(Self.flowchartElk, at: position) || isKeyword(Self.flowchart, at: position)
        case UInt8(ascii: "g"): return isKeyword(Self.graph, at: position)
        case UInt8(ascii: "e"): return isKeyword(Self.end, at: position)
        case MermaidByte.underscore: return Self.linkTargets.contains { word in isKeyword(word, at: position) }
        default: return false
        }
    }

    /// The lexer's direction statement, `.*direction\s+(TB|BT|RL|LR|TD)[^\n]*` from `position`: `direction`, then
    /// whitespace and a direction, anywhere from here to the line's end, which makes the rest of the line one token.
    func startsDirectionStatement(at position: Int) -> Bool {
        lookAhead.startsDirectionStatement(at: position)
    }

    /// Whether a link's identifier starts at `position`: the run of characters up to the next whitespace or
    /// quotation mark holds, after `position`, an `@` followed by neither `{` nor `"` (the lexer's `LINK_ID`, which
    /// runs to the last such `@`).
    func startsLinkIdentifier(at position: Int) -> Bool {
        endOfLinkIdentifier(at: position) != nil
    }

    /// The position after the `@` that ends a link's identifier starting at `position`, or nil.
    func endOfLinkIdentifier(at position: Int) -> Int? {
        guard lookAhead.hasLinkIdentifierEnds, let first = byte(at: position), first != MermaidByte.quotationMark,
              JavaScriptWhitespace.length(in: bytes, at: position) == 0 else { return nil }
        return lookAhead.lastLinkIdentifierEnd(inWordFrom: position).map { atSign in atSign + 1 }
    }

    /// Whether the lexer's `link` reads a link at `position`, where `x`, `o`, `-` or `.` stands: `--`, `---`, `-->` and
    /// the other solid ones, `-.` and the dotted ones, `==` and the thick ones, each with a mark (`x`, `o`, `<`) before it.
    func startsLink(at position: Int) -> Bool {
        var start = position
        if let mark = byte(at: start), mark == MermaidByte.letterX || mark == MermaidByte.letterO || mark == MermaidByte.lessThan { start += 1 }
        switch byte(at: start) {
        case MermaidByte.hyphen: return run(of: MermaidByte.hyphen, at: start) >= 2 || isDottedLink(markedAt: position)
            || (byte(at: start + 1) == MermaidByte.period)
        case MermaidByte.equals: return run(of: MermaidByte.equals, at: start) >= 2
        case MermaidByte.period: return isDottedLink(markedAt: position)
        default: return false
        }
    }

    /// `[xo<]?-?\.+-` at `position`: a dotted link with no text, its mark optional.
    private func isDottedLink(markedAt position: Int) -> Bool {
        if let mark = byte(at: position), mark == MermaidByte.letterX || mark == MermaidByte.letterO || mark == MermaidByte.lessThan,
           isDottedLinkWithoutMark(at: position + 1) { return true }
        return isDottedLinkWithoutMark(at: position)
    }

    /// `-?\.+-` at `start`.
    private func isDottedLinkWithoutMark(at start: Int) -> Bool {
        var index = start
        if byte(at: index) == MermaidByte.hyphen { index += 1 }
        let periods = run(of: MermaidByte.period, at: index)
        return periods > 0 && byte(at: index + periods) == MermaidByte.hyphen
    }

    private func run(of sign: UInt8, at position: Int) -> Int {
        var count = 0
        while byte(at: position + count) == sign { count += 1 }
        return count
    }

    /// The lexer's `nodeString`: ASCII letters, digits and ``!"#$%&'*+.`?\_/``, and a `-` not followed by `>`, `-` or
    /// `.`; the position after it, or nil when it is empty.
    func endOfNodeString(at position: Int) -> Int? {
        var end = position
        while let byte = byte(at: end) {
            if byte < 0x80, Self.nodeStringCharacters[Int(byte)] {
                end += 1
            } else if byte == MermaidByte.hyphen, case let next = self.byte(at: end + 1) ?? MermaidByte.newline,
                      next != MermaidByte.greaterThan, next != MermaidByte.hyphen, next != MermaidByte.period {
                end += 1
            } else {
                break
            }
        }
        return end > position ? end : nil
    }

    /// The Unicode scalar at `position` and its length in bytes, or nil for bytes that are not one.
    func scalar(at position: Int) -> (Unicode.Scalar, Int)? {
        var iterator = bytes[position...].makeIterator()
        var decoder = UTF8()
        guard case .scalarValue(let scalar) = decoder.decode(&iterator) else { return nil }
        return (scalar, UTF8.width(scalar))
    }

    private static let nodeStringCharacters: [Bool] = {
        var table = [Bool](repeating: false, count: 128)
        for byte in "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789!\"#$%&'*+.`?\\_/".utf8 { table[Int(byte)] = true }
        return table
    }()

    private static let accessibilityTitle = Array("accTitle".utf8)
    private static let accessibilityDescription = Array("accDescr".utf8)
    private static let call = Array("call".utf8)
    private static let classDefinition = Array("classDef".utf8)
    private static let classWord = Array("class".utf8)
    private static let click = Array("click".utf8)
    private static let style = Array("style".utf8)
    private static let swimlane = Array("swimlane-beta".utf8)
    private static let subgraph = Array("subgraph".utf8)
    private static let linkStyle = Array("linkStyle".utf8)
    private static let interpolate = Array("interpolate".utf8)
    private static let hypertextReference = Array("href".utf8)
    private static let flowchartElk = Array("flowchart-elk".utf8)
    private static let flowchart = Array("flowchart".utf8)
    private static let graph = Array("graph".utf8)
    private static let end = Array("end".utf8)
    private static let linkTargets = ["_self", "_blank", "_parent", "_top"].map { word in Array(word.utf8) }
}
