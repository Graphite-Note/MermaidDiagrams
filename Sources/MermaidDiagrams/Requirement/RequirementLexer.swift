/**
 * File: RequirementLexer.swift
 * ----------------------------
 * Layer: Core
 * Description: The token stream of Mermaid's requirement lexer over a diagram's UTF-8 bytes, rule for rule as Pele's
 *              lexer produces it.
 *
 * Authors: Bahey Shalash
 * Version: 0.4
 * Date: 23/11/2026
 */

/// Produces the tokens of Mermaid's requirement lexer, as Pele's `lexer.ts` does: its rules are tried in order and the
/// first that matches wins, in one of six states (the text, a quoted string, a style statement, and the three kinds of
/// accessibility value). A character no rule matches ends the stream with `unreadable`; otherwise it ends with what Jison
/// still matches at the end of the text in the state it is in, then `endOfTokens`. JavaScript's whitespace is read as it
/// is (`JavaScriptWhitespace`), and the positions are bytes.
struct RequirementLexer {
    private enum State {
        case text, quotedString, styleStatement, accessibilityTitle, accessibilityDescription, accessibilityDescriptionBlock
    }

    let bytes: [UInt8]
    private(set) var position: Int
    private var state = State.text
    private var stack: [State] = []
    private(set) var tokens: [RequirementToken] = []
    private var directions: RequirementDirectionStatements

    private init(bytes: [UInt8], start: Int) {
        self.bytes = bytes
        position = start
        directions = RequirementDirectionStatements(bytes: bytes, from: start)
        // About one token in five bytes in the documentation's examples.
        tokens.reserveCapacity((bytes.count - start) / 5 + 2)
    }

    /// The tokens of the text from `start`.
    static func tokens(of bytes: [UInt8], from start: Int) -> [RequirementToken] {
        var lexer = RequirementLexer(bytes: bytes, start: start)
        while lexer.position < bytes.count {
            guard lexer.readToken() else {
                lexer.tokens.append(RequirementToken(kind: .unreadable, start: lexer.position, textRange: lexer.position..<lexer.position))
                return lexer.tokens
            }
        }
        lexer.finish()
        return lexer.tokens
    }

    /// One rule's match in the current state; false when none matches.
    private mutating func readToken() -> Bool {
        switch state {
        case .text: return readText()
        case .styleStatement: return readStyle()
        case .quotedString:
            if bytes[position] == MermaidByte.quotationMark {
                pop()
                position += 1
            } else {
                emit(.quotedText, from: position, to: bytes[position...].firstIndex(of: MermaidByte.quotationMark) ?? bytes.count)
            }
        case .accessibilityTitle:
            pop()
            emit(.accessibilityTitleValue, from: position, to: Self.lineBreak(in: bytes, from: position))
        case .accessibilityDescription:
            pop()
            emit(.accessibilityDescriptionValue, from: position, to: Self.lineBreak(in: bytes, from: position))
        case .accessibilityDescriptionBlock:
            if bytes[position] == MermaidByte.closingBrace {
                pop()
                position += 1
            } else {
                emit(.accessibilityDescriptionBlockValue, from: position, to: bytes[position...].firstIndex(of: MermaidByte.closingBrace) ?? bytes.count)
            }
        }
        return true
    }

    /// At the text's end Jison still tries, once, the rules that can match nothing.
    private mutating func finish() {
        let end = bytes.count
        let last: RequirementTokenKind? = switch state {
        case .text: .endOfText
        case .quotedString: .quotedText
        case .accessibilityTitle: .accessibilityTitleValue
        case .accessibilityDescription: .accessibilityDescriptionValue
        case .accessibilityDescriptionBlock: .accessibilityDescriptionBlockValue
        case .styleStatement: nil
        }
        if let last { emit(last, from: end, to: end) }
        emit(.endOfTokens, from: end, to: end)
    }

