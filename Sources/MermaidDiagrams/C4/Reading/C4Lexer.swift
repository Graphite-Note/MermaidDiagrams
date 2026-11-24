/**
 * File: C4Lexer.swift
 * -------------------
 * Layer: Core
 * Description: Reads a C4 diagram's text into tokens as the lexer Jison compiles from Mermaid's c4Diagram.jison does,
 *              Pele's lexer.ts step for step: its rules in order, its start conditions, and what it returns once the
 *              text runs out in each of them, on the text's UTF-8 bytes.
 *
 * Authors: Bahey Shalash
 * Version: 0.4
 * Date: 24/11/2026
 */

/// Reads a C4 diagram's tokens from its keyword on, on the text's UTF-8 bytes. Pele reads UTF-16 code units, but every
/// character its rules test but white space is ASCII, and a white space character beyond ASCII is taken whole
/// (`JavaScriptWhitespace`), so each token covers the same characters. Every token's text is a range of the text;
/// nothing is copied until the parser asks for it. Each step consumes text, changes the start
/// condition or ends, and each search runs forward from where the last one of its kind ended, so the work grows with the
/// text's length.
struct C4Lexer {
    private enum StartCondition {
        case initial, macro, arguments, string, namedKey, namedKeyEnd, namedValue, accessibilityValue, multilineDescription
    }

    private let bytes: [UInt8]
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

    static func tokens(of bytes: [UInt8]) -> C4Tokens {
        var lexer = C4Lexer(bytes: bytes)
        lexer.run()
        return lexer.tokens
    }

    private init(bytes: [UInt8]) {
        self.bytes = bytes
        // About one token for every four bytes: room for them is made once.
        let expectedTokenCount = bytes.count / 4 + 16
        tokens.kinds.reserveCapacity(expectedTokenCount)
        tokens.starts.reserveCapacity(expectedTokenCount)
        tokens.ends.reserveCapacity(expectedTokenCount)
    }

    private var count: Int { bytes.count }

    /// Jison notes the end of the text one call before it reports it, so a rule that matches nothing gets one last turn.
    private mutating func run() {
        while true {
            if reachedEnd {
                emit(.end, from: count, to: count)
                return
            }
            if position >= count { reachedEnd = true }
            let byte = position < count ? bytes[position] : nil
            guard step(byte) else { return }
        }
    }

    /// One rule of the current start condition; false once the lexer gives up on unrecognized text.
    private mutating func step(_ byte: UInt8?) -> Bool {
        switch condition {
        case .initial: return readInitial(byte)
        case .macro: return readMacroParenthesis(byte)
        case .arguments: readArgument(byte)
        case .string: readStringPart(byte, closing: Self.quotationMark, kind: .string, then: .arguments)
        case .namedKey:
            emit(.namedArgumentKey, from: position, to: upTo(Self.equalsSign, from: position))
            condition = .namedKeyEnd
        case .namedKeyEnd: return readNamedKeyEnd(byte)
        case .namedValue:
            guard byte != nil else { return true }
            readStringPart(byte, closing: Self.quotationMark, kind: .namedArgumentValue, then: .arguments)
        case .accessibilityValue:
            emit(accessibilityValueKind, from: position, to: upTo(Self.lineFeed, from: position))
            condition = .initial
        case .multilineDescription:
            readStringPart(byte, closing: Self.closingBrace, kind: .accessibilityDescriptionMultilineValue, then: .initial)
        }
        return true
    }

    private mutating func readInitial(_ byte: UInt8?) -> Bool {
        guard let byte else {
            emit(.endOfFile, from: count, to: count)
            return true
        }
        if readDirection() { return true }
        if byte == Self.lowercaseT, readBareTitle() || readStatement(Self.titleWord, as: .title) { return true }
        if byte == Self.lowercaseA, readAccessibilityStatement() { return true }
        if byte == Self.percentSign, self.byte(at: position + 1) == Self.percentSign {
            skipComment()
            return true
        }
        if whitespaceLength(at: position) > 0 {
            readWhitespace()
            return true
        }
        if byte == Self.openingBrace || byte == Self.closingBrace {
            emit(byte == Self.openingBrace ? .openingBrace : .closingBrace, from: position, to: position + 1)
            return true
        }
        if C4Characters.isWord(UInt16(byte)), readKeyword() { return true }
        emit(.error, from: position, to: position)
        return false
    }

    // MARK: - The initial condition's rules

