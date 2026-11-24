/**
 * File: GitGraphLexer.swift
 * -------------------------
 * Layer: Core
 * Description: Reads the tokens of a Git graph's statements from its UTF-8 bytes as Mermaid's Git graph lexer does,
 *              trying at each token only the keywords and attributes its first byte can start.
 *
 * Authors: felixchvl, Bahey Shalash
 * Version: 0.2
 * Date: 23/11/2026
 */

/// Reads the tokens of a Git graph's statements from its UTF-8 bytes as the lexer of Mermaid's Git graph grammar does
/// (Pele's port of it): of the token types that match where a token starts, the first in Mermaid's order wins, and a
/// keyword followed by more of a name (`commits`, `TBD`) is that name. Keywords are compared exactly, case included.
/// Spaces, tabs, `%%` comments and `%%{ … }%%` directives are skipped; a line break is a token.
struct GitGraphLexer {
    var cursor: MermaidTextCursor
    /// Set once a directive had no end: none can have one further on, so no later search is made.
    private var hasNoDirectiveEnd = false

    init(cursor: MermaidTextCursor) {
        self.cursor = cursor
    }

    /// Skips what separates tokens and reads the token there, with the position and line of its first byte, for the
    /// line and the text an error reports: numbers, so that no copy of the cursor is kept for each token.
    mutating func readToken() throws(MermaidDiagramReadError) -> (token: GitGraphToken, start: Int, line: Int) {
        skipSeparators()
        let start = cursor.position
        let line = cursor.line
        guard let byte = cursor.peek() else { return (.endOfText, start, line) }
        return (try token(startingWith: byte), start, line)
    }

    /// The text an error reports at `position`, a token's start.
    func excerpt(at position: Int) -> String {
        var start = MermaidTextCursor(bytes: cursor.bytes)
        start.advance(by: position)
        return start.excerpt()
    }

    /// Whether the cursor is where the `gitGraph` keyword may end: at a space, a line break, a comment or the end.
    var isAtKeywordEnd: Bool {
        guard let byte = cursor.peek() else { return true }
        return MermaidByte.isWhitespace(byte) || cursor.hasPrefix(Self.commentStart)
    }

    private mutating func skipSeparators() {
        while let byte = cursor.peek() {
            if MermaidByte.isSpace(byte) {
                cursor.advance()
            } else if cursor.hasPrefix(Self.directiveStart), skipDirective() {
                continue
            } else if cursor.hasPrefix(Self.commentStart) {
                cursor.skipToEndOfLine()
            } else {
                return
            }
        }
    }

    /// Skips a directive up to the first `}%%` followed by whitespace or the end; its options are read with the rest of
    /// the configuration (`MermaidConfigurationOptions`). False, with nothing skipped, when there is no such `}%%`: the line is then a comment.
    private mutating func skipDirective() -> Bool {
        guard !hasNoDirectiveEnd else { return false }
        let bytes = cursor.bytes
        var index = cursor.position + Self.directiveStart.count
        while index + Self.directiveEnd.count <= bytes.count {
            let afterEnd = index + Self.directiveEnd.count
            if bytes[index] == MermaidByte.closingBrace, bytes[index + 1] == MermaidByte.percent, bytes[index + 2] == MermaidByte.percent,
               afterEnd == bytes.count || MermaidByte.isWhitespace(bytes[afterEnd]) {
                cursor.advance(by: afterEnd - cursor.position)
                return true
            }
            index += 1
        }
        hasNoDirectiveEnd = true
        return false
    }

    private mutating func token(startingWith byte: UInt8) throws(MermaidDiagramReadError) -> GitGraphToken {
        switch byte {
        case MermaidByte.newline, MermaidByte.carriageReturn: return readLineBreak()
        case MermaidByte.colon:
            cursor.advance()
            return .colon
        case MermaidByte.quotationMark, Self.apostrophe: return try readQuotedText(closedBy: byte)
        default: break
        }
        // Each of the words below is tried only at the byte it starts with: `gitGraph:` at `g`, the attributes at theirs,
        // the accessibility statements (in any case) at `a` or `A`, and `title` at `t`.
        if byte == UInt8(ascii: "g"), cursor.hasPrefix(Self.diagramKeywordWithColon) {
            cursor.advance(by: Self.diagramKeywordWithColon.count)
            return .diagramKeywordWithColon
        }
        if let attribute = readAttribute(startingWith: byte) { return .attribute(attribute) }
        if MermaidByte.lowercased(byte) == UInt8(ascii: "a"), let accessibility = try MermaidAccessibilityStatement.read(&cursor) {
            return .accessibility(accessibility)
        }
        if byte == UInt8(ascii: "t"), let title = readTitle() { return .title(title) }
        if MermaidByte.isDigit(byte), let integer = readInteger(startingWith: byte) { return .integer(integer) }
        guard let length = nameLength() else { throw .invalidSyntax(line: cursor.line, problem: .unexpectedText(cursor.excerpt())) }
        let start = cursor.position
        cursor.advance(by: length)
        if let keyword = keywordToken(from: start, length: length) { return keyword }
        return .name(cursor.text(from: start, to: cursor.position))
    }

