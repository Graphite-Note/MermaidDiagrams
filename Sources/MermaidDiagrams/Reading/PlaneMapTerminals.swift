/**
 * File: PlaneMapTerminals.swift
 * -----------------------------
 * Layer: Core
 * Description: The terminals the Langium grammars of Cynefin frameworks and Wardley maps share, as Pele's
 *              common/tokens.ts matches them: titles, accessibility statements, strings, line breaks, front matter,
 *              directives and comments, and the values of each.
 *
 * Authors: Bahey Shalash
 * Version: 0.3
 * Date: 23/11/2026
 */

/// Matches the terminals Mermaid's Langium grammars share at a position of a diagram's bytes, as their regular
/// expressions do, and gives each one's end, or nil where it does not match. The leading spaces and tabs some of them
/// allow are skipped before they are tried, as the hidden white space before them would be. Front matter and directives
/// that find no end once are never tried again (`hasNoFrontMatterEnd`, `hasNoDirectiveEnd`): none is further on either.
struct PlaneMapTerminals {
    let bytes: [UInt8]
    private(set) var hasNoFrontMatterEnd = false
    private(set) var hasNoDirectiveEnd = false
    private(set) var hasNoDescriptionEnd = false

    init(bytes: [UInt8]) {
        self.bytes = bytes
    }

    func byte(_ index: Int) -> UInt8? {
        index >= 0 && index < bytes.count ? bytes[index] : nil
    }

    func hasPrefix(_ literal: String, at start: Int) -> Bool {
        let literalBytes = literal.utf8
        guard start >= 0, start <= bytes.count - literalBytes.count else { return false }
        var index = start
        for expected in literalBytes {
            guard bytes[index] == expected else { return false }
            index += 1
        }
        return true
    }

    /// The end of the line from `start`: the first line feed or carriage return, or the end of the text.
    func lineEnd(from start: Int) -> Int {
        var index = start
        while let next = byte(index), !PlaneMapByte.isLineBreak(next) { index += 1 }
        return index
    }

    /// The end of `[^\n\r]*?(?=%%)|[^\n\r]*` from `start`: up to the first `%%` on the line, else to its end.
    func endBeforeComment(from start: Int) -> Int {
        var index = start
        while let next = byte(index), !PlaneMapByte.isLineBreak(next) {
            if next == PlaneMapByte.percent, byte(index + 1) == PlaneMapByte.percent { return index }
            index += 1
        }
        return index
    }

    /// `title`, then a space or tab and the rest of the line up to a comment, or nothing.
    func endOfTitle(at start: Int) -> Int? {
        guard hasPrefix("title", at: start) else { return nil }
        guard let separator = byte(start + 5), PlaneMapByte.isBlank(separator) else { return start + 5 }
        return endBeforeComment(from: start + 6)
    }

    /// `accTitle`, spaces, `:` and the rest of the line up to a comment.
    func endOfAccessibilityTitle(at start: Int) -> Int? {
        guard hasPrefix("accTitle", at: start) else { return nil }
        var index = start + 8
        while let next = byte(index), PlaneMapByte.isBlank(next) { index += 1 }
        guard byte(index) == PlaneMapByte.colon else { return nil }
        return endBeforeComment(from: index + 1)
    }

    /// `accDescr`, then spaces, `:` and the rest of the line up to a comment, or white space and `{ … }` over any lines.
    /// A brace that finds no end once is never tried again.
    mutating func endOfAccessibilityDescription(at start: Int) -> Int? {
        guard hasPrefix("accDescr", at: start) else { return nil }
        var index = start + 8
        while let next = byte(index), PlaneMapByte.isBlank(next) { index += 1 }
        if byte(index) == PlaneMapByte.colon { return endBeforeComment(from: index + 1) }
        index = JavaScriptWhitespace.endOfRun(in: bytes, from: start + 8)
        guard byte(index) == PlaneMapByte.openingBrace, !hasNoDescriptionEnd else { return nil }
        guard let closing = bytes[(index + 1)...].firstIndex(of: PlaneMapByte.closingBrace) else {
            hasNoDescriptionEnd = true
            return nil
        }
        return closing + 1
    }

    /// Text in quotation marks or apostrophes over any lines, a backslash taking the next character but a line break.
    func endOfString(at start: Int) -> Int? {
        guard let quote = byte(start), quote == PlaneMapByte.quotationMark || quote == PlaneMapByte.apostrophe else { return nil }
        var index = start + 1
        while let next = byte(index) {
            if next == quote { return index + 1 }
            if next == PlaneMapByte.backslash {
                guard let escaped = byte(index + 1), !PlaneMapByte.isLineBreak(escaped) else { return nil }
                index += 2
            } else {
                index += 1
            }
        }
        return nil
    }

    /// `\r?\n`.
    func endOfLineBreak(at start: Int) -> Int? {
        if byte(start) == PlaneMapByte.lineFeed { return start + 1 }
        return byte(start) == PlaneMapByte.carriageReturn && byte(start + 1) == PlaneMapByte.lineFeed ? start + 2 : nil
    }

    /// `---` and a line break, any lines, then `---` at a line's start followed by a line break (taken) or white space.
    mutating func endOfFrontMatter(at start: Int) -> Int? {
        guard !hasNoFrontMatterEnd, hasPrefix("---", at: start) else { return nil }
        var index = start + 3
        while let next = byte(index), PlaneMapByte.isBlank(next) { index += 1 }
        guard let opened = endOfLineBreak(at: index) else { return nil }
        var candidate = opened
        while candidate <= bytes.count {
            if hasPrefix("---", at: candidate), let end = endAfterClosing(candidate + 3) { return end }
            guard let lineFeed = bytes[min(candidate, bytes.count)...].firstIndex(of: PlaneMapByte.lineFeed) else { break }
            candidate = lineFeed + 1
        }
        hasNoFrontMatterEnd = true
        return nil
    }

    /// `%%{`, any text, and the first `}%%` followed by a line break (taken) or white space.
    mutating func endOfDirective(at start: Int) -> Int? {
        guard !hasNoDirectiveEnd, hasPrefix("%%{", at: start) else { return nil }
        var index = start + 3
        while index + 3 <= bytes.count {
            if hasPrefix("}%%", at: index), let end = endAfterClosing(index + 3) { return end }
            index += 1
        }
        hasNoDirectiveEnd = true
        return nil
    }

    /// After a closing fence: a line break, taken, or JavaScript's white space or the end of the text, not taken; nil otherwise.
    private func endAfterClosing(_ index: Int) -> Int? {
        if let lineBreak = endOfLineBreak(at: index) { return lineBreak }
        guard index < bytes.count else { return index }
        return JavaScriptWhitespace.length(in: bytes, at: index) > 0 ? index : nil
    }

    /// `%%` and the rest of the line.
    func endOfComment(at start: Int) -> Int? {
        hasPrefix("%%", at: start) ? lineEnd(from: start + 2) : nil
    }

    /// The text from `start` to `end`.
    func text(from start: Int, to end: Int) -> String {
        String(decoding: bytes[start..<end], as: UTF8.self)
    }
}