    /// The rules of the text's state, in Mermaid's order.
    private mutating func readText() -> Bool {
        if readTitle() || readAccessibilityStatement() { return true }
        if !directions.isEmpty, !Self.isLineEnd(bytes, at: position), let (direction, end) = directions.statement(at: position) {
            emit(.direction(direction), from: position, to: end)
            return true
        }
        let byte = bytes[position]
        if byte == MermaidByte.newline || (byte == MermaidByte.carriageReturn && peek(1) == MermaidByte.newline) {
            emit(.lineBreak, from: position, to: endOfLineBreaks(from: position))
            return true
        }
        let spaceEnd = JavaScriptWhitespace.endOfRun(in: bytes, from: position)
        if spaceEnd > position {
            position = spaceEnd
            return true
        }
        // Pele hides an entity code behind characters no rule reads where a token starts (`encodeEntities`).
        if byte == UInt8(ascii: "#"), isEntityCode(at: position) { return false }
        if byte == UInt8(ascii: "#") || byte == MermaidByte.percent {
            position = Self.lineBreak(in: bytes, from: position)
            return true
        }
        if Self.isWordByte(byte) {
            readWord()
            return true
        }
        return readPunctuation(byte)
    }

    /// `title` and a whitespace character, then at least one character before `#`, a line break or `;`.
    private mutating func readTitle() -> Bool {
        guard MermaidByte.lowercased(bytes[position]) == UInt8(ascii: "t"), position + 5 <= bytes.count,
              Self.hasLowercased(Self.titleRest, in: bytes, at: position + 1) else { return false }
        let spaceLength = JavaScriptWhitespace.length(in: bytes, at: position + 5)
        guard spaceLength > 0 else { return false }
        let textStart = position + 5 + spaceLength
        var end = textStart
        while end < bytes.count, bytes[end] != MermaidByte.newline {
            if let entityEnd = entityCodeEnd(at: end) {
                end = entityEnd
                continue
            }
            if bytes[end] == UInt8(ascii: "#") || bytes[end] == MermaidByte.semicolon { break }
            end += 1
        }
        guard end > textStart else { return false }
        emit(.title, from: position, to: end)
        return true
    }

    /// `accTitle\s*:\s*`, `accDescr\s*:\s*` and `accDescr\s*{\s*`, without regard to case.
    private mutating func readAccessibilityStatement() -> Bool {
        guard Self.hasLowercased(Self.accessibilityPrefix, in: bytes, at: position) else { return false }
        if let end = accessibilityKeywordEnd(Self.accessibilityTitleWord, closing: MermaidByte.colon) {
            push(.accessibilityTitle)
            emit(.accessibilityTitle, from: position, to: end)
        } else if let end = accessibilityKeywordEnd(Self.accessibilityDescriptionWord, closing: MermaidByte.colon) {
            push(.accessibilityDescription)
            emit(.accessibilityDescription, from: position, to: end)
        } else if let end = accessibilityKeywordEnd(Self.accessibilityDescriptionWord, closing: MermaidByte.openingBrace) {
            push(.accessibilityDescriptionBlock)
            position = end
        } else {
            return false
        }
        return true
    }

    /// Whether `word`, in lowercase, is written at `position` in any case: compared byte by byte, without making the bytes
    /// lowercase in an array of their own at every token.
    private static func hasLowercased(_ word: [UInt8], in bytes: [UInt8], at position: Int) -> Bool {
        guard position >= 0, position + word.count <= bytes.count else { return false }
        for (offset, byte) in word.enumerated() where MermaidByte.lowercased(bytes[position + offset]) != byte { return false }
        return true
    }

    private static let titleRest = Array("itle".utf8)
    private static let accessibilityPrefix = Array("acc".utf8)

    /// Where `word`, whitespace, `closing` and whitespace end, the word without regard to case, or nil.
    private func accessibilityKeywordEnd(_ word: [UInt8], closing: UInt8) -> Int? {
        guard Self.hasLowercased(word, in: bytes, at: position) else { return nil }
        let afterSpace = JavaScriptWhitespace.endOfRun(in: bytes, from: position + word.count)
        guard afterSpace < bytes.count, bytes[afterSpace] == closing else { return nil }
        return JavaScriptWhitespace.endOfRun(in: bytes, from: afterSpace + 1)
    }

