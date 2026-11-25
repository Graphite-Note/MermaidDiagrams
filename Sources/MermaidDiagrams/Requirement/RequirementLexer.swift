/**
 * File: RequirementLexer.swift
 * ----------------------------
 * Layer: Core
 * Description: The token stream of Mermaid's requirement lexer over a diagram's UTF-8 bytes, borrowed, rule for rule as
 *              Pele's lexer produces it, one token at a time as the parser asks for it.
 *
 * Authors: Bahey Shalash
 * Version: 0.5
 * Date: 25/11/2026
 */

/// Produces the tokens of Mermaid's requirement lexer, as Pele's `lexer.ts` does: its rules are tried in order and the
/// first that matches wins, in one of six states (the text, a quoted string, a style statement, and the three kinds of
/// accessibility value). A character no rule matches ends the stream with `unreadable`; otherwise it ends with what Jison
/// still matches at the end of the text in the state it is in, then `endOfTokens`. The stream repeats its last token once
/// it has ended. JavaScript's whitespace is read as it is (`JavaScriptWhitespace`), and the positions are bytes. The
/// tokens are made as they are asked for, so that no list of them is kept.
struct RequirementLexer {
    enum State {
        case text, quotedString, styleStatement, accessibilityTitle, accessibilityDescription, accessibilityDescriptionBlock
    }

    let bytes: UnsafeBufferPointer<UInt8>
    private(set) var position: Int
    private var state = State.text
    /// The states under the current one: a state is pushed only from the text or a style statement, so two at most.
    private var pushedStates: (State, State) = (.text, .text)
    private var pushedCount = 0
    private var directions: RequirementDirectionStatements
    /// The token the last rule made, if it made one.
    private var made: RequirementToken?
    /// The tokens the end of the text still gives: the last state's empty match, then `endOfTokens`.
    private var finalTokens: (RequirementToken?, RequirementToken?) = (nil, nil)
    /// The token the stream ended with, `unreadable` or `endOfTokens`, given again from then on.
    private var lastToken: RequirementToken?
    private var hasFinished = false

    init(bytes: UnsafeBufferPointer<UInt8>, start: Int) {
        self.bytes = bytes
        position = start
        directions = RequirementDirectionStatements(bytes: bytes, from: start)
    }

    /// The next token.
    mutating func next() -> RequirementToken {
        if let lastToken { return lastToken }
        while position < bytes.count, !hasFinished {
            made = nil
            guard readToken() else {
                let unreadable = RequirementToken(kind: .unreadable, start: position, textRange: position..<position)
                lastToken = unreadable
                return unreadable
            }
            if let token = made { return token }
        }
        return finalToken()
    }

