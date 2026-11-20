/**
 * File: UseCaseLexer.swift
 * ------------------------
 * Layer: Core
 * Description: Produces the tokens of Mermaid's Chevrotain lexer for use case diagrams as Pele's lexer.ts does, step
 *              for step on UTF-16 code units: words and keywords, strings, comments and accessibility lines.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 19/11/2026
 */

/// A use case diagram's tokens: each one's kind and where it starts and ends (end exclusive), in code units, followed
/// by three end tokens so that the parser may look three tokens ahead.
struct UseCaseTokens {
    var kinds: [UseCaseTokenKind] = []
    var starts: [Int] = []
    var ends: [Int] = []

    mutating func append(_ kind: UseCaseTokenKind, from start: Int, to end: Int) {
        kinds.append(kind)
        starts.append(start)
        ends.append(end)
    }
}

/// Mermaid's lexer for use case diagrams, as Pele ports it: the first pattern of its list that matches wins, a keyword
/// gives way to a longer identifier, and `json id@` and `<<` switch to reading a JSON object and a stereotype. Each
/// construct is read once from where it starts, so that no text makes it scan again from every character.
struct UseCaseLexer {
    /// Text no token starts with, by the offset of its first character.
    struct Failure: Error, Equatable {
        let offset: Int
    }

    let text: UseCaseCharacters
    var tokens = UseCaseTokens()
    var position = 0
    /// Whether only blanks came before on this line, where comments and accessibility lines may start.
    var isAtLineStart = true
    /// Whether an `accDescr {` found no closing brace, so that later ones do not look again.
    var hasNoClosingBrace = false

    static func tokens(of text: UseCaseCharacters) throws(Failure) -> UseCaseTokens {
        var lexer = UseCaseLexer(text: text)
        try lexer.readAll()
        for _ in 0..<3 { lexer.tokens.append(.end, from: text.count, to: text.count) }
        return lexer.tokens
    }

    private mutating func readAll() throws(Failure) {
        while position < text.count {
            let unit = text.units[position]
            if unit == 0x20 || unit == 0x09 {
                position += 1
                continue
            }
            if UseCaseCharacters.isWord(unit) {
                if try readWordConstruct(unit) { continue }
                let end = readWord(unit)
                finish(end.kind, to: end.end)
                continue
            }
            guard let (kind, end) = try readSymbol(unit) else { return }
            finish(kind, to: end, endsLine: kind == .newline)
        }
    }

    private mutating func finish(_ kind: UseCaseTokenKind, to end: Int, endsLine: Bool = false) {
        tokens.append(kind, from: position, to: end)
        position = end
        isAtLineStart = endsLine
    }

    /// An accessibility line or block, or a JSON declaration and its object, at a word: whether one was read.
    private mutating func readWordConstruct(_ unit: UInt16) throws(Failure) -> Bool {
        if unit == UInt16(ascii: "a"), isAtLineStart, text.starts(with: "acc", at: position) {
            guard let (kind, end) = accessibilityStatement() else { return false }
            finish(kind, to: end)
            return true
        }
        if unit == UInt16(ascii: "j"), text.starts(with: "json", at: position), UseCaseCharacters.isBlank(text[position + 4]) {
            return readJSONDeclaration()
        }
        return false
    }

    /// `accTitle:` or `accDescr:` to the end of the line, or `accDescr {` to its closing brace.
    private mutating func accessibilityStatement() -> (UseCaseTokenKind, Int)? {
        let isDescription = text.starts(with: "Descr", at: position + 3)
        guard isDescription || text.starts(with: "Title", at: position + 3) else { return nil }
        var index = position + 8
        while UseCaseCharacters.isBlank(text[index]) { index += 1 }
        if text[index] == UInt16(ascii: ":") {
            return (isDescription ? .accessibilityDescriptionLine : .accessibilityTitleLine, text.lineEnd(from: index + 1))
        }
        guard text[index] == UInt16(ascii: "{"), isDescription, !hasNoClosingBrace else { return nil }
        var close = index + 1
        while close < text.count, text.units[close] != UInt16(ascii: "}") { close += 1 }
        guard close < text.count else {
            hasNoClosingBrace = true
            return nil
        }
        return (.accessibilityDescriptionBlock, close + 1)
    }

    /// `json Id @ {`, then its object read to the brace that balances its first, outside strings.
    private mutating func readJSONDeclaration() -> Bool {
        var index = position + 5
        while UseCaseCharacters.isBlank(text[index]) { index += 1 }
        let identifierStart = index
        while UseCaseCharacters.isWord(text[index]) { index += 1 }
        guard index > identifierStart else { return false }
        while UseCaseCharacters.isBlank(text[index]) { index += 1 }
        guard text[index] == UInt16(ascii: "@") else { return false }
        index += 1
        while UseCaseCharacters.isBlank(text[index]) { index += 1 }
        guard text[index] == UInt16(ascii: "{") else { return false }
        tokens.append(.jsonDeclarationStart, from: position, to: index)
        position = index
        let close = Self.balancedBrace(in: text, from: index)
        let end = close.map { close in close + 1 } ?? text.count
        finish(close == nil ? .unclosedJSONObjectLiteral : .jsonObjectLiteral, to: end)
        return true
    }

