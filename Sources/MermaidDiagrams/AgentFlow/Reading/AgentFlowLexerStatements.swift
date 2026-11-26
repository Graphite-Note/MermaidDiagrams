/**
 * File: AgentFlowLexerStatements.swift
 * ------------------------------------
 * Layer: Core
 * Description: The initial condition's rules after its keywords, as Pele's lexer.ts writes them: direction statements
 *              found as the greedy regular expressions find them, link identifiers, punctuation and white space.
 *
 * Authors: Bahey Shalash
 * Version: 0.2
 * Date: 26/11/2026
 */

extension AgentFlowLexer {
    private typealias Unit = AgentFlowCharacter

    /// `.*direction\s+TB[^\n]*` and the other four directions, each tried in turn on a line that holds `direction`. The
    /// greedy `.*` takes the last place on the line where the statement matches, and `[^\n]*` runs to the line feed.
    mutating func readDirectionStatement() -> Bool {
        guard nextDirection != -1, position >= directionFailedBefore else { return false }
        if nextDirection < position { nextDirection = Self.firstIndex(of: Self.directionWord, in: bytes, from: position) ?? -1 }
        guard nextDirection != -1 else { return false }
        if lineEnd < position {
            lineEnd = (position..<count).first { index in isLineTerminator(at: index) } ?? count
        }
        guard nextDirection < lineEnd else { return false }
        for (offset, letters) in Self.directionLetters.enumerated() {
            guard let end = directionStatementEnd(letters) else { continue }
            emit(AgentFlowTokenKind(rawValue: AgentFlowTokenKind.directionTopToBottom.rawValue + UInt8(offset)) ?? .directionTopToBottom, to: end)
            return true
        }
        // No direction statement starts anywhere in the rest of this line either.
        directionFailedBefore = lineEnd
        return false
    }

    /// Where the statement for `letters` that starts last on the line ends, or nil.
    private mutating func directionStatementEnd(_ letters: [UInt8]) -> Int? {
        var start = lineEnd - Self.directionWord.count
        while start >= position {
            if startsWith(Self.directionWord, at: start) {
                let afterWord = start + Self.directionWord.count
                let lettersAt = whitespaceEnd(from: afterWord)
                if lettersAt > afterWord, startsWith(letters, at: lettersAt) {
                    var end = lettersAt + letters.count
                    while end < count, bytes[end] != UInt8(Unit.lineFeed) { end += 1 }
                    return end
                }
            }
            start -= 1
        }
        return nil
    }

    /// A link's identifier: a run of characters without space or quotation mark, up to its last `@` that no `{` or `"`
    /// follows (`e1@-->`).
    mutating func readLinkIdentifier(_ character: Int) -> Bool {
        guard nextCommercialAt != -1, character != Unit.quotationMark, !Unit.isSpace(character) else { return false }
        if position >= runEnd {
            if nextCommercialAt < position { nextCommercialAt = bytes[position...].firstIndex(of: UInt8(Unit.commercialAt)) ?? -1 }
            var end = position
            while end < count, Int(bytes[end]) != Unit.quotationMark, !isSpace(at: end) { end += 1 }
            runEnd = end
            runLinkIdentifierEnd = -1
            if nextCommercialAt != -1, nextCommercialAt < end {
                var index = min(end, count - 1) - 1
                while index >= nextCommercialAt {
                    if Int(bytes[index]) == Unit.commercialAt {
                        let after = self.character(at: index + 1)
                        if after != Unit.openingBrace, after != Unit.quotationMark {
                            runLinkIdentifierEnd = index
                            break
                        }
                    }
                    index -= 1
                }
            }
        }
        guard runLinkIdentifierEnd > position else { return false }
        emitFlat(.linkIdentifier, to: runLinkIdentifierEnd + 1)
        return true
    }

    /// One character of punctuation, or the rule its character starts; nil when the character is none of them.
    mutating func readPunctuation(_ character: Int) -> Bool? {
        let next = self.character(at: position + 1)
        switch character {
        case Unit.numberSign: emitFlat(.numberSign, to: position + 1)
        case Unit.colon:
            if next == Unit.colon, self.character(at: position + 2) == Unit.colon { emitFlat(.styleSeparator, to: position + 3) } else { emitFlat(.colon, to: position + 1) }
        case Unit.ampersand: emitFlat(.ampersand, to: position + 1)
        case Unit.semicolon: emitFlat(.semicolon, to: position + 1)
        case Unit.comma: emitFlat(.comma, to: position + 1)
        case Unit.asterisk: emitFlat(.asterisk, to: position + 1)
        case Unit.lessThan: emitFlat(.tagStart, to: position + 1)
        case Unit.hyphen:
            if readLink() || readNodeString() { return true }
            emitFlat(.minus, to: position + 1)
        case Unit.openingParenthesis, Unit.verticalLine, Unit.openingBrace: return readOpener(character)
        case Unit.openingBracket:
            guard next == Unit.verticalLine else { return readOpener(character) }
            emitFlat(.vertexWithPropertiesStart, to: position + 2)
        case Unit.greaterThan:
            push(.text)
            emitFlat(.tagEnd, to: position + 1)
        case Unit.circumflex: emitFlat(.up, to: position + 1)
        case Unit.reverseSolidus:
            guard next == Unit.verticalLine else { return readNodeString() }
            emitFlat(.separator, to: position + 2)
        case Unit.lowercaseV:
            guard !Unit.isWord(next) else { return readNodeString() }
            emitFlat(.down, to: position + 1)
        case Unit.percentSign:
            let end = commentEnd(from: position)
            guard end >= 0 else { return readNodeString() }
            emit(.comment, to: end)
        default: return nil
        }
        return true
    }

    /// White space: a link after it, a comment after spaces and tabs, a run of line breaks, or one space.
    mutating func readWhitespace(_ character: Int) {
        if readLink() { return }
        if character == Unit.space || character == Unit.tab {
            let end = commentEnd(from: blankEnd(from: position))
            if end >= 0 {
                emit(.comment, to: end)
                return
            }
        }
        var end = position
        while true {
            if self.character(at: end) == Unit.lineFeed {
                end += 1
            } else if self.character(at: end) == Unit.carriageReturn, self.character(at: end + 1) == Unit.lineFeed {
                end += 2
            } else {
                break
            }
        }
        if end > position { emit(.newline, to: end) } else { emit(.space, to: position + characterLength(at: position)) }
    }

    /// The letters of `TB`, `BT`, `RL`, `LR` and `TD`, in the order of Pele's expressions and of the tokens.
    static let directionLetters = ["TB", "BT", "RL", "LR", "TD"].map { letters in Array(letters.utf8) }
}