    /// `\n`, `\r\n` or `\r`, as Mermaid reads a text whose line breaks it first makes `\n`.
    private mutating func readLineBreak() -> GitGraphToken {
        let isCarriageReturnAndNewline = cursor.peek() == MermaidByte.carriageReturn && cursor.peek(1) == MermaidByte.newline
        cursor.advance(by: isCarriageReturnAndNewline ? 2 : 1)
        return .lineBreak
    }

    /// Text up to the next unescaped `closing` byte, which may run over several lines. A backslash keeps the character
    /// after it, or makes `\b`, `\f`, `\n`, `\r`, `\t`, `\v` and `\0` the control characters JavaScript does; one
    /// before a line break ends nothing, and the text is then unclosed, as in Mermaid's grammar.
    private mutating func readQuotedText(closedBy closing: UInt8) throws(MermaidDiagramReadError) -> GitGraphToken {
        let openingLine = cursor.line
        cursor.advance()
        var bytes: [UInt8] = []
        while let byte = cursor.peek(), byte != closing {
            guard byte == Self.backslash else {
                bytes.append(byte)
                cursor.advance()
                continue
            }
            guard let escaped = cursor.peek(1), escaped != MermaidByte.newline, escaped != MermaidByte.carriageReturn else { break }
            bytes.append(Self.controlCharactersByEscape[escaped] ?? escaped)
            cursor.advance(by: 2)
        }
        guard cursor.peek() == closing else { throw .invalidSyntax(line: openingLine, problem: .unclosedQuotation) }
        cursor.advance()
        return .quotedText(String(decoding: bytes, as: UTF8.self))
    }

    /// `id:`, `msg:`, `tag:`, `type:`, `parent:` or `order:`, the colon written right after the word. No two start with
    /// the same byte, so the one `first` starts is the only one tried.
    private mutating func readAttribute(startingWith first: UInt8) -> GitGraphAttribute? {
        let match: (written: [UInt8], attribute: GitGraphAttribute)
        switch first {
        case UInt8(ascii: "p"): match = Self.attributesByWriting[0]
        case UInt8(ascii: "o"): match = Self.attributesByWriting[1]
        case UInt8(ascii: "t"): match = Self.attributesByWriting[2]
        case UInt8(ascii: "m"): match = Self.attributesByWriting[3]
        case UInt8(ascii: "i"): match = Self.attributesByWriting[5]
        default: return nil
        }
        guard cursor.hasPrefix(match.written) else {
            // `tag:` starts with `t` too, as `type:` does.
            guard first == UInt8(ascii: "t"), cursor.hasPrefix(Self.attributesByWriting[4].written) else { return nil }
            cursor.advance(by: Self.attributesByWriting[4].written.count)
            return Self.attributesByWriting[4].attribute
        }
        cursor.advance(by: match.written.count)
        return match.attribute
    }

    /// `title`, and after a space or a tab the rest of its line up to a `%%` comment; nil when the word is not `title`.
    /// A word that starts with `title` is the title keyword and the rest of the word, as in Mermaid's lexer.
    private mutating func readTitle() -> String? {
        guard cursor.hasPrefix(Self.titleKeyword) else { return nil }
        cursor.advance(by: Self.titleKeyword.count)
        guard let separator = cursor.peek(), MermaidByte.isSpace(separator) else { return "" }
        let start = cursor.position
        while let byte = cursor.peek(), byte != MermaidByte.newline, byte != MermaidByte.carriageReturn, !cursor.hasPrefix(Self.commentStart) {
            cursor.advance()
        }
        let words = cursor.text(from: start, to: cursor.position).split(whereSeparator: { character in character == " " || character == "\t" })
        return words.joined(separator: " ")
    }

    /// A whole number as Mermaid's `0|[1-9][0-9]*(?!\.)` matches it: `0` alone; else the digits, or all but the last when
    /// a `.` follows them, as the expression backtracks; nil for one digit before a `.`, which starts a name (`1.0.1`).
    /// A number past `Int`'s range is `Int.max`, which sorts last as JavaScript's `Infinity` does.
    private mutating func readInteger(startingWith first: UInt8) -> Int? {
        if first == Self.digitZero {
            cursor.advance()
            return 0
        }
        var length = 1
        while let byte = cursor.peek(length), MermaidByte.isDigit(byte) { length += 1 }
        if cursor.peek(length) == MermaidByte.period {
            guard length > 1 else { return nil }
            length -= 1
        }
        let start = cursor.position
        cursor.advance(by: length)
        return Int(cursor.text(from: start, to: cursor.position)) ?? Int.max
    }

