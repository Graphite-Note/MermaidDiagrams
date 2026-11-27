/**
 * File: EntityRelationshipAttributeWords.swift
 * --------------------------------------------
 * Layer: Core
 * Description: The tokens inside an entity's block, read on the text's borrowed bytes as Mermaid's lexer reads them
 *              there: words as byte ranges, keys, comments and punctuation.
 *
 * Authors: felixchvl, Bahey Shalash
 * Version: 0.3
 * Date: 26/11/2026
 */

#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif

/// The tokens inside an entity's `{ … }`, as Mermaid's lexer reads them there: whitespace and line breaks only
/// separate them, `PK`, `FK` and `UK` are keys in any case, and a run holding `~` is one word to the last `~` of its
/// line. Where the next `~` and whitespace are is found once and kept until the cursor passes them, so that a long
/// line of short tokens is read in one pass.
struct EntityRelationshipAttributeWords {
    enum Token: Equatable {
        /// A type or a name, by its bytes.
        case word(MermaidTextRange)
        case key(EntityRelationshipAttributeKey)
        /// The text between quotation marks, which may run over several lines, by its bytes.
        case comment(MermaidTextRange)
        case questionMark
        case comma
        case closingBrace
        case endOfText
        case unexpectedCharacter
    }

    private(set) var cursor: GraphDiagramBytes
    /// Where the last token read starts, whose line an error names.
    private(set) var tokenStart: Int
    /// The next whitespace at or after the cursor (the end of the text when there is none), once found.
    private var nextWhitespacePosition = -1
    /// The next `~` at or after the cursor (the end of the text when there is none), once found.
    private var nextTildePosition = -1
    /// Where the line of the last run holding `~` ends, and the position of that line's last `~`.
    private var tildeLineEnd = -1
    private var lastTildeOfLine = -1

    init(cursor: GraphDiagramBytes) {
        self.cursor = cursor
        tokenStart = cursor.position
    }

    mutating func next() throws(MermaidDiagramReadError) -> Token {
        skipWhitespaceAndComments()
        tokenStart = cursor.position
        guard let byte = cursor.peek() else { return .endOfText }
        if let key = readKey() { return .key(key) }
        if let word = readRunHoldingTildes() { return .word(word) }
        if characterLength(atOffset: 0, startsWord: true) > 0 { return .word(readWord()) }
        let token: Token
        switch byte {
        case MermaidByte.graveAccent: return .word(readBacktickWord())
        case MermaidByte.quotationMark: return try readComment()
        case MermaidByte.closingBrace: token = .closingBrace
        case Self.questionMark: token = .questionMark
        case MermaidByte.comma: token = .comma
        default: token = .unexpectedCharacter
        }
        cursor.advance()
        return token
    }

    /// Skips whitespace, line breaks, `%%` comments and empty backticks.
    private mutating func skipWhitespaceAndComments() {
        while !cursor.isAtEnd {
            let whitespace = whitespaceLength(at: cursor.position)
            if whitespace > 0 {
                cursor.advance(by: whitespace)
            } else if cursor.isAtCommentStart {
                cursor.skipToEndOfLine()
            } else if cursor.isAt(MermaidByte.graveAccent, MermaidByte.graveAccent) {
                cursor.advance(by: 2)
            } else {
                return
            }
        }
    }

    /// `PK`, `FK` or `UK` in any case, when no letter, digit or `_` follows.
    private mutating func readKey() -> EntityRelationshipAttributeKey? {
        guard let first = cursor.peek().map(MermaidByte.lowercased), let second = cursor.peek(1).map(MermaidByte.lowercased),
              second == UInt8(ascii: "k") else { return nil }
        if let following = cursor.peek(2), EntityRelationshipWords.isWordByte(following) { return nil }
        let key: EntityRelationshipAttributeKey
        switch first {
        case UInt8(ascii: "p"): key = .primary
        case UInt8(ascii: "f"): key = .foreign
        case UInt8(ascii: "u"): key = .unique
        default: return nil
        }
        cursor.advance(by: 2)
        return key
    }

    /// A run without whitespace that holds a `~`, taken through the last `~` of its line and on to the next whitespace
    /// (`List~int~`, `Map~K, V~`); nil when the run holds none, or its `~` is the line's last.
    private mutating func readRunHoldingTildes() -> MermaidTextRange? {
        let position = cursor.position
        if nextTildePosition < position { nextTildePosition = Self.firstIndex(of: Self.tilde, in: cursor.buffer, from: position) }
        // With no `~` before the text's end no run holds one, and the whitespace need not be found.
        guard nextTildePosition < cursor.buffer.count else { return nil }
        if nextWhitespacePosition < position { nextWhitespacePosition = firstPosition(from: position) { index in whitespaceLength(at: index) > 0 } }
        guard nextTildePosition < nextWhitespacePosition else { return nil }
        if tildeLineEnd < position {
            tildeLineEnd = firstPosition(from: position) { index in
                cursor.buffer[index] == MermaidByte.newline || cursor.buffer[index] == MermaidByte.carriageReturn
            }
            lastTildeOfLine = (position..<tildeLineEnd).last { index in cursor.buffer[index] == Self.tilde } ?? -1
        }
        guard lastTildeOfLine > nextTildePosition else { return nil }
        let end = firstPosition(from: lastTildeOfLine + 1) { index in whitespaceLength(at: index) > 0 }
        cursor.advance(by: end - position)
        return MermaidTextRange(start: position, end: end)
    }