    /// `.*direction\s+TB[^\n]*` and the other three directions, tried only on a line that holds `direction`.
    private mutating func readDirection() -> Bool {
        guard nextDirection != -1, position >= directionFailedBefore else { return false }
        if nextDirection < position { nextDirection = firstIndex(of: Self.directionWord, from: position) ?? -1 }
        guard nextDirection != -1 else { return false }
        if lineEnd < position { lineEnd = (position..<count).first { index in isLineTerminator(at: index) } ?? count }
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
    private func directionStatementEnd(_ letters: [UInt8]) -> Int? {
        var start = lineEnd - 1
        while start >= position {
            defer { start -= 1 }
            guard hasPrefix(Self.directionWord, at: start) else { continue }
            let spacesStart = start + Self.directionWord.count
            let after = skipSpaces(from: spacesStart)
            guard after > spacesStart, hasPrefix(letters, at: after) else { continue }
            return upTo(Self.lineFeed, from: after + letters.count)
        }
        return nil
    }

    /// `title`, white space but no line break, then a line break or the end: no title, its white space after it skipped.
    private mutating func readBareTitle() -> Bool {
        guard hasPrefix(Self.titleWord, at: position) else { return false }
        var end = position + Self.titleWord.count
        while end < count, !isLineBreak(bytes[end]), case let length = whitespaceLength(at: end), length > 0 { end += length }
        guard end == count || isLineBreak(bytes[end]) else { return false }
        position = skipSpaces(from: end)
        return true
    }

    /// `word\s[^#\n;]+`: the word, one white space character, and the rest up to a `#`, a line feed or a `;`.
    private mutating func readStatement(_ word: [UInt8], as kind: C4TokenKind) -> Bool {
        var end = position + word.count
        guard hasPrefix(word, at: position), end < count, case let spaceLength = whitespaceLength(at: end), spaceLength > 0 else { return false }
        end += spaceLength
        let valueStart = end
        while end < count, bytes[end] != Self.numberSign, bytes[end] != Self.lineFeed, bytes[end] != Self.semicolon {
            end += 1
        }
        guard end > valueStart else { return false }
        emit(kind, from: position, to: end)
        return true
    }

    /// `accDescription …`, `accTitle:`, `accDescr:` and `accDescr {`.
    private mutating func readAccessibilityStatement() -> Bool {
        if readStatement(Self.accessibilityDescriptionStatementWord, as: .accessibilityDescriptionStatement) { return true }
        let isTitle = hasPrefix(Self.accessibilityTitleWord, at: position)
        guard isTitle || hasPrefix(Self.accessibilityDescriptionWord, at: position) else { return false }
        let mark = skipSpaces(from: position + Self.accessibilityTitleWord.count)
        if byte(at: mark) == Self.colon {
            emit(isTitle ? .accessibilityTitle : .accessibilityDescription, from: position, to: skipSpaces(from: mark + 1))
            accessibilityValueKind = isTitle ? .accessibilityTitleValue : .accessibilityDescriptionValue
            condition = .accessibilityValue
            return true
        }
        guard byte(at: mark) == Self.openingBrace, !isTitle else { return false }
        position = skipSpaces(from: mark + 1)
        condition = .multilineDescription
        return true
    }

    /// A comment takes the line breaks after it, so no line break token follows.
    private mutating func skipComment() {
        var end = upTo(Self.lineFeed, from: position + 2)
        while end < count, isLineBreak(bytes[end]) { end += 1 }
        position = end
    }

    /// A run of white space: a line break token up to its last line feed, or nothing when it holds none.
    private mutating func readWhitespace() {
        var end = position
        var lastLineFeed = -1
        while end < count {
            let byte = bytes[end]
            // ASCII white space is one byte; anything else is measured as JavaScript's `\s` takes it.
            let length = byte == Self.space || (byte >= MermaidByte.tab && byte <= MermaidByte.carriageReturn) ? 1 : byte < 0x80 ? 0 : whitespaceLength(at: end)
            guard length > 0 else { break }
            if byte == Self.lineFeed { lastLineFeed = end }
            end += length
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
        while end < count, C4Characters.isWord(UInt16(bytes[end])) { end += 1 }
        guard end - position <= C4TokenKind.longestKeywordLength,
              let kind = bytes.withUnsafeBufferPointer({ text in C4Keywords.kind(of: UnsafeBufferPointer(rebasing: text[position..<end])) }) else {
            return false
        }
        if kind > .deployment { condition = .macro }
        emit(kind, from: position, to: end)
        return true
    }

    // MARK: - A macro's arguments

    private mutating func readMacroParenthesis(_ byte: UInt8?) -> Bool {
        guard let byte else {
            emit(.endOfFileInMacro, from: count, to: count)
            return true
        }
        if byte == Self.openingParenthesis {
            var next = position + 1
            while self.byte(at: next) == Self.space { next += 1 }
            if self.byte(at: next) == Self.comma { emit(.emptyArgument, from: position, to: next + 1) } else { position += 1 }
            condition = .arguments
            return true
        }
        if byte == Self.closingParenthesis {
            position += 1
            condition = .initial
            return true
        }
        emit(.error, from: position, to: position)
        return false
    }

    private mutating func readArgument(_ byte: UInt8?) {
        guard let byte else { return }
        if byte == Self.closingParenthesis {
            position += 1
            condition = .initial
        } else if byte == Self.comma {
            if self.byte(at: position + 1) == Self.comma { emit(.emptyArgument, from: position, to: position + 2) } else { position += 1 }
        } else {
            var start = position
            while self.byte(at: start) == Self.space { start += 1 }
            let first = self.byte(at: start)
            if first == Self.quotationMark {
                if self.byte(at: start + 1) == Self.quotationMark {
                    emit(.emptyArgument, from: position, to: start + 2)
                } else {
                    position = start + 1
                    condition = .string
                }
            } else if first == Self.dollarSign {
                position = start + 1
                condition = .namedKey
            } else {
                // An unquoted value runs to the next comma, through closing parentheses and line breaks.
                emit(.string, from: position, to: upTo(Self.comma, from: position))
            }
        }
    }

    /// After a named argument's key: `=`, spaces, then the opening quotation mark of its value.
    private mutating func readNamedKeyEnd(_ byte: UInt8?) -> Bool {
        guard let byte else { return true }
        var next = position + 1
        if byte == Self.equalsSign { while self.byte(at: next) == Self.space { next += 1 } }
        guard byte == Self.equalsSign, self.byte(at: next) == Self.quotationMark else {
            emit(.error, from: position, to: position)
            return false
        }
        position = next + 1
        condition = .namedValue
        return true
    }

    /// The closing character ends the part and returns to `next`; anything else is text up to it.
    private mutating func readStringPart(_ byte: UInt8?, closing: UInt8, kind: C4TokenKind, then next: StartCondition) {
        if byte == closing {
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

    private func byte(at index: Int) -> UInt8? {
        index >= 0 && index < count ? bytes[index] : nil
    }

    /// The length in bytes of the white space character (JavaScript's `\s`) at `index`, or zero.
    private func whitespaceLength(at index: Int) -> Int {
        JavaScriptWhitespace.length(in: bytes, at: index)
    }

    private func isLineBreak(_ byte: UInt8) -> Bool {
        byte == Self.lineFeed || byte == Self.carriageReturn
    }

    /// A line terminator starts at `index`: a line feed, a carriage return, or U+2028 or U+2029 (`E2 80 A8`, `E2 80 A9`),
    /// what `.` does not match.
    private func isLineTerminator(at index: Int) -> Bool {
        let byte = bytes[index]
        if isLineBreak(byte) { return true }
        return byte == 0xE2 && index + 2 < count && bytes[index + 1] == 0x80 && (bytes[index + 2] == 0xA8 || bytes[index + 2] == 0xA9)
    }

    private func skipSpaces(from start: Int) -> Int {
        JavaScriptWhitespace.endOfRun(in: bytes, from: start)
    }

    /// The index of the next `byte` from `start`, or the end of the text.
    private func upTo(_ byte: UInt8, from start: Int) -> Int {
        guard start < count else { return count }
        return bytes[start...].firstIndex(of: byte) ?? count
    }

    private func hasPrefix(_ word: [UInt8], at start: Int) -> Bool {
        start >= 0 && start + word.count <= count && bytes[start..<(start + word.count)].elementsEqual(word)
    }

    private func firstIndex(of word: [UInt8], from start: Int) -> Int? {
        C4ByteSearch.firstIndex(of: word, in: bytes, from: start)
    }

    private static let directionWord = Array("direction".utf8)
    private static let directionLetters = ["TB", "BT", "RL", "LR"].map { letters in Array(letters.utf8) }
    private static let titleWord = Array("title".utf8)
    private static let accessibilityDescriptionStatementWord = Array("accDescription".utf8)
    private static let accessibilityTitleWord = Array("accTitle".utf8)
    private static let accessibilityDescriptionWord = Array("accDescr".utf8)

    private static let lineFeed = UInt8(ascii: "\n")
    private static let carriageReturn = UInt8(ascii: "\r")
    private static let space = UInt8(ascii: " ")
    private static let quotationMark = UInt8(ascii: "\"")
    private static let numberSign = UInt8(ascii: "#")
    private static let dollarSign = UInt8(ascii: "$")
    private static let percentSign = UInt8(ascii: "%")
    private static let openingParenthesis = UInt8(ascii: "(")
    private static let closingParenthesis = UInt8(ascii: ")")
    private static let comma = UInt8(ascii: ",")
    private static let colon = UInt8(ascii: ":")
    private static let semicolon = UInt8(ascii: ";")
    private static let equalsSign = UInt8(ascii: "=")
    private static let lowercaseA = UInt8(ascii: "a")
    private static let lowercaseT = UInt8(ascii: "t")
    private static let openingBrace = UInt8(ascii: "{")
    private static let closingBrace = UInt8(ascii: "}")
}
