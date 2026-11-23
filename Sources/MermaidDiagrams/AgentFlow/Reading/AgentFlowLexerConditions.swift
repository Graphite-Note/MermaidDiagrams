/**
 * File: AgentFlowLexerConditions.swift
 * ------------------------------------
 * Layer: Core
 * Description: The start conditions of an agent flow's lexer other than the initial one and the node texts: strings,
 *              accessibility values, the direction after the keyword, clicks and callbacks, and metadata.
 *
 * Authors: Bahey Shalash
 * Version: 0.2
 * Date: 23/11/2026
 */

extension AgentFlowLexer {
    private typealias Unit = AgentFlowCharacter

    /// Inside `"…"`: the text up to the next quotation mark, which ends the string or, before a backtick, opens a
    /// Markdown string.
    mutating func readString(_ character: Int) {
        guard character == Unit.quotationMark else {
            emit(.string, to: index(of: Unit.quotationMark, from: position) ?? count)
            return
        }
        if self.character(at: position + 1) == Unit.graveAccent {
            push(.markdownString)
            advance(to: position + 2)
        } else {
            pop()
            advance(to: position + 1)
        }
    }

    /// Inside `` "`…`" ``: the text up to a backtick or a quotation mark.
    mutating func readMarkdownString(_ character: Int) -> Bool {
        if character == Unit.graveAccent {
            guard self.character(at: position + 1) == Unit.quotationMark else { return false }
            pop()
            advance(to: position + 2)
        } else if character == Unit.quotationMark {
            readQuotationMark()
        } else {
            var end = position + 1
            while end < count, Int(units[end]) != Unit.graveAccent, Int(units[end]) != Unit.quotationMark { end += 1 }
            emit(.markdownString, to: end)
        }
        return true
    }

    /// The rest of the line after `accTitle:` or `accDescr:`.
    mutating func readAccessibilityValue() {
        let kind: AgentFlowTokenKind = condition == .accessibilityTitle ? .accessibilityTitleValue : .accessibilityDescriptionValue
        pop()
        emit(kind, to: index(of: Unit.lineFeed, from: position) ?? count)
    }

    /// Inside `accDescr { … }`: the text up to the closing brace.
    mutating func readMultilineDescription(_ character: Int) {
        if character == Unit.closingBrace {
            pop()
            advance(to: position + 1)
        } else {
            emit(.accessibilityDescriptionMultilineValue, to: index(of: Unit.closingBrace, from: position) ?? count)
        }
    }

    /// After the first `agentflow-beta`: a line break (no direction), a direction, or a bracket.
    mutating func readDirectionCondition(_ character: Int) -> Bool {
        if character == Unit.quotationMark {
            readQuotationMark()
            return true
        }
        if let end = noDirectionEnd() {
            pop()
            emit(.noDirection, to: end)
            return true
        }
        if let end = directionEnd() {
            pop()
            emit(.direction, to: end)
            return true
        }
        return readOpener(character)
    }

    /// The end of `(?:\r?\n)*\s*\n`: the white space from the position through its last line feed, or nil.
    private mutating func noDirectionEnd() -> Int? {
        let end = whitespaceEnd(from: position)
        var index = end - 1
        while index >= position {
            if Int(units[index]) == Unit.lineFeed { return index + 1 }
            index -= 1
        }
        return nil
    }

    /// The end of `\s*(?:LR|RL|TB|BT|TD|BR)\b`, `\s*[<>^]` or `\s*v\b`, or nil.
    private mutating func directionEnd() -> Int? {
        let start = whitespaceEnd(from: position)
        let first = character(at: start)
        let second = character(at: start + 1)
        if first >= 0, second >= 0, Self.directionPairs.contains([UInt16(first), UInt16(second)]), !Unit.isWord(character(at: start + 2)) {
            return start + 2
        }
        if first == Unit.lessThan || first == Unit.greaterThan || first == Unit.circumflex { return start + 1 }
        if first == Unit.lowercaseV, !Unit.isWord(second) { return start + 1 }
        return nil
    }

    /// After `click` and white space: the node's identifier up to white space, or a quoted string.
    mutating func readClick(_ character: Int) {
        if character == Unit.quotationMark {
            readQuotationMark()
        } else if Unit.isSpace(character) {
            pop()
            advance(to: position + 1)
        } else {
            var end = position + 1
            while end < count, !Unit.isSpace(Int(units[end])) { end += 1 }
            emitFlat(.click, to: end)
        }
    }

    /// After `call`: the callback's name up to its parenthesis, then `()` or its arguments.
    mutating func readCallbackName(_ character: Int) {
        guard character == Unit.openingParenthesis else {
            emit(.callbackName, to: index(of: Unit.openingParenthesis, from: position) ?? count)
            return
        }
        let afterSpace = whitespaceEnd(from: position + 1)
        pop()
        if self.character(at: afterSpace) == Unit.closingParenthesis {
            advance(to: afterSpace + 1)
        } else {
            push(.callbackArguments)
            advance(to: position + 1)
        }
    }

    mutating func readCallbackArguments(_ character: Int) {
        if character == Unit.closingParenthesis {
            pop()
            advance(to: position + 1)
        } else {
            emit(.callbackArguments, to: index(of: Unit.closingParenthesis, from: position) ?? count)
        }
    }

    /// Inside `@{ … }`: text up to `}`, `^` (refused) or a quotation mark, which opens a quoted string.
    mutating func readShapeData(_ character: Int) -> Bool {
        if character == Unit.quotationMark {
            push(.shapeDataString)
            emitFlat(.shapeData, to: position + 1)
        } else if character == Unit.closingBrace {
            pop()
            advance(to: position + 1)
        } else if character == Unit.circumflex {
            return false
        } else {
            var end = position + 1
            while end < count, Int(units[end]) != Unit.closingBrace, Int(units[end]) != Unit.circumflex, Int(units[end]) != Unit.quotationMark { end += 1 }
            emit(.shapeData, to: end)
        }
        return true
    }

    /// A quoted string inside `@{ … }`: its text with each line break and the white space after it made `<br/>`.
    mutating func readShapeDataString(_ character: Int) {
        if character == Unit.quotationMark {
            pop()
            emitFlat(.shapeData, to: position + 1)
            return
        }
        let end = index(of: Unit.quotationMark, from: position) ?? count
        var text = ""
        var index = position
        while index < end {
            if Int(units[index]) == Unit.lineFeed {
                text += "<br/>"
                index += 1
                while index < end, Unit.isSpace(Int(units[index])) { index += 1 }
            } else {
                var runEnd = index
                while runEnd < end, Int(units[runEnd]) != Unit.lineFeed { runEnd += 1 }
                text += UnicodeScalarText.string(utf16: units[index..<runEnd])
                index = runEnd
            }
        }
        emit(.shapeData, text: text, to: end)
    }

    func index(of character: Int, from start: Int) -> Int? {
        var index = start
        while index < count {
            if Int(units[index]) == character { return index }
            index += 1
        }
        return nil
    }

    static let directionPairs: Set<[UInt16]> = Set(["LR", "RL", "TB", "BT", "TD", "BR"].map { pair in Array(pair.utf16) })
}
