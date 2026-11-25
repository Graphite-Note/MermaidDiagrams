/**
 * File: ReferenceFirstMatchTokenPatterns.swift
 * --------------------------------------------
 * Layer: Tests
 * Description: MermaidDiagrams 0.7.0's the patterns the first-match token rules share, as closures, frozen as the reference the compiled tokenizer is checked
 *              against.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 24/11/2026
 */

@testable import MermaidDiagrams


/// How a token rule's pattern matches at a position, by the regular expression Mermaid's grammars give it.
typealias ReferenceFirstMatchTokenPattern = @Sendable (inout ReferenceFirstMatchTokenizerText, Int) -> ReferenceFirstMatchTokenMatch

enum ReferenceFirstMatchTokenPatterns {
    /// The text itself, compared exactly.
    static func literal(_ text: String) -> ReferenceFirstMatchTokenPattern {
        let literal = Array(text.utf8)
        return { text, position in
            starts(text.bytes, at: position, with: literal) ? .matched(end: position + literal.count) : .none
        }
    }

    /// A diagram's keyword, which Mermaid ends only at whitespace, a comment or the end of the text.
    static func keyword(_ word: String) -> ReferenceFirstMatchTokenPattern {
        let literal = Array(word.utf8)
        return { text, position in
            let end = position + literal.count
            guard starts(text.bytes, at: position, with: literal), isAtEndOfWord(text.bytes, end) else { return .none }
            return .matched(end: end)
        }
    }

    /// A first byte `first` allows, then any number that `rest` allows.
    static func name(first: @escaping @Sendable (UInt8) -> Bool, rest: @escaping @Sendable (UInt8) -> Bool) -> ReferenceFirstMatchTokenPattern {
        { text, position in
            guard first(text.bytes[position]) else { return .none }
            var end = position + 1
            while end < text.bytes.count, rest(text.bytes[end]) { end += 1 }
            return .matched(end: end)
        }
    }

    /// `"…"` or `'…'`, a backslash taking the character after it (other than a line break) whatever it is.
    static let quoted: ReferenceFirstMatchTokenPattern = { text, position in
        let bytes = text.bytes
        let quote = bytes[position]
        guard quote == MermaidByte.quotationMark || quote == apostrophe else { return .none }
        var index = position + 1
        while index < bytes.count {
            let byte = bytes[index]
            if byte == quote { return .matched(end: index + 1) }
            if byte == backslash {
                guard index + 1 < bytes.count, lineTerminatorLength(bytes, index + 1) == 0 else { return .none }
                index += 1
            }
            index += 1
        }
        return .none
    }

    /// `[\t ]*%%` and the rest of the line.
    static let percentComment: ReferenceFirstMatchTokenPattern = { text, position in
        let start = endOfBlanks(text.bytes, from: position)
        guard starts(text.bytes, at: start, with: percentSigns) else { return .none }
        return .matched(end: endOfLine(text.bytes, from: start))
    }

    /// `[\t ]*%%{`, then the first `}%%` that a line break, whitespace or the end follows, the line break taken too.
    static let directive: ReferenceFirstMatchTokenPattern = { text, position in
        let start = endOfBlanks(text.bytes, from: position)
        guard starts(text.bytes, at: start, with: directiveOpening) else { return .none }
        var from = start + directiveOpening.count
        while let closing = text.firstOccurrence(of: directiveClosing, from: from) {
            if let end = endAfterClosingFence(text.bytes, closing + directiveClosing.count) { return .matched(end: end) }
            from = closing + 1
        }
        return .noneFurtherOn
    }

    /// Front matter written where it is not read: `---`, blanks and a line break, then the first line that is `---`,
    /// which a line break, whitespace or the end follows.
    static let frontMatterFence: ReferenceFirstMatchTokenPattern = { text, position in
        let bytes = text.bytes
        guard starts(bytes, at: position, with: fence) else { return .none }
        var index = endOfBlanks(bytes, from: position + fence.count)
        if index < bytes.count, bytes[index] == MermaidByte.carriageReturn { index += 1 }
        guard index < bytes.count, bytes[index] == MermaidByte.newline else { return .none }
        var lineStart = index + 1
        while true {
            if starts(bytes, at: lineStart, with: fence), let end = endAfterClosingFence(bytes, lineStart + fence.count) { return .matched(end: end) }
            guard let lineBreak = text.firstOccurrence(of: [MermaidByte.newline], from: lineStart) else { return .noneFurtherOn }
            lineStart = lineBreak + 1
        }
    }

    /// `opening`, then everything up to the first `closing`.
    static func blockComment(opening: String, closing: String) -> ReferenceFirstMatchTokenPattern {
        let opening = Array(opening.utf8)
        let closing = Array(closing.utf8)
        return { text, position in
            guard starts(text.bytes, at: position, with: opening) else { return .none }
            guard let end = text.firstOccurrence(of: closing, from: position + opening.count) else { return .noneFurtherOn }
            return .matched(end: end + closing.count)
        }
    }

    /// `opening` and the rest of the line (`//`, `#`).
    static func lineComment(opening: String) -> ReferenceFirstMatchTokenPattern {
        let opening = Array(opening.utf8)
        return { text, position in
            starts(text.bytes, at: position, with: opening) ? .matched(end: endOfLine(text.bytes, from: position)) : .none
        }
    }

