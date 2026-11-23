/**
 * File: AgentFlowLexer.swift
 * --------------------------
 * Layer: Core
 * Description: Reads an agent flow's text into tokens as Pele's lexer.ts does, the lexer Jison compiles from Mermaid's
 *              agentflow.jison: its start conditions, its stack of them, and Jison's way of counting lines and columns.
 *
 * Authors: Bahey Shalash
 * Version: 0.2
 * Date: 23/11/2026
 */

/// Reads an agent flow's tokens on UTF-16 code units, as Pele reads them with `charCodeAt`. Each step consumes text or
/// changes the start condition, and every search that could run far keeps where it ended (the last run of white space,
/// the next `direction` and `@`, the line on which no direction statement starts), so the work grows with the text's
/// length. A character the current condition has no rule for ends the tokens with an error token.
struct AgentFlowLexer {
    enum StartCondition {
        case initial, string, markdownString, accessibilityTitle, accessibilityDescription, accessibilityDescriptionMultiline
        case direction, text, ellipseText, trapezoidText, edgeText, click, callbackName, callbackArguments, shapeData, shapeDataString
    }

    let units: [UInt16]
    var tokens = AgentFlowTokens()
    var stack: [StartCondition] = []
    var condition = StartCondition.initial
    var position = 0
    var line = 1
    var column = 0
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

    static func tokens(of units: [UInt16]) -> AgentFlowTokens {
        var lexer = AgentFlowLexer(units: units)
        lexer.run()
        return lexer.tokens
    }

    private init(units: [UInt16]) {
        self.units = units
        nextDirection = Self.firstIndex(of: Self.directionWord, in: units, from: 0) ?? -1
        nextCommercialAt = units.firstIndex(of: UInt16(AgentFlowCharacter.commercialAt)) ?? -1
    }

    var count: Int { units.count }

    /// The code unit at `index`, or -1 past the end, which no rule matches (JavaScript's NaN).
    func character(at index: Int) -> Int {
        index >= 0 && index < units.count ? Int(units[index]) : -1
    }

    private mutating func run() {
        while true {
            guard position < count else {
                emitFinalToken()
                break
            }
            guard step(character(at: position)) else {
                tokens.kinds.append(.error)
                tokens.starts.append(position)
                tokens.ends.append(position)
                tokens.locations.append(line)
                tokens.locations.append(column)
                tokens.locations.append(line)
                tokens.locations.append(column)
                return
            }
        }
        tokens.kinds.append(.end)
        tokens.starts.append(count)
        tokens.ends.append(count)
        tokens.locations.append(line)
        tokens.locations.append(column)
        tokens.locations.append(line)
        tokens.locations.append(column)
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

    // MARK: - Moving and emitting

    /// Moves over a match to `end`. Jison counts `\r\n`, `\r` and `\n` as one line break each, and after a break its
    /// column stops at the first U+2028 or U+2029.
    mutating func advance(to end: Int) {
        var lastBreak = -1
        var index = position
        while index < end {
            let unit = units[index]
            if unit == 10 {
                line += 1
                lastBreak = index
            } else if unit == 13 {
                if index + 1 < end, units[index + 1] == 10 { index += 1 }
                line += 1
                lastBreak = index
            }
            index += 1
        }
        if lastBreak < 0 {
            column += end - position
        } else {
            var stop = lastBreak + 1
            while stop < end, units[stop] != 0x2028, units[stop] != 0x2029 { stop += 1 }
            column = stop - lastBreak - 1
        }
        position = end
    }

    mutating func emit(_ kind: AgentFlowTokenKind, to end: Int) {
        appendStart(kind, end: end)
        advance(to: end)
        tokens.locations.append(line)
        tokens.locations.append(column)
    }

    /// A token that cannot hold a line break.
    mutating func emitFlat(_ kind: AgentFlowTokenKind, to end: Int) {
        appendStart(kind, end: end)
        column += end - position
        position = end
        tokens.locations.append(line)
        tokens.locations.append(column)
    }

    /// A run Jison matches one character at a time, where `\r\n` counts as two line breaks.
    mutating func emitCharacters(_ kind: AgentFlowTokenKind, to end: Int) {
        appendStart(kind, end: end)
        for index in position..<end {
            if units[index] == 10 || units[index] == 13 {
                line += 1
                column = 0
            } else {
                column += 1
            }
        }
        position = end
        tokens.locations.append(line)
        tokens.locations.append(column)
    }

    /// A token whose text is not the text it covers.
    mutating func emit(_ kind: AgentFlowTokenKind, text: String, to end: Int) {
        tokens.replacedTexts[tokens.count] = text
        emit(kind, to: end)
    }

    private mutating func appendStart(_ kind: AgentFlowTokenKind, end: Int) {
        tokens.kinds.append(kind)
        tokens.starts.append(position)
        tokens.ends.append(end)
        tokens.locations.append(line)
        tokens.locations.append(column)
    }

    mutating func push(_ next: StartCondition) {
        stack.append(condition)
        condition = next
    }

    mutating func pop() {
        if let previous = stack.popLast() { condition = previous }
    }

    /// Whether `word` starts at the position and no word character follows it.
    func isKeyword(_ word: [UInt16]) -> Bool {
        startsWith(word, at: position) && !AgentFlowCharacter.isWord(character(at: position + word.count))
    }

    func startsWith(_ word: [UInt16], at index: Int) -> Bool {
        guard index + word.count <= count else { return false }
        for offset in word.indices where units[index + offset] != word[offset] { return false }
        return true
    }

    static func firstIndex(of word: [UInt16], in units: [UInt16], from start: Int) -> Int? {
        guard let first = word.first, start < units.count else { return nil }
        var index = start
        while index + word.count <= units.count {
            if units[index] == first, units[index..<(index + word.count)].elementsEqual(word) { return index }
            index += 1
        }
        return nil
    }

    static let directionWord = Array("direction".utf16)
}
