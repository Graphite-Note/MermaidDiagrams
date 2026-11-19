/**
 * File: WardleyMapWords.swift
 * ---------------------------
 * Layer: Core
 * Description: The terminals of a Wardley map that start with a letter, a digit or a link's sign, as Pele's WARDLEY_TOKENS
 *              match them: sourcing words, keywords, names with spaces, numbers, identifiers and link arrows.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 19/11/2026
 */

/// Matches the terminals of a Wardley map that start with a letter, a digit or a link's sign, in Pele's order.
enum WardleyMapWords {
    /// The keywords in Pele's order, each matched without regard to what follows it, as Langium's lexer matches them.
    private static let keywords: [(String, WardleyMapTokenKind)] = [
        ("wardley-beta", .wardleyKeyword), ("size", .size), ("evolution", .evolution), ("anchor", .anchor), ("component", .component), ("label", .label),
        ("inertia", .inertia), ("evolve", .evolve), ("pipeline", .pipeline), ("note", .note), ("annotations", .annotations), ("annotation", .annotation),
        ("accelerator", .accelerator), ("deaccelerator", .deaccelerator),
    ]
    private static let sourcingWords = ["build", "buy", "outsource", "market"]

    static func endOfBlanks(in terminals: PlaneMapTerminals, from start: Int) -> Int {
        var end = start
        while let next = terminals.byte(end), PlaneMapByte.isBlank(next) { end += 1 }
        return end
    }

    /// At `+`: a port (`+<>`, `+>`, `+<`), else a labelled arrow (`+'label'<>`, `<` or `>`); at `>`: an arrow.
    static func endOfLink(in terminals: PlaneMapTerminals, at start: Int) -> (WardleyMapTokenKind?, Int)? {
        if terminals.byte(start) == PlaneMapByte.greaterThan { return (.linkArrow, start + 1) }
        for port in ["+<>", "+>", "+<"] where terminals.hasPrefix(port, at: start) { return (.linkPort, start + port.utf8.count) }
        guard terminals.byte(start + 1) == PlaneMapByte.apostrophe else { return nil }
        var index = start + 2
        while let next = terminals.byte(index), next != PlaneMapByte.apostrophe { index += 1 }
        guard terminals.byte(index) == PlaneMapByte.apostrophe else { return nil }
        for ending in ["<>", "<", ">"] where terminals.hasPrefix(ending, at: index + 1) { return (.linkArrow, index + 1 + ending.utf8.count) }
        return nil
    }

    /// Digits, a point and digits; else a whole number not followed by a point (`0` alone, or digits from 1 to 9 first,
    /// backing off one digit before a point); else an identifier.
    static func matchNumber(in terminals: PlaneMapTerminals, at start: Int) -> (WardleyMapTokenKind?, Int)? {
        var end = start
        while let next = terminals.byte(end), PlaneMapByte.isDigit(next) { end += 1 }
        if terminals.byte(end) == PlaneMapByte.period, let next = terminals.byte(end + 1), PlaneMapByte.isDigit(next) {
            var fractionEnd = end + 1
            while let digit = terminals.byte(fractionEnd), PlaneMapByte.isDigit(digit) { fractionEnd += 1 }
            return (.decimal, fractionEnd)
        }
        if terminals.byte(start) == UInt8(ascii: "0") { return (.wholeNumber, start + 1) }
        if terminals.byte(end) != PlaneMapByte.period { return (.wholeNumber, end) }
        if end - start >= 2 { return (.wholeNumber, end - 1) }
        return endOfIdentifier(in: terminals, at: start).map { end in (.identifier, end) }
    }

    /// A sourcing word, a keyword, a name with spaces, an accessibility statement, a title or an identifier.
    static func matchWord(in terminals: inout PlaneMapTerminals, at start: Int) -> (WardleyMapTokenKind?, Int)? {
        for word in sourcingWords where terminals.hasPrefix(word, at: start) { return (.sourcing, start + word.utf8.count) }
        for (word, kind) in keywords where terminals.hasPrefix(word, at: start) {
            return (kind, start + word.utf8.count)
        }
        if let end = endOfName(in: terminals, at: start) { return (.name, end) }
        if let end = terminals.endOfAccessibilityDescription(at: start) { return (.accessibilityDescription, end) }
        if let end = terminals.endOfAccessibilityTitle(at: start) { return (.accessibilityTitle, end) }
        if let end = terminals.endOfTitle(at: start) { return (.title, end) }
        return endOfIdentifier(in: terminals, at: start).map { end in (.identifier, end) }
    }

    /// A letter, then letters, digits, `_`, `(`, `)`, `&` and hyphens not before `>`; then words after spaces or tabs,
    /// each starting with a letter or `(`. Not a name where `title` and white space, `accTitle` or `accDescr` start.
    private static func endOfName(in terminals: PlaneMapTerminals, at start: Int) -> Int? {
        guard let first = terminals.byte(start), PlaneMapByte.isLetter(first) else { return nil }
        if terminals.hasPrefix("accTitle", at: start) || terminals.hasPrefix("accDescr", at: start) { return nil }
        if terminals.hasPrefix("title", at: start), let next = terminals.byte(start + 5), PlaneMapByte.isSpace(next) { return nil }
        var end = endOfNameWord(in: terminals, from: start + 1)
        while true {
            let afterBlanks = endOfBlanks(in: terminals, from: end)
            guard afterBlanks > end, let next = terminals.byte(afterBlanks), PlaneMapByte.isLetter(next) || next == PlaneMapByte.openingParenthesis else { return end }
            end = endOfNameWord(in: terminals, from: afterBlanks + 1)
        }
    }

    private static func endOfNameWord(in terminals: PlaneMapTerminals, from start: Int) -> Int {
        var end = start
        while let next = terminals.byte(end) {
            if PlaneMapByte.isWord(next) || next == PlaneMapByte.openingParenthesis || next == PlaneMapByte.closingParenthesis || next == PlaneMapByte.ampersand {
                end += 1
            } else if next == PlaneMapByte.hyphen, terminals.byte(end + 1) != PlaneMapByte.greaterThan {
                end += 1
            } else {
                return end
            }
        }
        return end
    }

    /// A word character, then word characters and hyphens, ending on a word character.
    private static func endOfIdentifier(in terminals: PlaneMapTerminals, at start: Int) -> Int? {
        guard let first = terminals.byte(start), PlaneMapByte.isWord(first) else { return nil }
        var end = start + 1
        var lastWord = end
        while let next = terminals.byte(end), PlaneMapByte.isWord(next) || next == PlaneMapByte.hyphen {
            end += 1
            if PlaneMapByte.isWord(next) { lastWord = end }
        }
        return lastWord
    }
}
