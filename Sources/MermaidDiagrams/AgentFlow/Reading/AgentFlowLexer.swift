/**
 * File: AgentFlowLexer.swift
 * --------------------------
 * Layer: Core
 * Description: Reads an agent flow's text into tokens as Pele's lexer.ts does, the lexer Jison compiles from Mermaid's
 *              agentflow.jison: its start conditions, its stack of them, and Jison's way of counting lines and columns,
 *              on the text's UTF-8 bytes.
 *
 * Authors: Bahey Shalash
 * Version: 0.4
 * Date: 26/11/2026
 */

/// Reads an agent flow's tokens on the UTF-8 bytes of its prepared text, as Pele reads them on UTF-16 code units with
/// `charCodeAt`: a rule that tests one character tests the character a byte starts (`character(at:)`), so a character
/// beyond ASCII is one character as it is one code unit, and the lines and columns are counted in UTF-16 code units,
/// as Jison counts them (a character beyond the Basic Multilingual Plane counts two). Each step consumes text or
/// changes the start condition, and every search that could run far keeps where it ended (the last run of white space,
/// the next `direction` and `@`, the line on which no direction statement starts), so the work grows with the text's
/// length. A character the current condition has no rule for ends the tokens with an error token.
struct AgentFlowLexer {
    enum StartCondition {
        case initial, string, markdownString, accessibilityTitle, accessibilityDescription, accessibilityDescriptionMultiline
        case direction, text, ellipseText, trapezoidText, edgeText, click, callbackName, callbackArguments, shapeData, shapeDataString
    }

    let bytes: [UInt8]
    /// Whether every byte is ASCII: a column then moves by one for each byte.
    let isASCII: Bool
    var tokens: AgentFlowTokens
    /// The texts made for tokens whose text is not their bytes, which follow the prepared text's bytes.
    var derived: [UInt8] = []
    var stack: ScratchList<StartCondition>
    var condition = StartCondition.initial
    var position = 0
    var line: Int32 = 1
    var column: Int32 = 0
    var isFirstGraph = true
    /// Where the next `direction` and `@` are (-1 for none), the end of the line being read, and where the line ends
    /// on which no direction statement starts.
    var nextDirection: Int
    var nextCommercialAt: Int
    var lineEnd = -1
    var directionFailedBefore = 0
    /// The run of characters without space or quotation mark being read, and its last `@` that names a link, or -1.
    var runEnd = 0
    var runLinkIdentifierEnd = -1
    var whitespaceRun = (from: -1, to: -1)
    var blankRun = (from: -1, to: -1)
    /// Where a link or an arrow was last found not to start, after white space.
    var noLinkAt = -1
    var noArrowAt = -1

    /// The tokens of the prepared text's `bytes`, in `arena`, and the texts made for some of them, which are to follow
    /// the bytes.
    static func tokens(of bytes: [UInt8], isASCII: Bool, arena: DiagramScratchArena) -> (tokens: AgentFlowTokens, derived: [UInt8]) {
        var lexer = AgentFlowLexer(bytes: bytes, isASCII: isASCII, arena: arena)
        lexer.run()
        return (lexer.tokens, lexer.derived)
    }

    private init(bytes: [UInt8], isASCII: Bool, arena: DiagramScratchArena) {
        self.bytes = bytes
        self.isASCII = isASCII
        // About one token for every two or three bytes: room for them is made once.
        tokens = AgentFlowTokens(arena: arena, capacity: bytes.count / 2 + 16)
        stack = arena.list(capacity: 8)
        nextDirection = Self.firstIndex(of: Self.directionWord, in: bytes, from: 0) ?? -1
        nextCommercialAt = bytes.firstIndex(of: UInt8(AgentFlowCharacter.commercialAt)) ?? -1
    }

    var count: Int { bytes.count }

    private mutating func run() {
        while true {
            guard position < count else {
                emitFinalToken()
                break
            }
            guard step(character(at: position)) else {
                appendBounds(.error, start: position, end: position)
                return
            }
        }
        appendBounds(.end, start: count, end: count)
    }

    /// A token that covers nothing, at the current line and column.
    private mutating func appendBounds(_ kind: AgentFlowTokenKind, start: Int, end: Int) {
        tokens.records.append(AgentFlowToken(kind: kind, start: Int32(truncatingIfNeeded: start), end: Int32(truncatingIfNeeded: end), firstLine: line,
                                             firstColumn: column, lastLine: line, lastColumn: column))
    }

    /// What Jison returns when the text runs out in each start condition.
    private mutating func emitFinalToken() {
        let kind: AgentFlowTokenKind? = switch condition {
        case .initial: .endOfFile
        case .accessibilityTitle: .accessibilityTitleValue
        case .accessibilityDescription: .accessibilityDescriptionValue
        case .accessibilityDescriptionMultiline: .accessibilityDescriptionMultilineValue
        case .click: .click
        case .callbackName: .callbackName
        case .callbackArguments: .callbackArguments
        default: nil
        }
        if let kind { emitFlat(kind, to: count) }
    }

    /// One rule of the current start condition; false when it has none for the character.
    private mutating func step(_ character: Int) -> Bool {
        switch condition {
        case .initial: return readInitial(character)
        case .string: readString(character)
        case .markdownString: return readMarkdownString(character)
        case .accessibilityTitle, .accessibilityDescription: readAccessibilityValue()
        case .accessibilityDescriptionMultiline: readMultilineDescription(character)
        case .direction: return readDirectionCondition(character)
        case .text: return readText(character)
        case .ellipseText: return readEllipseText(character)
        case .trapezoidText: return readTrapezoidText(character)
        case .edgeText: return readEdgeText(character)
        case .click: readClick(character)
        case .callbackName: readCallbackName(character)
        case .callbackArguments: readCallbackArguments(character)
        case .shapeData: return readShapeData(character)
        case .shapeDataString: readShapeDataString(character)
        }
        return true
    }

    mutating func push(_ next: StartCondition) {
        stack.append(condition)
        condition = next
    }

    mutating func pop() {
        if let previous = stack.popLast() { condition = previous }
    }

    /// Whether `word` starts at the position and no word character follows it.
    func isKeyword(_ word: [UInt8]) -> Bool {
        startsWith(word, at: position) && !AgentFlowCharacter.isWord(character(at: position + word.count))
    }

    func startsWith(_ word: [UInt8], at index: Int) -> Bool {
        guard index >= 0, index + word.count <= count else { return false }
        for offset in word.indices where bytes[index + offset] != word[offset] { return false }
        return true
    }

    /// Where `word` first starts at `start` or after it, or nil: each place its first byte is found, compared there.
    static func firstIndex(of word: [UInt8], in bytes: [UInt8], from start: Int) -> Int? {
        guard let first = word.first, start >= 0, start < bytes.count else { return nil }
        let lastStart = bytes.count - word.count
        var index = start
        while index <= lastStart {
            guard let found = bytes[index...lastStart].firstIndex(of: first) else { return nil }
            var offset = 1
            while offset < word.count, bytes[found + offset] == word[offset] { offset += 1 }
            if offset == word.count { return found }
            index = found + 1
        }
        return nil
    }

    static let directionWord = Array("direction".utf8)
}
