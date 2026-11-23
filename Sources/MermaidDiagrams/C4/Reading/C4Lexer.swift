/**
 * File: C4Lexer.swift
 * -------------------
 * Layer: Core
 * Description: Reads a C4 diagram's text into tokens as the lexer Jison compiles from Mermaid's c4Diagram.jison does,
 *              Pele's lexer.ts step for step: its rules in order, its start conditions, and what it returns once the
 *              text runs out in each of them.
 *
 * Authors: Bahey Shalash
 * Version: 0.2
 * Date: 23/11/2026
 */

/// Reads a C4 diagram's tokens from its keyword on, on UTF-16 code units as Pele reads them. Every token's text is a
/// range of the text; nothing is copied until the parser asks for it. Each step consumes text, changes the start
/// condition or ends, and each search runs forward from where the last one of its kind ended, so the work grows with the
/// text's length.
struct C4Lexer {
    private enum StartCondition {
        case initial, macro, arguments, string, namedKey, namedKeyEnd, namedValue, accessibilityValue, multilineDescription
    }

    private let units: [UInt16]
    private var tokens = C4Tokens()
    private var condition = StartCondition.initial
    private var accessibilityValueKind = C4TokenKind.accessibilityTitleValue
    private var position = 0
    private var reachedEnd = false
    /// Where the next `direction` is, -2 before the first search and -1 when there is none; the end of the line being
    /// read; and where the line ends on which no direction statement starts.
    private var nextDirection = -2
    private var lineEnd = -1
    private var directionFailedBefore = 0

    static func tokens(of units: [UInt16]) -> C4Tokens {
        var lexer = C4Lexer(units: units)
        lexer.run()
        return lexer.tokens
    }

    private init(units: [UInt16]) {
        self.units = units
    }

    private var count: Int { units.count }

    /// Jison notes the end of the text one call before it reports it, so a rule that matches nothing gets one last turn.
    private mutating func run() {
        while true {
            if reachedEnd {
                emit(.end, from: count, to: count)
                return
            }
            if position >= count { reachedEnd = true }
            let unit = position < count ? units[position] : nil
            guard step(unit) else { return }
        }
    }

    /// One rule of the current start condition; false once the lexer gives up on unrecognized text.
    private mutating func step(_ unit: UInt16?) -> Bool {
        switch condition {
        case .initial: return readInitial(unit)
        case .macro: return readMacroParenthesis(unit)
        case .arguments: readArgument(unit)
        case .string: readStringPart(unit, closing: C4Characters.quotationMark, kind: .string, then: .arguments)
        case .namedKey:
            emit(.namedArgumentKey, from: position, to: upTo(C4Characters.equalsSign, from: position))
            condition = .namedKeyEnd
        case .namedKeyEnd: return readNamedKeyEnd(unit)
        case .namedValue:
            guard unit != nil else { return true }
            readStringPart(unit, closing: C4Characters.quotationMark, kind: .namedArgumentValue, then: .arguments)
        case .accessibilityValue:
            emit(accessibilityValueKind, from: position, to: upTo(C4Characters.lineFeed, from: position))
            condition = .initial
        case .multilineDescription:
            readStringPart(unit, closing: C4Characters.closingBrace, kind: .accessibilityDescriptionMultilineValue, then: .initial)
        }
        return true
    }

    private mutating func readInitial(_ unit: UInt16?) -> Bool {
        guard let unit else {
            emit(.endOfFile, from: count, to: count)
            return true
        }
        if readDirection() { return true }
        if unit == C4Characters.lowercaseT, readBareTitle() || readStatement("title", as: .title) { return true }
        if unit == C4Characters.lowercaseA, readAccessibilityStatement() { return true }
        if unit == C4Characters.percentSign, self.unit(at: position + 1) == C4Characters.percentSign {
            skipComment()
            return true
        }
        if C4Characters.isSpace(unit) {
            readWhitespace()
            return true
        }
        if unit == C4Characters.openingBrace || unit == C4Characters.closingBrace {
            emit(unit == C4Characters.openingBrace ? .openingBrace : .closingBrace, from: position, to: position + 1)
            return true
        }
        if C4Characters.isWord(unit), readKeyword() { return true }
        emit(.error, from: position, to: position)
        return false
    }

    // MARK: - The initial condition's rules

