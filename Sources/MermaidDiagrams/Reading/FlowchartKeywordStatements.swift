/**
 * File: FlowchartKeywordStatements.swift
 * --------------------------------------
 * Layer: Core
 * Description: The flowchart statements that start with a keyword (`subgraph`, `end`, `direction`, `classDef`,
 *              `class`, `style`, `linkStyle`, `click`, `accTitle`, `accDescr`), and the moves of the reading position
 *              every statement makes.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 24/11/2026
 */

extension FlowchartParser {
    /// The statements a keyword starts.
    private enum Keyword {
        case subgraph
        case end
        case direction
        case styling(FlowchartStyleKeyword)
        case click
        case accessibilityTitle
        case accessibilityDescription
    }

    /// The keyword the letters from `start` to `end` spell, or nil.
    private func keyword(from start: Int, to end: Int) -> Keyword? {
        switch end - start {
        case 3: return bytes.hasText("end", at: start) ? .end : nil
        case 5:
            if bytes.hasText("class", at: start) { return .styling(.classAssignment) }
            if bytes.hasText("style", at: start) { return .styling(.style) }
            return bytes.hasText("click", at: start) ? .click : nil
        case 8:
            if bytes.hasText("subgraph", at: start) { return .subgraph }
            if bytes.hasText("classDef", at: start) { return .styling(.classDefinition) }
            if bytes.hasText("accTitle", at: start) { return .accessibilityTitle }
            return bytes.hasText("accDescr", at: start) ? .accessibilityDescription : nil
        case 9:
            if bytes.hasText("direction", at: start) { return .direction }
            return bytes.hasText("linkStyle", at: start) ? .styling(.linkStyle) : nil
        default: return nil
        }
    }

    /// Reads a statement that starts with a keyword, and returns whether there was one. A word is a keyword only when
    /// a space, a colon, a brace or the statement's end follows it, so that `classes --> B` is a chain.
    mutating func readKeywordStatement() throws(MermaidDiagramReadError) -> Bool {
        var wordEnd = position
        while wordEnd < bytes.count, MermaidByte.isLetter(bytes.base[wordEnd]) { wordEnd += 1 }
        guard wordEnd > position, let keyword = keyword(from: position, to: wordEnd) else { return false }
        if wordEnd < bytes.count, case let next = bytes.base[wordEnd], !MermaidByte.isSpace(next), !MermaidByte.endsStatement(next),
           next != MermaidByte.colon, next != MermaidByte.openingBrace { return false }
        let statementStart = position
        position = wordEnd
        switch keyword {
        case .subgraph: readGroupOpening()
        case .end:
            guard closeGroup() else { throw .invalidSyntax(line: bytes.line(at: statementStart), problem: .endWithoutSubgraph) }
            try expectStatementEnd()
        case .accessibilityTitle: accessibilityTitle = readAccessibilityLine()
        case .accessibilityDescription: accessibilityDescription = try readAccessibilityDescription()
        case .direction: readDirectionStatement()
        case .styling(let styleKeyword): try readStyleStatement(styleKeyword, keywordAt: statementStart)
        case .click:
            skipStatement()
            unappliedStatementCount += 1
        }
        return true
    }

    /// `classDef`, `class`, `style` or `linkStyle`: the statement is refused unless Pele's grammar reads it
    /// (`FlowchartStyleGrammar`), then what it sets is recorded.
    private mutating func readStyleStatement(_ keyword: FlowchartStyleKeyword, keywordAt keywordStart: Int) throws(MermaidDiagramReadError) {
        let statementStart = position
        skipStatement()
        let text = trimmedText(from: statementStart, to: position)
        guard FlowchartStyleGrammar.isReadByPele(keyword: keyword, in: bytes, from: statementStart, to: position) else {
            throw .invalidSyntax(line: bytes.line(at: keywordStart), problem: .unexpectedText(text))
        }
        apply(FlowchartStyleSyntax.statement(keyword: keyword.text, text: text))
    }

    /// `accTitle: text`, to the end of the line.
    private mutating func readAccessibilityLine() -> String {
        skipSpaces()
        if bytes[position] == MermaidByte.colon { position += 1 }
        skipSpaces()
        let start = position
        skipToEndOfLine()
        var end = position
        while end > start, MermaidByte.isSpace(bytes.base[end - 1]) || bytes.base[end - 1] == MermaidByte.carriageReturn { end -= 1 }
        return DiagramLabelDecoder.decodingEntities(bytes.string(from: start, to: end))
    }

    /// `accDescr: text` or `accDescr { lines }`.
    private mutating func readAccessibilityDescription() throws(MermaidDiagramReadError) -> String {
        skipSpaces()
        guard bytes[position] == MermaidByte.openingBrace, position < bytes.count else { return readAccessibilityLine() }
        let opening = position
        position += 1
        let start = position
        while position < bytes.count, bytes.base[position] != MermaidByte.closingBrace { position += 1 }
        guard position < bytes.count else { throw .invalidSyntax(line: bytes.line(at: opening), problem: .unclosedAccessibilityDescription) }
        let description = bytes.string(from: start, to: position)
        position += 1
        return DiagramLabelDecoder.label(from: description, form: .plain).lines.filter { line in !line.isEmpty }.joined(separator: " ")
    }

    // MARK: Moving

    /// Skips spaces and tabs, never a line break.
    @inline(__always) mutating func skipSpaces() {
        while MermaidByte.isSpace(bytes[position]) { position += 1 }
    }

    /// Skips spaces, tabs, carriage returns and line breaks.
    @inline(__always) mutating func skipWhitespace() {
        while MermaidByte.isWhitespace(bytes[position]) { position += 1 }
    }

    /// Moves to the line break that ends the current line, or to the end.
    mutating func skipToEndOfLine() {
        while position < bytes.count, bytes.base[position] != MermaidByte.newline { position += 1 }
    }

    /// Moves to the end of a statement that is not read: the next line break, or semicolon outside quotation marks.
    mutating func skipStatement() {
        var isInsideQuotation = false
        while position < bytes.count, case let byte = bytes.base[position], byte != MermaidByte.newline {
            if byte == MermaidByte.quotationMark { isInsideQuotation.toggle() }
            if byte == MermaidByte.semicolon, !isInsideQuotation { return }
            position += 1
        }
    }

    /// A statement ends at a line break, a semicolon, a comment or the end of the text; anything else is an error.
    mutating func expectStatementEnd() throws(MermaidDiagramReadError) {
        skipSpaces()
        guard position < bytes.count, !MermaidByte.endsStatement(bytes.base[position]) else { return }
        guard isAtComment else { throw .invalidSyntax(line: bytes.line(at: position), problem: .unexpectedText(bytes.excerpt(at: position))) }
        skipToEndOfLine()
    }

    /// The text from `start` to `end` without the spaces, tabs and line breaks at either end.
    func trimmedText(from start: Int, to end: Int) -> String {
        let trimmed = trimmedRange(from: start, to: end)
        return bytes.string(from: trimmed.lowerBound, to: trimmed.upperBound)
    }

    /// The range from `start` to `end` without the spaces, tabs and line breaks at either end.
    func trimmedRange(from start: Int, to end: Int) -> Range<Int> {
        var first = start
        var last = end
        while first < last, MermaidByte.isWhitespace(bytes.base[first]) { first += 1 }
        while last > first, MermaidByte.isWhitespace(bytes.base[last - 1]) { last -= 1 }
        return first..<last
    }
}