    /// At the text's end Jison still tries, once, the rules that can match nothing.
    private mutating func finalToken() -> RequirementToken {
        if !hasFinished {
            hasFinished = true
            let end = bytes.count
            let last: RequirementTokenKind? = switch state {
            case .text: .endOfText
            case .quotedString: .quotedText
            case .accessibilityTitle: .accessibilityTitleValue
            case .accessibilityDescription: .accessibilityDescriptionValue
            case .accessibilityDescriptionBlock: .accessibilityDescriptionBlockValue
            case .styleStatement: nil
            }
            let endOfTokens = RequirementToken(kind: .endOfTokens, start: end, textRange: end..<end)
            finalTokens = (last.map { kind in RequirementToken(kind: kind, start: end, textRange: end..<end) }, endOfTokens)
        }
        if let first = finalTokens.0 {
            finalTokens.0 = nil
            return first
        }
        let endOfTokens = finalTokens.1 ?? RequirementToken(kind: .endOfTokens, start: bytes.count, textRange: bytes.count..<bytes.count)
        lastToken = endOfTokens
        return endOfTokens
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
                emit(.quotedText, from: position, to: Self.firstIndex(of: MermaidByte.quotationMark, in: bytes, from: position))
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
                emit(.accessibilityDescriptionBlockValue, from: position, to: Self.firstIndex(of: MermaidByte.closingBrace, in: bytes, from: position))
            }
        }
        return true
    }

    /// The rules of the text's state, in Mermaid's order.
    private mutating func readText() -> Bool {
        let byte = bytes[position]
        // `title` starts with `t` and the accessibility statements with `a`, in either case.
        let lowercased = byte | 0x20
        if lowercased == UInt8(ascii: "t"), readTitle() { return true }
        if lowercased == UInt8(ascii: "a"), readAccessibilityStatement() { return true }
        if !directions.isEmpty, !Self.isLineEnd(bytes, at: position), let (direction, end) = directions.statement(at: position) {
            emit(.direction(direction), from: position, to: end)
            return true
        }
        if byte == MermaidByte.newline || (byte == MermaidByte.carriageReturn && peek(1) == MermaidByte.newline) {
            emit(.lineBreak, from: position, to: endOfLineBreaks(from: position))
            return true
        }
        let spaceEnd = Self.isPlainNonSpace(byte) ? position : JavaScriptWhitespace.endOfRun(in: bytes, from: position)
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
              Self.hasLowercased("itle", in: bytes, at: position + 1) else { return false }
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
        guard Self.hasLowercased("acc", in: bytes, at: position) else { return false }
        if let end = accessibilityKeywordEnd("acctitle", closing: MermaidByte.colon) {
            push(.accessibilityTitle)
            emit(.accessibilityTitle, from: position, to: end)
        } else if let end = accessibilityKeywordEnd("accdescr", closing: MermaidByte.colon) {
            push(.accessibilityDescription)
            emit(.accessibilityDescription, from: position, to: end)
        } else if let end = accessibilityKeywordEnd("accdescr", closing: MermaidByte.openingBrace) {
            push(.accessibilityDescriptionBlock)
            position = end
        } else {
            return false
        }
        return true
    }

    /// Where `word`, whitespace, `closing` and whitespace end, the word without regard to case, or nil.
    private func accessibilityKeywordEnd(_ word: StaticString, closing: UInt8) -> Int? {
        guard Self.hasLowercased(word, in: bytes, at: position) else { return nil }
        let afterSpace = JavaScriptWhitespace.endOfRun(in: bytes, from: position + word.utf8CodeUnitCount)
        guard afterSpace < bytes.count, bytes[afterSpace] == closing else { return nil }
        return JavaScriptWhitespace.endOfRun(in: bytes, from: afterSpace + 1)
    }

    /// A run of word characters: a keyword when it is one (and not longer than any), else the start of an unquoted text
    /// that runs to `:`, `,`, a line break, `{`, `<`, `>`, `-` or `=`, without the whitespace at its ends.
    private mutating func readWord() {
        var end = position + 1
        while end < bytes.count, Self.isWordByte(bytes[end]) { end += 1 }
        if end - position <= RequirementKeywords.longestKeywordLength, let keyword = RequirementKeywords.keyword(from: position, to: end, in: bytes) {
            if keyword == .style || keyword == .classDefinition || keyword == .classAssignment { push(.styleStatement) }
            emit(keyword, from: position, to: end)
            return
        }
        while end < bytes.count, !Self.endsUnquotedText(bytes[end]) { end += 1 }
        made = RequirementToken(kind: .unquotedText, start: position, textRange: Self.trimmed(bytes, position..<end))
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

    @inline(__always) private mutating func emit(_ kind: RequirementTokenKind, from start: Int, to end: Int) {
        made = RequirementToken(kind: kind, start: start, textRange: start..<end)
        position = end
    }

    private mutating func push(_ next: State) {
        if pushedCount == 0 { pushedStates.0 = state } else { pushedStates.1 = state }
        pushedCount += 1
        precondition(pushedCount <= 2, "a requirement lexer state is pushed only from the text or a style statement")
        state = next
    }

    private mutating func pop() {
        guard pushedCount > 0 else { return }
        pushedCount -= 1
        state = pushedCount == 0 ? pushedStates.0 : pushedStates.1
    }

    @inline(__always) private func peek(_ offset: Int) -> UInt8? {
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
}