    /// `.*direction\s+TB[^\n]*` and the other three directions, tried only on a line that holds `direction`.
    private mutating func readDirection() -> Bool {
        guard nextDirection != -1, position >= directionFailedBefore else { return false }
        if nextDirection < position { nextDirection = firstIndex(of: Self.directionWord, from: position) ?? -1 }
        guard nextDirection != -1 else { return false }
        if lineEnd < position { lineEnd = (position..<count).first { index in C4Characters.isLineTerminator(units[index]) } ?? count }
        guard nextDirection < lineEnd else { return false }
        for (offset, letters) in Self.directionLetters.enumerated() {
            guard let end = directionStatementEnd(letters) else { continue }
            emit(C4TokenKind(rawValue: C4TokenKind.directionTopToBottom.rawValue + offset) ?? .directionTopToBottom, from: position, to: end)
            return true
        }
        // No direction statement starts anywhere in the rest of this line either.
        directionFailedBefore = lineEnd
        return false
    }

    /// Where a match of `.*direction\s+` and `letters` then `[^\n]*` from the position ends: the greedy `.*` takes the
    /// last `direction` of the line that is followed by white space and the letters.
    private func directionStatementEnd(_ letters: [UInt16]) -> Int? {
        var start = lineEnd - 1
        while start >= position {
            defer { start -= 1 }
            guard hasPrefix(Self.directionWord, at: start) else { continue }
            var after = start + Self.directionWord.count
            let spacesStart = after
            while after < count, C4Characters.isSpace(units[after]) { after += 1 }
            guard after > spacesStart, hasPrefix(letters, at: after) else { continue }
            return upTo(C4Characters.lineFeed, from: after + letters.count)
        }
        return nil
    }

    /// `title`, white space but no line break, then a line break or the end: no title, its white space after it skipped.
    private mutating func readBareTitle() -> Bool {
        guard hasPrefix(Self.titleWord, at: position) else { return false }
        var end = position + Self.titleWord.count
        while end < count, C4Characters.isSpace(units[end]), !isLineBreak(units[end]) { end += 1 }
        guard end == count || isLineBreak(units[end]) else { return false }
        position = skipSpaces(from: end)
        return true
    }

    /// `word\s[^#\n;]+`: the word, one white space character, and the rest up to a `#`, a line feed or a `;`.
    private mutating func readStatement(_ word: String, as kind: C4TokenKind) -> Bool {
        let wordUnits = Array(word.utf16)
        var end = position + wordUnits.count
        guard hasPrefix(wordUnits, at: position), end < count, C4Characters.isSpace(units[end]) else { return false }
        end += 1
        let valueStart = end
        while end < count, units[end] != C4Characters.numberSign, units[end] != C4Characters.lineFeed, units[end] != C4Characters.semicolon {
            end += 1
        }
        guard end > valueStart else { return false }
        emit(kind, from: position, to: end)
        return true
    }

    /// `accDescription …`, `accTitle:`, `accDescr:` and `accDescr {`.
    private mutating func readAccessibilityStatement() -> Bool {
        if readStatement("accDescription", as: .accessibilityDescriptionStatement) { return true }
        let isTitle = hasPrefix(Self.accessibilityTitleWord, at: position)
        guard isTitle || hasPrefix(Self.accessibilityDescriptionWord, at: position) else { return false }
        let mark = skipSpaces(from: position + Self.accessibilityTitleWord.count)
        if unit(at: mark) == C4Characters.colon {
            emit(isTitle ? .accessibilityTitle : .accessibilityDescription, from: position, to: skipSpaces(from: mark + 1))
            accessibilityValueKind = isTitle ? .accessibilityTitleValue : .accessibilityDescriptionValue
            condition = .accessibilityValue
            return true
        }
        guard unit(at: mark) == C4Characters.openingBrace, !isTitle else { return false }
        position = skipSpaces(from: mark + 1)
        condition = .multilineDescription
        return true
    }

    /// A comment takes the line breaks after it, so no line break token follows.
    private mutating func skipComment() {
        var end = upTo(C4Characters.lineFeed, from: position + 2)
        while end < count, isLineBreak(units[end]) { end += 1 }
        position = end
    }

    /// A run of white space: a line break token up to its last line feed, or nothing when it holds none.
    private mutating func readWhitespace() {
        var end = position
        var lastLineFeed = -1
        while end < count, C4Characters.isSpace(units[end]) {
            if units[end] == C4Characters.lineFeed { lastLineFeed = end }
            end += 1
        }
        if lastLineFeed != -1 {
            emit(.newline, from: position, to: lastLineFeed + 1)
        } else {
            position = end
        }
    }

    /// A word that is a keyword; a macro's keyword starts its parenthesis's condition.
    private mutating func readKeyword() -> Bool {
        var end = position + 1
        while end < count, C4Characters.isWord(units[end]) { end += 1 }
        guard end - position <= C4TokenKind.longestKeywordLength,
              let kind = C4TokenKind.keywords[UnicodeScalarText.string(utf16: units[position..<end])] else { return false }
        if kind > .deployment { condition = .macro }
        emit(kind, from: position, to: end)
        return true
    }

