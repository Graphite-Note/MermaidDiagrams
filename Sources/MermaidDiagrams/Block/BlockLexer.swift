/**
 * File: BlockLexer.swift
 * ----------------------
 * Layer: Core
 * Description: Reads a block diagram's text into tokens as Pele's block lexer does, the states of Mermaid's
 *              block.jison: strings, shapes, arrows, links and their text, classes and styles to the end of their line.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 19/11/2026
 */

/// A token of a block diagram, Pele's `T` (`tokens.ts`).
enum BlockTokenKind: Equatable {
    case keyword, compositeKeyword, columns, markdownString, string, space, defaultKeyword, linkStyle, interpolate
    case classDefinition, defaultClassDefinitionIdentifier, classDefinitionIdentifier, classDefinitionStyles
    case classAssignment, classAssignmentIdentifiers, classAssignmentName, style, styleIdentifiers, styleDeclarations
    case accessibilityTitle, accessibilityTitleValue, accessibilityDescription, accessibilityDescriptionValue
    case accessibilityDescriptionBlockValue
    case end, nodeStart, nodeEnd, arrowStart, arrowEnd, direction, nodeIdentifier, link, startLink, linkLabel, size
    case endOfText
    /// Text no rule reads, where the lexer stopped.
    case unrecognized
    /// After the last token.
    case finished
}

/// One token: its kind, its text and where it starts in the text's bytes.
struct BlockToken {
    let kind: BlockTokenKind
    let text: String
    let start: Int
}

/// Pele's block lexer (`lexer.ts`) over UTF-8 bytes: a state machine whose states are Mermaid's, entered and left on a
/// stack, every token read in one pass. Text it does not read ends the tokens with `unrecognized`, which the parser
/// reports when it reaches it.
struct BlockLexer {
    enum State {
        case initial, string, markdownString, node, blockArrow, arrowDirection, linkLabel, classDefinition
        case classDefinitionIdentifier, classAssignment, classAssignmentStyle, styleStatement, styleDefinition
        case accessibilityTitle, accessibilityDescription, accessibilityDescriptionBlock
    }

    let bytes: [UInt8]
    var position: Int
    var state = State.initial
    var stack: [State] = []
    var tokens: [BlockToken] = []

    /// The tokens of `bytes` from `start`, ending with `endOfText` and `finished`, or with `unrecognized` and `finished`.
    static func tokens(of bytes: [UInt8], from start: Int) -> [BlockToken] {
        var lexer = BlockLexer(bytes: bytes, position: start)
        lexer.run()
        return lexer.tokens
    }

    private mutating func run() {
        while true {
            guard position < bytes.count else {
                if let kind = endOfTextKind { put(kind, "", end: bytes.count) }
                break
            }
            if !step(bytes[position]) {
                tokens.append(BlockToken(kind: .unrecognized, text: "", start: position))
                break
            }
        }
        tokens.append(BlockToken(kind: .finished, text: "", start: bytes.count))
    }

    /// The token the text's end gives in the current state, Pele's table at `p >= n`.
    private var endOfTextKind: BlockTokenKind? {
        switch state {
        case .initial: .endOfText
        case .string: .string
        case .classDefinitionIdentifier: .classDefinitionStyles
        case .classAssignmentStyle: .classAssignmentName
        case .styleDefinition: .styleDeclarations
        case .accessibilityTitle: .accessibilityTitleValue
        case .accessibilityDescription: .accessibilityDescriptionValue
        case .accessibilityDescriptionBlock: .accessibilityDescriptionBlockValue
        default: nil
        }
    }

    /// One step in the current state at `byte`; false where nothing is read.
    private mutating func step(_ byte: UInt8) -> Bool {
        switch state {
        case .initial: return initial(byte)
        case .string: readString(byte)
        case .markdownString: return readMarkdownString(byte)
        case .node: return nodeEnd(byte)
        case .blockArrow: return blockArrow(byte)
        case .arrowDirection: return arrowDirection(byte)
        case .linkLabel: return linkLabel(byte)
        case .classDefinition: return classDefinitionName()
        case .classDefinitionIdentifier: restOfLine(.classDefinitionStyles)
        case .classAssignment: return identifierList(.classAssignmentIdentifiers, next: .classAssignmentStyle)
        case .classAssignmentStyle: restOfLine(.classAssignmentName)
        case .styleStatement: return identifierList(.styleIdentifiers, next: .styleDefinition)
        case .styleDefinition: restOfLine(.styleDeclarations)
        case .accessibilityTitle: restOfLine(.accessibilityTitleValue)
        case .accessibilityDescription: restOfLine(.accessibilityDescriptionValue)
        case .accessibilityDescriptionBlock: readDescriptionBlock(byte)
        }
        return true
    }

    // MARK: Pele's helpers

    func byte(at index: Int) -> UInt8? {
        index >= 0 && index < bytes.count ? bytes[index] : nil
    }