    /// A run of whitespace: JavaScript's (`\s+`) when `isJavaScriptWhitespace`, else tabs, spaces and line breaks.
    static func whitespace(isJavaScriptWhitespace: Bool) -> ReferenceFirstMatchTokenPattern {
        { text, position in
            if isJavaScriptWhitespace { return .matched(end: JavaScriptWhitespace.endOfRun(in: text.bytes, from: position)) }
            var end = position
            while end < text.bytes.count, MermaidByte.isWhitespace(text.bytes[end]) { end += 1 }
            return .matched(end: end)
        }
    }

    /// A statement's keyword followed by the rest of its line: a blank, then text up to `%%` or the end of the line;
    /// or, when `allowsBare`, the keyword alone where no byte `continuesName` allows follows it.
    static func lineStatement(_ keyword: String, leadingBlanks: Bool, continuesName: @escaping @Sendable (UInt8) -> Bool) -> ReferenceFirstMatchTokenPattern {
        let keyword = Array(keyword.utf8)
        return { text, position in
            let bytes = text.bytes
            let start = leadingBlanks ? endOfBlanks(bytes, from: position) : position
            guard starts(bytes, at: start, with: keyword) else { return .none }
            let afterKeyword = start + keyword.count
            if afterKeyword < bytes.count, MermaidByte.isSpace(bytes[afterKeyword]) { return .matched(end: endBeforeComment(bytes, from: afterKeyword)) }
            if afterKeyword < bytes.count, continuesName(bytes[afterKeyword]) { return .none }
            return .matched(end: afterKeyword)
        }
    }

    /// `accTitle`, blanks, `:`, then the rest of the line up to `%%`.
    static func accessibilityTitle(leadingBlanks: Bool) -> ReferenceFirstMatchTokenPattern {
        { text, position in
            let bytes = text.bytes
            let start = leadingBlanks ? endOfBlanks(bytes, from: position) : position
            guard starts(bytes, at: start, with: accessibilityTitleKeyword) else { return .none }
            let colon = endOfBlanks(bytes, from: start + accessibilityTitleKeyword.count)
            guard colon < bytes.count, bytes[colon] == MermaidByte.colon else { return .none }
            return .matched(end: endBeforeComment(bytes, from: colon + 1))
        }
    }

    static func starts(_ bytes: [UInt8], at position: Int, with literal: [UInt8]) -> Bool {
        guard position + literal.count <= bytes.count else { return false }
        for (offset, byte) in literal.enumerated() where bytes[position + offset] != byte { return false }
        return true
    }

    /// Whether a word ending at `end` ends there for Mermaid: the end of the text, whitespace or `%%` follows.
    static func isAtEndOfWord(_ bytes: [UInt8], _ end: Int) -> Bool {
        end >= bytes.count || JavaScriptWhitespace.length(in: bytes, at: end) > 0 || starts(bytes, at: end, with: percentSigns)
    }

    static func endOfBlanks(_ bytes: [UInt8], from position: Int) -> Int {
        var end = position
        while end < bytes.count, MermaidByte.isSpace(bytes[end]) { end += 1 }
        return end
    }

    /// The position of the line break or carriage return that ends the line, or the end.
    static func endOfLine(_ bytes: [UInt8], from position: Int) -> Int {
        var end = position
        while end < bytes.count, bytes[end] != MermaidByte.newline, bytes[end] != MermaidByte.carriageReturn { end += 1 }
        return end
    }

    /// The end of the line, or the first `%%` on it before that.
    static func endBeforeComment(_ bytes: [UInt8], from position: Int) -> Int {
        var end = position
        while end < bytes.count, bytes[end] != MermaidByte.newline, bytes[end] != MermaidByte.carriageReturn {
            if bytes[end] == MermaidByte.percent, end + 1 < bytes.count, bytes[end + 1] == MermaidByte.percent { return end }
            end += 1
        }
        return end
    }

    /// The length of the line terminator JavaScript's `.` does not match at `position`: a line feed, a carriage return,
    /// or a line or paragraph separator; zero for any other character.
    static func lineTerminatorLength(_ bytes: [UInt8], _ position: Int) -> Int {
        guard position < bytes.count else { return 0 }
        if bytes[position] == MermaidByte.newline || bytes[position] == MermaidByte.carriageReturn { return 1 }
        let isSeparator = bytes[position] == 0xE2 && position + 2 < bytes.count && bytes[position + 1] == 0x80
            && (bytes[position + 2] == 0xA8 || bytes[position + 2] == 0xA9)
        return isSeparator ? 3 : 0
    }

    /// After a closing fence at `position`: past `\r\n` or `\n`, or at the position when whitespace or the end follows;
    /// nil when anything else follows.
    static func endAfterClosingFence(_ bytes: [UInt8], _ position: Int) -> Int? {
        if position < bytes.count, bytes[position] == MermaidByte.newline { return position + 1 }
        if position + 1 < bytes.count, bytes[position] == MermaidByte.carriageReturn, bytes[position + 1] == MermaidByte.newline { return position + 2 }
        return position >= bytes.count || JavaScriptWhitespace.length(in: bytes, at: position) > 0 ? position : nil
    }

    /// `\w` of JavaScript's regular expressions: an ASCII letter, a digit or an underscore.
    @Sendable static func isWordByte(_ byte: UInt8) -> Bool {
        MermaidByte.isLetter(byte) || MermaidByte.isDigit(byte) || byte == MermaidByte.underscore
    }

    static let apostrophe = UInt8(ascii: "'")
    static let backslash = UInt8(ascii: "\\")
    static let percentSigns = Array("%%".utf8)
    private static let directiveOpening = Array("%%{".utf8)
    private static let directiveClosing = Array("}%%".utf8)
    private static let fence = Array("---".utf8)
    private static let accessibilityTitleKeyword = Array("accTitle".utf8)
}