    /// A word that starts with a letter, `_`, `*` or a character from U+00C0, and goes on with letters, digits and
    /// `_ - * . [ ] ( ) ,`.
    private mutating func readWord() -> MermaidTextRange {
        let start = cursor.position
        var length = characterLength(atOffset: 0, startsWord: true)
        while length > 0 {
            cursor.advance(by: length)
            length = characterLength(atOffset: 0, startsWord: false)
        }
        return MermaidTextRange(start: start, end: cursor.position)
    }

    /// Text in backticks, which may hold any character; without its closing backtick it runs to the end of the text.
    private mutating func readBacktickWord() -> MermaidTextRange {
        cursor.advance()
        let start = cursor.position
        while let byte = cursor.peek(), byte != MermaidByte.graveAccent { cursor.advance() }
        let word = MermaidTextRange(start: start, end: cursor.position)
        if !cursor.isAtEnd { cursor.advance() }
        return word
    }

    private mutating func readComment() throws(MermaidDiagramReadError) -> Token {
        let opening = cursor.position
        cursor.advance()
        let start = cursor.position
        while let byte = cursor.peek(), byte != MermaidByte.quotationMark { cursor.advance() }
        guard !cursor.isAtEnd else { throw .invalidSyntax(line: cursor.line(at: opening), problem: .unclosedQuotation) }
        let text = MermaidTextRange(start: start, end: cursor.position)
        cursor.advance()
        return .comment(text)
    }

    /// The length in bytes of a word's character at `offset` from the cursor, 0 when there is none there. Beyond
    /// ASCII, Mermaid's pattern takes the characters from U+00C0, and µ.
    private func characterLength(atOffset offset: Int, startsWord: Bool) -> Int {
        guard let byte = cursor.peek(offset) else { return 0 }
        if byte < 0x80 {
            let isWordByte = MermaidByte.isLetter(byte) || byte == MermaidByte.underscore || byte == Self.asterisk
            if startsWord { return isWordByte ? 1 : 0 }
            return isWordByte || MermaidByte.isDigit(byte) || Self.isLaterWordByte(byte) ? 1 : 0
        }
        if byte == Self.leadByteBelowU00C0 { return cursor.peek(offset + 1) == Self.microSignSecondByte ? 2 : 0 }
        guard byte > Self.leadByteBelowU00C0, byte & 0xC0 != 0x80 else { return 0 }
        var length = 1
        while let continuation = cursor.peek(offset + length), continuation & 0xC0 == 0x80 { length += 1 }
        return length
    }

    /// 1 or 2 for whitespace at `index` (ASCII whitespace, or a no-break space), 0 otherwise.
    private func whitespaceLength(at index: Int) -> Int {
        let bytes = cursor.buffer
        guard index < bytes.count else { return 0 }
        if EntityRelationshipLexer.isWhitespace(bytes[index]) { return 1 }
        return bytes[index] == Self.leadByteBelowU00C0 && index + 1 < bytes.count && bytes[index + 1] == Self.noBreakSpaceSecondByte ? 2 : 0
    }

    /// The first `byte` at or after `start`, or the text's end.
    private static func firstIndex(of byte: UInt8, in bytes: UnsafeBufferPointer<UInt8>, from start: Int) -> Int {
        guard start < bytes.count, let base = bytes.baseAddress else { return bytes.count }
        guard let found = memchr(base + start, Int32(byte), bytes.count - start) else { return bytes.count }
        return base.distance(to: found.assumingMemoryBound(to: UInt8.self))
    }

    /// The first index from `start` that `matches`, or the end of the text.
    private func firstPosition(from start: Int, where matches: (Int) -> Bool) -> Int {
        var index = start
        while index < cursor.buffer.count, !matches(index) { index += 1 }
        return index
    }

    private static let tilde = UInt8(ascii: "~")
    private static let questionMark = UInt8(ascii: "?")
    private static let asterisk = UInt8(ascii: "*")
    /// After a word's first character: `-`, `.`, brackets, parentheses and commas, as in `public.geometry(point,4326)`.
    @inline(__always) private static func isLaterWordByte(_ byte: UInt8) -> Bool {
        byte == MermaidByte.hyphen || byte == MermaidByte.period || byte == MermaidByte.openingBracket || byte == MermaidByte.closingBracket
            || byte == UInt8(ascii: "(") || byte == UInt8(ascii: ")") || byte == MermaidByte.comma
    }
    /// The UTF-8 lead byte of the characters U+0080 to U+00BF.
    private static let leadByteBelowU00C0: UInt8 = 0xC2
    private static let microSignSecondByte: UInt8 = 0xB5
    private static let noBreakSpaceSecondByte: UInt8 = 0xA0
}