    /// The brace that closes the one at `start`, braces inside strings not counted, or nil.
    private static func balancedBrace(in text: UseCaseCharacters, from start: Int) -> Int? {
        var depth = 0
        var isQuoted = false
        var isEscaped = false
        for index in start..<text.count {
            let unit = text.units[index]
            if isQuoted {
                if isEscaped { isEscaped = false } else if unit == 0x5C { isEscaped = true } else if unit == 0x22 { isQuoted = false }
            } else if unit == 0x22 {
                isQuoted = true
            } else if unit == UInt16(ascii: "{") {
                depth += 1
            } else if unit == UInt16(ascii: "}") {
                depth -= 1
                if depth == 0 { return index }
            }
        }
        return nil
    }

    /// A keyword, an identifier, a number, or `o--` and `x--`, from a word character.
    private func readWord(_ unit: UInt16) -> (kind: UseCaseTokenKind, end: Int) {
        var end = position + 1
        while UseCaseCharacters.isWord(text[end]) { end += 1 }
        let keyword = text.keyword(at: position)
        if keyword != .end {
            // A keyword that is only the start of a longer word is an identifier.
            if keyword == .useCase || end - position == keyword.keywordLength { return (keyword, position + keyword.keywordLength) }
            return (.identifier, end)
        }
        if unit == UInt16(ascii: "o") || unit == UInt16(ascii: "x"), text[position + 1] == 0x2D, text[position + 2] == 0x2D {
            return (unit == UInt16(ascii: "o") ? .backwardCircle : .backwardCross, position + 3)
        }
        if UseCaseCharacters.isDigit(unit) {
            // `1mg` is an identifier, and `1.5px` a number, as the identifier stops at the point.
            var digits = position + 1
            while UseCaseCharacters.isDigit(text[digits]) { digits += 1 }
            guard text[digits] == UInt16(ascii: "."), UseCaseCharacters.isDigit(text[digits + 1]) else { return (.identifier, end) }
            var numberEnd = digits + 2
            while UseCaseCharacters.isDigit(text[numberEnd]) { numberEnd += 1 }
            while UseCaseCharacters.isLetter(text[numberEnd]) { numberEnd += 1 }
            return (.number, numberEnd)
        }
        var kind = UseCaseTokenKind.identifier
        while text[end] == 0x2D, UseCaseCharacters.isWord(text[end + 1]) {
            kind = .cssIdentifier
            end += 2
            while UseCaseCharacters.isWord(text[end]) { end += 1 }
        }
        return (kind, end)
    }

    /// The token at a character that starts no word, or nil when the text ends after a stereotype's opening.
    private mutating func readSymbol(_ unit: UInt16) throws(Failure) -> (UseCaseTokenKind, Int)? {
        let next = position + 1
        switch unit {
        case 0x0A: return (.newline, next)
        case 0x0D: return (.newline, text[next] == 0x0A ? next + 1 : next)
        case 0x22, 0x27: return try readString(unit)
        case UInt16(ascii: "%"):
            guard isAtLineStart, text[next] == UInt16(ascii: "%") else { return (.percent, next) }
            return (.comment, text.lineEnd(from: next))
        case UInt16(ascii: "-"): return readDashes()
        case UInt16(ascii: "."): return readDot()
        case UInt16(ascii: "<"): return try readAngle()
        case UInt16(ascii: ":"):
            return text[next] == UInt16(ascii: ":") && text[next + 1] == UInt16(ascii: ":") ? (.classSeparator, next + 2) : (.colon, next)
        case UInt16(ascii: "@"): return text[next] == UInt16(ascii: "{") ? (.metadataStart, next + 1) : (.at, next)
        default: return readPunctuation(unit)
        }
    }

    private func readPunctuation(_ unit: UInt16) -> (UseCaseTokenKind, Int) {
        let next = position + 1
        switch unit {
        case UInt16(ascii: "{"): return (.leftBrace, next)
        case UInt16(ascii: "}"): return (.rightBrace, next)
        case UInt16(ascii: "["): return (.leftBracket, next)
        case UInt16(ascii: "]"): return (.rightBracket, next)
        case UInt16(ascii: "("): return (.leftParenthesis, next)
        case UInt16(ascii: ")"): return (.rightParenthesis, next)
        case UInt16(ascii: ","): return (.comma, next)
        case UInt16(ascii: "#"):
            var end = next
            while UseCaseCharacters.isHexadecimal(text[end]) { end += 1 }
            return (end > next ? .hashColor : .cssPunctuation, end)
        case 0x5C: return text[next] == UInt16(ascii: ",") ? (.cssEscapedComma, next + 1) : (.labelPunctuation, next)
        case 33..<127: return (UseCaseCharacters.isCSSPunctuation(unit) ? .cssPunctuation : .labelPunctuation, next)
        default:
            var end = next
            while let following = text[end], !(following >= 32 && following < 127), following != 0x09, following != 0x0A, following != 0x0D { end += 1 }
            return (.labelSymbol, end)
        }
    }
}