    /// The length of the name at the cursor: a letter, a digit or `_`, then letters, digits, `_`, `-`, `.` and `/`, up
    /// to the last that is no `.` or `/`. Nil when the byte at the cursor starts none.
    private func nameLength() -> Int? {
        guard let first = cursor.peek(), Self.isWordByte(first) else { return nil }
        var length = 1
        var offset = 1
        while let byte = cursor.peek(offset), Self.isWordByte(byte) || byte == MermaidByte.hyphen || byte == MermaidByte.period || byte == Self.slash {
            offset += 1
            if byte != MermaidByte.period, byte != Self.slash { length = offset }
        }
        return length
    }

    /// The keyword the whole name of `length` bytes at `start` is, or nil for a name; the cursor is past the name. The
    /// name's bytes are compared with the keywords its first byte can start.
    private func keywordToken(from start: Int, length: Int) -> GitGraphToken? {
        let bytes = cursor.bytes
        func isWord(_ keyword: [UInt8]) -> Bool {
            guard keyword.count == length else { return false }
            for offset in 0..<length where bytes[start + offset] != keyword[offset] { return false }
            return true
        }
        switch bytes[start] {
        case UInt8(ascii: "c"):
            if isWord(Self.commitKeyword) { return .statement(.commit) }
            if isWord(Self.checkoutKeyword) { return .statement(.checkout) }
            if isWord(Self.cherryPickKeyword) { return .statement(.cherryPick) }
        case UInt8(ascii: "b"): if isWord(Self.branchKeyword) { return .statement(.branch) }
        case UInt8(ascii: "m"): if isWord(Self.mergeKeyword) { return .statement(.merge) }
        case UInt8(ascii: "s"): if isWord(Self.switchKeyword) { return .statement(.checkout) }
        case UInt8(ascii: "N"): if isWord(Self.normalKeyword) { return .commitType(.normal) }
        case UInt8(ascii: "R"): if isWord(Self.reverseKeyword) { return .commitType(.reverse) }
        case UInt8(ascii: "H"): if isWord(Self.highlightKeyword) { return .commitType(.highlight) }
        case UInt8(ascii: "L"): if isWord(Self.leftToRightKeyword) { return .direction(.leftToRight) }
        case UInt8(ascii: "T"): if isWord(Self.topToBottomKeyword) { return .direction(.topToBottom) }
        case UInt8(ascii: "B"): if isWord(Self.bottomToTopKeyword) { return .direction(.bottomToTop) }
        case UInt8(ascii: "g"): if isWord(Self.diagramKeyword), isAtKeywordEnd { return .diagramKeyword }
        default: break
        }
        return nil
    }

    private static let commitKeyword = Array("commit".utf8)
    private static let checkoutKeyword = Array("checkout".utf8)
    private static let cherryPickKeyword = Array("cherry-pick".utf8)
    private static let branchKeyword = Array("branch".utf8)
    private static let mergeKeyword = Array("merge".utf8)
    private static let switchKeyword = Array("switch".utf8)
    private static let normalKeyword = Array("NORMAL".utf8)
    private static let reverseKeyword = Array("REVERSE".utf8)
    private static let highlightKeyword = Array("HIGHLIGHT".utf8)
    private static let leftToRightKeyword = Array("LR".utf8)
    private static let topToBottomKeyword = Array("TB".utf8)
    private static let bottomToTopKeyword = Array("BT".utf8)
    private static let diagramKeyword = Array("gitGraph".utf8)

    /// An ASCII letter, digit or `_`: what JavaScript's `\w` matches.
    private static func isWordByte(_ byte: UInt8) -> Bool {
        MermaidByte.isLetter(byte) || MermaidByte.isDigit(byte) || byte == MermaidByte.underscore
    }

    private static let attributesByWriting: [(written: [UInt8], attribute: GitGraphAttribute)] = [
        (Array("parent:".utf8), .parent), (Array("order:".utf8), .order), (Array("type:".utf8), .type), (Array("msg:".utf8), .message),
        (Array("tag:".utf8), .tag), (Array("id:".utf8), .identifier),
    ]
    private static let controlCharactersByEscape: [UInt8: UInt8] = [
        UInt8(ascii: "b"): 0x08, UInt8(ascii: "f"): 0x0C, UInt8(ascii: "n"): MermaidByte.newline, UInt8(ascii: "r"): MermaidByte.carriageReturn,
        UInt8(ascii: "t"): MermaidByte.tab, UInt8(ascii: "v"): 0x0B, UInt8(ascii: "0"): 0x00,
    ]
    private static let diagramKeywordWithColon = Array("gitGraph:".utf8)
    private static let titleKeyword = Array("title".utf8)
    private static let commentStart = Array("%%".utf8)
    private static let directiveStart = Array("%%{".utf8)
    private static let directiveEnd = Array("}%%".utf8)
    private static let apostrophe = UInt8(ascii: "'")
    private static let backslash = UInt8(ascii: "\\")
    private static let slash = UInt8(ascii: "/")
    private static let digitZero = UInt8(ascii: "0")
}