    func isWord(at index: Int) -> Bool {
        byte(at: index).map(PlaneMapByte.isWord) ?? false
    }

    func hasPrefix(_ literal: String, at index: Int) -> Bool {
        var at = index
        for expected in literal.utf8 {
            guard byte(at: at) == expected else { return false }
            at += 1
        }
        return true
    }

    /// `literal` at the position, not followed by a word character.
    func isKeyword(_ literal: String) -> Bool {
        hasPrefix(literal, at: position) && !isWord(at: position + literal.utf8.count)
    }

    /// After the run of white space (`\s`) from `index`.
    func skippingWhitespace(from index: Int) -> Int {
        JavaScriptWhitespace.endOfRun(in: bytes, from: index)
    }

    func skippingDigits(from index: Int) -> Int {
        var end = index
        while let next = byte(at: end), PlaneMapByte.isDigit(next) { end += 1 }
        return end
    }

    func skippingWord(from index: Int) -> Int {
        var end = index
        while isWord(at: end) { end += 1 }
        return end
    }

    func text(from start: Int, to end: Int) -> String {
        String(decoding: bytes[start..<end], as: UTF8.self)
    }

    /// Pele's `put`: a token of `text` starting at the position, which then moves to `end`.
    mutating func put(_ kind: BlockTokenKind, _ text: String, end: Int) {
        tokens.append(BlockToken(kind: kind, text: text, start: position))
        position = end
    }

    /// Pele's `emit`: a token of the text from the position to `end`.
    mutating func emit(_ kind: BlockTokenKind, end: Int) {
        put(kind, text(from: position, to: end), end: end)
    }

    mutating func push(_ next: State) {
        stack.append(state)
        state = next
    }

    mutating func pop() {
        if let previous = stack.popLast() { state = previous }
    }

    /// A string opens: a Markdown one after `"` and a backtick.
    mutating func openQuotation() {
        if byte(at: position + 1) == BlockByte.backtick {
            push(.markdownString)
            position += 2
        } else {
            push(.string)
            position += 1
        }
    }

    // MARK: The states that read to a delimiter

    private mutating func readString(_ current: UInt8) {
        if current == PlaneMapByte.quotationMark {
            pop()
            position += 1
        } else {
            emit(.string, end: bytes[position...].firstIndex(of: PlaneMapByte.quotationMark) ?? bytes.count)
        }
    }

    private mutating func readMarkdownString(_ current: UInt8) -> Bool {
        if current == BlockByte.backtick {
            guard byte(at: position + 1) == PlaneMapByte.quotationMark else { return false }
            pop()
            position += 2
            return true
        }
        guard current != PlaneMapByte.quotationMark else { return false }
        var end = position + 1
        while let next = byte(at: end), next != BlockByte.backtick, next != PlaneMapByte.quotationMark { end += 1 }
        emit(.markdownString, end: end)
        return true
    }

    private mutating func readDescriptionBlock(_ current: UInt8) {
        if current == PlaneMapByte.closingBrace {
            pop()
            position += 1
        } else {
            emit(.accessibilityDescriptionBlockValue, end: bytes[position...].firstIndex(of: PlaneMapByte.closingBrace) ?? bytes.count)
        }
    }

    /// Pele's `lineState`: the rest of the line, then the state before.
    private mutating func restOfLine(_ kind: BlockTokenKind) {
        let end = bytes[position...].firstIndex(of: PlaneMapByte.lineFeed) ?? bytes.count
        pop()
        emit(kind, end: end)
    }

    /// Pele's `idList`: `\w+(,\s*\w+)*`, then `next`.
    private mutating func identifierList(_ kind: BlockTokenKind, next: State) -> Bool {
        var end = skippingWord(from: position)
        guard end > position else { return false }
        while byte(at: end) == PlaneMapByte.comma {
            let from = skippingWhitespace(from: end + 1)
            let to = skippingWord(from: from)
            if to == from { break }
            end = to
        }
        state = next
        emit(kind, end: end)
        return true
    }

    /// After `classDef `: `DEFAULT` and white space, or a word and white space.
    private mutating func classDefinitionName() -> Bool {
        var kind = BlockTokenKind.defaultClassDefinitionIdentifier
        var end = hasPrefix("DEFAULT", at: position) ? position + 7 : position
        var after = skippingWhitespace(from: end)
        if end == position || after == end {
            kind = .classDefinitionIdentifier
            end = skippingWord(from: position)
            after = skippingWhitespace(from: end)
        }
        guard end > position, after > end else { return false }
        state = .classDefinitionIdentifier
        emit(kind, end: after)
        return true
    }
}

/// The bytes the block lexer tests beyond `PlaneMapByte`'s.
enum BlockByte {
    static let backtick = UInt8(ascii: "`")
    static let equals = UInt8(ascii: "=")
    static let pipe = UInt8(ascii: "|")
    static let letterX = UInt8(ascii: "x")
    static let letterO = UInt8(ascii: "o")
}