    /// A run of word characters: a keyword when it is one (and not longer than any), else the start of an unquoted text
    /// that runs to `:`, `,`, a line break, `{`, `<`, `>`, `-` or `=`, without the whitespace at its ends.
    private mutating func readWord() {
        var end = position + 1
        while end < bytes.count, Self.isWordByte(bytes[end]) { end += 1 }
        if end - position <= RequirementKeywords.longestKeywordLength, let keyword = Self.keyword(from: position, to: end, in: bytes) {
            if keyword == .style || keyword == .classDefinition || keyword == .classAssignment { push(.styleStatement) }
            emit(keyword, from: position, to: end)
            return
        }
        while end < bytes.count, !Self.endsUnquotedText(bytes[end]) { end += 1 }
        let trimmed = JavaScriptWhitespace.trimmed(bytes[position..<end])
        tokens.append(RequirementToken(kind: .unquotedText, start: position, textRange: trimmed.startIndex..<trimmed.endIndex))
        position = end
    }

    /// `{`, `}`, `:::`, `:`, `<-`, `->`, `-`, `"` and `,`; false for any other character.
    private mutating func readPunctuation(_ byte: UInt8) -> Bool {
        switch byte {
        case MermaidByte.openingBrace: emit(.openingBrace, from: position, to: position + 1)
        case MermaidByte.closingBrace: emit(.closingBrace, from: position, to: position + 1)
        case MermaidByte.colon:
            if peek(1) == MermaidByte.colon, peek(2) == MermaidByte.colon {
                emit(.styleSeparator, from: position, to: position + 3)
            } else {
                emit(.fieldSeparator, from: position, to: position + 1)
            }
        case MermaidByte.lessThan:
            guard peek(1) == MermaidByte.hyphen else { return false }
            emit(.leftArrowEnd, from: position, to: position + 2)
        case MermaidByte.hyphen:
            if peek(1) == MermaidByte.greaterThan { emit(.rightArrowEnd, from: position, to: position + 2) } else { emit(.line, from: position, to: position + 1) }
        case MermaidByte.quotationMark:
            push(.quotedString)
            position += 1
        case MermaidByte.comma: emit(.comma, from: position, to: position + 1)
        default: return false
        }
        return true
    }

    /// Where the entity code `#name;` (a word of ASCII letters, digits and `_`) that starts at `start` ends, or nil: Pele
    /// hides each behind placeholder characters before its lexer reads the text, so that its `#` and `;` are read as
    /// neither a comment, a color nor the end of a title (`encodeEntities`).
    private func entityCodeEnd(at start: Int) -> Int? {
        guard bytes[start] == UInt8(ascii: "#") else { return nil }
        var end = start + 1
        while end < bytes.count, Self.isWordByte(bytes[end]) { end += 1 }
        return end > start + 1 && end < bytes.count && bytes[end] == MermaidByte.semicolon ? end + 1 : nil
    }

    private func isEntityCode(at start: Int) -> Bool {
        entityCodeEnd(at: start) != nil
    }

    /// The rules of a style statement, which ends at its line break.
    private mutating func readStyle() -> Bool {
        let byte = bytes[position]
        if byte == UInt8(ascii: "#"), isEntityCode(at: position) { return false }
        if Self.isWordByte(byte) {
            var end = position + 1
            while end < bytes.count, Self.isWordByte(bytes[end]) { end += 1 }
            emit(.styleWord, from: position, to: end)
            return true
        }
        let single: RequirementTokenKind? = switch byte {
        case MermaidByte.colon: .styleColon
        case MermaidByte.semicolon: .styleSemicolon
        case MermaidByte.percent: .stylePercent
        case MermaidByte.hyphen: .styleMinus
        case UInt8(ascii: "#"): .styleNumberSign
        case MermaidByte.comma: .comma
        default: nil
        }
        if let single {
            emit(single, from: position, to: position + 1)
        } else if byte == MermaidByte.space {
            position += 1
        } else if byte == MermaidByte.quotationMark {
            push(.quotedString)
            position += 1
        } else if byte == MermaidByte.newline {
            pop()
            position += 1
        } else {
            return false
        }
        return true
    }