    // MARK: - A macro's arguments

    private mutating func readMacroParenthesis(_ unit: UInt16?) -> Bool {
        guard let unit else {
            emit(.endOfFileInMacro, from: count, to: count)
            return true
        }
        if unit == C4Characters.openingParenthesis {
            var next = position + 1
            while self.unit(at: next) == C4Characters.space { next += 1 }
            if self.unit(at: next) == C4Characters.comma { emit(.emptyArgument, from: position, to: next + 1) } else { position += 1 }
            condition = .arguments
            return true
        }
        if unit == C4Characters.closingParenthesis {
            position += 1
            condition = .initial
            return true
        }
        emit(.error, from: position, to: position)
        return false
    }

    private mutating func readArgument(_ unit: UInt16?) {
        guard let unit else { return }
        if unit == C4Characters.closingParenthesis {
            position += 1
            condition = .initial
        } else if unit == C4Characters.comma {
            if self.unit(at: position + 1) == C4Characters.comma { emit(.emptyArgument, from: position, to: position + 2) } else { position += 1 }
        } else {
            var start = position
            while self.unit(at: start) == C4Characters.space { start += 1 }
            let first = self.unit(at: start)
            if first == C4Characters.quotationMark {
                if self.unit(at: start + 1) == C4Characters.quotationMark {
                    emit(.emptyArgument, from: position, to: start + 2)
                } else {
                    position = start + 1
                    condition = .string
                }
            } else if first == C4Characters.dollarSign {
                position = start + 1
                condition = .namedKey
            } else {
                // An unquoted value runs to the next comma, through closing parentheses and line breaks.
                emit(.string, from: position, to: upTo(C4Characters.comma, from: position))
            }
        }
    }

    /// After a named argument's key: `=`, spaces, then the opening quotation mark of its value.
    private mutating func readNamedKeyEnd(_ unit: UInt16?) -> Bool {
        guard let unit else { return true }
        var next = position + 1
        if unit == C4Characters.equalsSign { while self.unit(at: next) == C4Characters.space { next += 1 } }
        guard unit == C4Characters.equalsSign, self.unit(at: next) == C4Characters.quotationMark else {
            emit(.error, from: position, to: position)
            return false
        }
        position = next + 1
        condition = .namedValue
        return true
    }

    /// The closing character ends the part and returns to `next`; anything else is text up to it.
    private mutating func readStringPart(_ unit: UInt16?, closing: UInt16, kind: C4TokenKind, then next: StartCondition) {
        if unit == closing {
            position += 1
            condition = next
        } else {
            emit(kind, from: position, to: upTo(closing, from: position))
        }
    }

    // MARK: - Helpers

    private mutating func emit(_ kind: C4TokenKind, from start: Int, to end: Int) {
        tokens.kinds.append(kind)
        tokens.starts.append(start)
        tokens.ends.append(end)
        position = end
    }

    private func unit(at index: Int) -> UInt16? {
        index >= 0 && index < count ? units[index] : nil
    }

    private func isLineBreak(_ unit: UInt16) -> Bool {
        unit == C4Characters.lineFeed || unit == C4Characters.carriageReturn
    }

    private func skipSpaces(from start: Int) -> Int {
        var end = start
        while end < count, C4Characters.isSpace(units[end]) { end += 1 }
        return end
    }

    /// The index of the next `unit` from `start`, or the end of the text.
    private func upTo(_ unit: UInt16, from start: Int) -> Int {
        guard start < count else { return count }
        return units[start...].firstIndex(of: unit) ?? count
    }

    private func hasPrefix(_ word: [UInt16], at start: Int) -> Bool {
        start >= 0 && start + word.count <= count && units[start..<(start + word.count)].elementsEqual(word)
    }

    private func firstIndex(of word: [UInt16], from start: Int) -> Int? {
        var index = start
        while index + word.count <= count {
            guard let candidate = units[index...].firstIndex(of: word[0]), candidate + word.count <= count else { return nil }
            if hasPrefix(word, at: candidate) { return candidate }
            index = candidate + 1
        }
        return nil
    }

    private static let directionWord = Array("direction".utf16)
    private static let directionLetters = ["TB", "BT", "RL", "LR"].map { letters in Array(letters.utf16) }
    private static let titleWord = Array("title".utf16)
    private static let accessibilityTitleWord = Array("accTitle".utf16)
    private static let accessibilityDescriptionWord = Array("accDescr".utf16)
}
