/**
 * File: AgentFlowLexerInitial.swift
 * ---------------------------------
 * Layer: Core
 * Description: The rules of an agent flow's initial start condition, in Pele's order: keywords, direction statements,
 *              link identifiers, numbers, punctuation, white space, node strings and Unicode letters.
 *
 * Authors: Bahey Shalash
 * Version: 0.2
 * Date: 26/11/2026
 */

extension AgentFlowLexer {
    private typealias Unit = AgentFlowCharacter

    mutating func readInitial(_ character: Int) -> Bool {
        if readKeyword(character) { return true }
        if readDirectionStatement() { return true }
        if readLinkIdentifier(character) { return true }
        if Unit.isDigit(character) {
            var end = position + 1
            while Unit.isDigit(self.character(at: end)) { end += 1 }
            emitFlat(.number, to: end)
            return true
        }
        if let read = readPunctuation(character) { return read }
        if Unit.isSpace(character) {
            readWhitespace(character)
            return true
        }
        if character < 128 { return readNodeString() }
        if Unit.isUnicodeLetter(character) {
            emitFlat(.unicodeText, to: position + characterLength(at: position))
            return true
        }
        return false
    }

    // MARK: - Keywords

    /// The rules that start with a keyword's first letter, as Pele's first switch tries them.
    private mutating func readKeyword(_ character: Int) -> Bool {
        switch character {
        case 97: return readAccessibilityStatement() || readGraphKeyword()
        case Unit.commercialAt:
            guard self.character(at: position + 1) == Unit.openingBrace else { return false }
            push(.shapeData)
            emitShapeData(textFrom: derived.count, to: position + 2)
            return true
        case 99: return readCallOrClick()
        case Unit.quotationMark:
            readQuotationMark()
            return true
        case 115: return readFlatKeyword(Self.styleWord, as: .style)
        case 100: return readFlatKeyword(Self.defaultWord, as: .defaultKeyword)
        case 108: return readFlatKeyword(Self.linkStyleWord, as: .linkStyle)
        case 105: return readFlatKeyword(Self.interpolateWord, as: .interpolate)
        case 104:
            guard startsWith(Self.hyperlinkWord, at: position), Unit.isSpace(self.character(at: position + 4)) else { return false }
            emit(.hyperlinkReference, to: position + 5)
            return true
        case 102: return readFlatKeyword(Self.flowWord, as: .flow)
        case 103:
            guard isKeyword(Self.globalWord) else { return false }
            emitFlat(.global, to: blanks(from: position + Self.globalWord.count))
            return true
        case 101:
            guard isKeyword(Self.endWord) else { return false }
            emitFlat(.endKeyword, to: blanks(from: position + Self.endWord.count))
            return true
        case Unit.lowLine:
            for target in Self.linkTargetWords where isKeyword(target) {
                emitFlat(.linkTarget, to: position + target.count)
                return true
            }
            return false
        default: return false
        }
    }

    private mutating func readFlatKeyword(_ word: [UInt8], as kind: AgentFlowTokenKind) -> Bool {
        guard isKeyword(word) else { return false }
        emitFlat(kind, to: position + word.count)
        return true
    }

    /// `accTitle:`, `accDescr:` and `accDescr {`, each with the white space around its separator.
    private mutating func readAccessibilityStatement() -> Bool {
        guard startsWith(Self.accessibilityPrefix, at: position) else { return false }
        if let end = endOfWord(Self.accessibilityTitleWord, separator: Unit.colon) {
            push(.accessibilityTitle)
            emit(.accessibilityTitle, to: end)
            return true
        }
        if let end = endOfWord(Self.accessibilityDescriptionWord, separator: Unit.colon) {
            push(.accessibilityDescription)
            emit(.accessibilityDescription, to: end)
            return true
        }
        if let end = endOfWord(Self.accessibilityDescriptionWord, separator: Unit.openingBrace) {
            push(.accessibilityDescriptionMultiline)
            advance(to: end)
            return true
        }
        return false
    }

    /// `agentflow-beta`; the first one is followed by its direction.
    private mutating func readGraphKeyword() -> Bool {
        guard isKeyword(Self.graphWord) else { return false }
        if isFirstGraph {
            isFirstGraph = false
            push(.direction)
        }
        emitFlat(.graph, to: position + Self.graphWord.count)
        return true
    }

    /// `call` and white space (a callback), `classDef`, `class`, `click` and white space, and `connector`.
    private mutating func readCallOrClick() -> Bool {
        if let end = endOfWordAndSpace(Self.callWord) {
            push(.callbackName)
            advance(to: end)
            return true
        }
        if readFlatKeyword(Self.classDefinitionWord, as: .classDefinition) || readFlatKeyword(Self.classWord, as: .classKeyword) { return true }
        if let end = endOfWordAndSpace(Self.clickWord) {
            push(.click)
            advance(to: end)
            return true
        }
        return readFlatKeyword(Self.connectorWord, as: .connector)
    }

    /// The end of `word\s*` then `separator` then `\s*` at the position, or nil.
    private mutating func endOfWord(_ word: [UInt8], separator: Int) -> Int? {
        guard startsWith(word, at: position) else { return nil }
        let separatorAt = whitespaceEnd(from: position + word.count)
        guard character(at: separatorAt) == separator else { return nil }
        return whitespaceEnd(from: separatorAt + 1)
    }

    /// The end of `word\s+` at the position, or nil.
    private mutating func endOfWordAndSpace(_ word: [UInt8]) -> Int? {
        guard startsWith(word, at: position), Unit.isSpace(character(at: position + word.count)) else { return nil }
        return whitespaceEnd(from: position + word.count)
    }

    static let accessibilityPrefix = Array("acc".utf8)
    static let accessibilityTitleWord = Array("accTitle".utf8)
    static let accessibilityDescriptionWord = Array("accDescr".utf8)
    static let graphWord = Array("agentflow-beta".utf8)
    static let callWord = Array("call".utf8)
    static let classDefinitionWord = Array("classDef".utf8)
    static let classWord = Array("class".utf8)
    static let clickWord = Array("click".utf8)
    static let connectorWord = Array("connector".utf8)
    static let styleWord = Array("style".utf8)
    static let defaultWord = Array("default".utf8)
    static let linkStyleWord = Array("linkStyle".utf8)
    static let interpolateWord = Array("interpolate".utf8)
    static let hyperlinkWord = Array("href".utf8)
    static let flowWord = Array("flow".utf8)
    static let globalWord = Array("global".utf8)
    static let endWord = Array("end".utf8)
    static let linkTargetWords = ["_self", "_blank", "_parent", "_top"].map { word in Array(word.utf8) }
}
