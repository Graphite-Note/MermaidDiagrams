/**
 * File: FirstMatchTokenPatterns.swift
 * -----------------------------------
 * Layer: Core
 * Description: The patterns the token rules of Mermaid's Langium grammars share, as matchers a tokenizer compiles into
 *              flat records and reads once over the bytes as their regular expressions would match them: literals,
 *              keywords, names, strings, comments, front matter fences and directives.
 *
 * Authors: Bahey Shalash
 * Version: 0.2
 * Date: 24/11/2026
 */

/// How a type's own token pattern matches at a position, for the few rules no shared matcher covers.
typealias FirstMatchTokenPattern = @Sendable (inout FirstMatchTokenizerText, Int) -> FirstMatchTokenMatch

/// The bytes a name's first byte or its next ones may be, as the grammars' character classes write them.
enum FirstMatchByteClass: UInt8, Sendable {
    /// `[A-Za-z]`.
    case letter = 1
    /// `[A-Z_a-z]`.
    case letterOrUnderscore = 2
    /// `[0-9]`.
    case digit = 4
    /// `\w`: a letter, a digit or an underscore.
    case word = 8
    /// `[\w-]`.
    case wordOrHyphen = 16
    /// `[A-Za-z0-9-]`.
    case letterDigitOrHyphen = 32

    /// Each byte's classes, as bits.
    private static let classesOfBytes: [UInt8] = (0..<256).map { value in
        let byte = UInt8(value)
        let isLetter = MermaidByte.isLetter(byte)
        let isDigit = MermaidByte.isDigit(byte)
        let isWord = isLetter || isDigit || byte == MermaidByte.underscore
        var classes: UInt8 = 0
        if isLetter { classes |= letter.rawValue }
        if isLetter || byte == MermaidByte.underscore { classes |= letterOrUnderscore.rawValue }
        if isDigit { classes |= digit.rawValue }
        if isWord { classes |= word.rawValue }
        if isWord || byte == MermaidByte.hyphen { classes |= wordOrHyphen.rawValue }
        if isLetter || isDigit || byte == MermaidByte.hyphen { classes |= letterDigitOrHyphen.rawValue }
        return classes
    }

    @inline(__always)
    func contains(_ byte: UInt8) -> Bool {
        Self.classesOfBytes[Int(byte)] & rawValue != 0
    }
}

/// How a token rule's pattern matches at a position, by the regular expression Mermaid's grammars give it.
enum FirstMatchTokenMatcher: Sendable {
    /// The text itself, compared exactly.
    case literal([UInt8])
    /// A diagram's keyword, which Mermaid ends only at whitespace, a comment or the end of the text.
    case keyword([UInt8])
    /// A first byte of one class, then any number of another's.
    case name(first: FirstMatchByteClass, rest: FirstMatchByteClass)
    /// `"…"` or `'…'`, a backslash taking the character after it (other than a line break) whatever it is.
    case quoted
    /// `[\t ]*%%` and the rest of the line.
    case percentComment
    /// `[\t ]*%%{`, then the first `}%%` that a line break, whitespace or the end follows, the line break taken too.
    case directive
    /// Front matter written where it is not read: `---`, blanks and a line break, then the first line that is `---`,
    /// which a line break, whitespace or the end follows.
    case frontMatterFence
    /// The opening, then everything up to the first closing.
    case blockComment(opening: [UInt8], closing: [UInt8])
    /// The opening and the rest of the line (`//`, `#`).
    case lineComment(opening: [UInt8])
    /// A run of whitespace: JavaScript's (`\s+`) when `isJavaScriptWhitespace`, else tabs, spaces and line breaks.
    case whitespace(isJavaScriptWhitespace: Bool)
    /// A statement's keyword followed by the rest of its line: a blank, then text up to `%%` or the end of the line;
    /// or the keyword alone where no byte of `continuesName` follows it.
    case lineStatement(keyword: [UInt8], leadingBlanks: Bool, continuesName: FirstMatchByteClass)
    /// `accTitle`, blanks, `:`, then the rest of the line up to `%%`.
    case accessibilityTitle(leadingBlanks: Bool)
    /// A type's own pattern.
    case custom(FirstMatchTokenPattern)
}

/// The shared matchers' builders, under the names the grammars' rules have always used, and the scanning helpers
/// the matchers and the types' own patterns share.
enum FirstMatchTokenPatterns {
    static func literal(_ text: String) -> FirstMatchTokenMatcher { .literal(Array(text.utf8)) }
    static func keyword(_ word: String) -> FirstMatchTokenMatcher { .keyword(Array(word.utf8)) }
    static func name(first: FirstMatchByteClass, rest: FirstMatchByteClass) -> FirstMatchTokenMatcher { .name(first: first, rest: rest) }
    static let quoted = FirstMatchTokenMatcher.quoted
    static let percentComment = FirstMatchTokenMatcher.percentComment
    static let directive = FirstMatchTokenMatcher.directive
    static let frontMatterFence = FirstMatchTokenMatcher.frontMatterFence

    static func blockComment(opening: String, closing: String) -> FirstMatchTokenMatcher {
        .blockComment(opening: Array(opening.utf8), closing: Array(closing.utf8))
    }

    static func lineComment(opening: String) -> FirstMatchTokenMatcher { .lineComment(opening: Array(opening.utf8)) }
    static func whitespace(isJavaScriptWhitespace: Bool) -> FirstMatchTokenMatcher { .whitespace(isJavaScriptWhitespace: isJavaScriptWhitespace) }

    static func lineStatement(_ keyword: String, leadingBlanks: Bool, continuesName: FirstMatchByteClass) -> FirstMatchTokenMatcher {
        .lineStatement(keyword: Array(keyword.utf8), leadingBlanks: leadingBlanks, continuesName: continuesName)
    }

    static func accessibilityTitle(leadingBlanks: Bool) -> FirstMatchTokenMatcher { .accessibilityTitle(leadingBlanks: leadingBlanks) }

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
    static let directiveOpening = Array("%%{".utf8)
    static let directiveClosing = Array("}%%".utf8)
    static let fence = Array("---".utf8)
    static let accessibilityTitleKeyword = Array("accTitle".utf8)
}