    private mutating func emit(_ kind: RequirementTokenKind, from start: Int, to end: Int) {
        tokens.append(RequirementToken(kind: kind, start: start, textRange: start..<end))
        position = end
    }

    private mutating func push(_ next: State) {
        stack.append(state)
        state = next
    }

    private mutating func pop() {
        if let previous = stack.popLast() { state = previous }
    }

    private func peek(_ offset: Int) -> UInt8? {
        position + offset < bytes.count ? bytes[position + offset] : nil
    }

    /// Past a run of `\n` and `\r\n`.
    private func endOfLineBreaks(from start: Int) -> Int {
        var end = start
        while end < bytes.count {
            if bytes[end] == MermaidByte.newline {
                end += 1
            } else if bytes[end] == MermaidByte.carriageReturn, end + 1 < bytes.count, bytes[end + 1] == MermaidByte.newline {
                end += 2
            } else {
                break
            }
        }
        return end
    }

    private static let accessibilityTitleWord = Array("acctitle".utf8)
    private static let accessibilityDescriptionWord = Array("accdescr".utf8)

    /// The keyword the word from `start` to `end` is in any case, or nil: compared byte by byte, made lowercase, with the
    /// keywords of its length that start with its first letter, without making it a string to look it up.
    private static func keyword(from start: Int, to end: Int, in bytes: [UInt8]) -> RequirementTokenKind? {
        let first = MermaidByte.lowercased(bytes[start])
        guard first < 0x80 else { return nil }
        let length = end - start
        candidates: for (word, kind) in keywordsByFirstByte[Int(first)] where word.count == length {
            for offset in 1..<length where MermaidByte.lowercased(bytes[start + offset]) != word[offset] { continue candidates }
            return kind
        }
        return nil
    }

    /// `RequirementKeywords.byLowercaseWord`'s words as bytes, by their first byte.
    private static let keywordsByFirstByte: [[(word: [UInt8], kind: RequirementTokenKind)]] = {
        var byFirstByte = [[(word: [UInt8], kind: RequirementTokenKind)]](repeating: [], count: 128)
        for (word, kind) in RequirementKeywords.byLowercaseWord {
            let bytes = Array(word.utf8)
            byFirstByte[Int(bytes[0])].append((bytes, kind))
        }
        return byFirstByte
    }()
}

extension RequirementLexer {
    /// A character of `\w`.
    static func isWordByte(_ byte: UInt8) -> Bool {
        MermaidByte.isLetter(byte) || MermaidByte.isDigit(byte) || byte == MermaidByte.underscore
    }

    /// The bytes that end an unquoted text: `:,\r\n{<>-=`.
    static func endsUnquotedText(_ byte: UInt8) -> Bool {
        switch byte {
        case MermaidByte.colon, MermaidByte.comma, MermaidByte.carriageReturn, MermaidByte.newline, MermaidByte.openingBrace, MermaidByte.lessThan,
             MermaidByte.greaterThan, MermaidByte.hyphen, MermaidByte.equals: true
        default: false
        }
    }

    /// A line terminator, what JavaScript's `.` does not match: a line feed, a carriage return, U+2028 or U+2029.
    static func isLineEnd(_ bytes: [UInt8], at position: Int) -> Bool {
        let byte = bytes[position]
        if byte == MermaidByte.newline || byte == MermaidByte.carriageReturn { return true }
        return byte == 0xE2 && position + 2 < bytes.count && bytes[position + 1] == 0x80 && (bytes[position + 2] == 0xA8 || bytes[position + 2] == 0xA9)
    }

    /// The first line terminator at or after `start`, or the text's end.
    static func lineEnd(in bytes: [UInt8], from start: Int) -> Int {
        var position = start
        while position < bytes.count, !isLineEnd(bytes, at: position) { position += 1 }
        return position
    }

    /// The first line feed at or after `start`, or the text's end.
    static func lineBreak(in bytes: [UInt8], from start: Int) -> Int {
        bytes[min(start, bytes.count)...].firstIndex(of: MermaidByte.newline) ?? bytes.count
    }
}
