/**
 * File: StateDiagramParser.swift
 * ------------------------------
 * Layer: Core
 * Description: Reads a state diagram's statements on its text's bytes, as Mermaid's grammar reads them: states,
 *              transitions, starts and ends, declarations, notes, composite bodies, the direction, accessibility text,
 *              and the statements that only style the diagram, counted and left.
 *
 * Authors: felixchvl, Bahey Shalash
 * Version: 0.2
 * Date: 25/11/2026
 */

import Foundation

/// Reads a state diagram's statements after its `stateDiagram` or `stateDiagram-v2` keyword, as Mermaid's grammar
/// does: states named alone or with a text (`A : text`), transitions (`A --> B : text`), `[*]` starts and ends,
/// declarations (`state …`), notes, composite bodies (`{ … }`, divided by `--`), the direction, accessibility text,
/// and the statements that only style the diagram, which are counted and left. A statement may follow another on the
/// same line, as in Mermaid (`a --> b class a done`); a line break, or a semicolon, ends a text. `%%` and `#` start a
/// comment.
struct StateDiagramParser {
    private var bytes: GraphDiagramBytes
    private var builder: StateDiagramBuilder

    /// Reads the state diagram whose keyword ends at the cursor, on the cursor's bytes, borrowed.
    static func parse(_ cursor: MermaidTextCursor, limits: MermaidDiagramLimits) throws(MermaidDiagramReadError) -> StateDiagram {
        try cursor.bytes.withUnsafeBufferPointer { buffer throws(MermaidDiagramReadError) in
            let bytes = GraphDiagramBytes(buffer, position: cursor.position)
            var parser = StateDiagramParser(bytes: bytes, builder: StateDiagramBuilder(limits: limits, isASCII: bytes.isASCII, byteCount: buffer.count - cursor.position))
            try parser.readStatements()
            return parser.builder.diagram
        }
    }

    private mutating func readStatements() throws(MermaidDiagramReadError) {
        while true {
            bytes.skipWhitespace()
            guard let byte = bytes.peek() else { break }
            if byte == MermaidByte.semicolon {
                bytes.advance()
            } else if bytes.isAtCommentStart || byte == Self.numberSign {
                bytes.skipToEndOfLine()
            } else if try readKeywordStatement() {
                continue
            } else if try readBodyPunctuation() {
                continue
            } else {
                try readStateStatement()
            }
        }
        if let identifier = builder.innermostOpenCompositeIdentifier {
            throw .invalidSyntax(line: bytes.line, problem: .unclosedCompositeState(identifier: identifier))
        }
    }

    /// Reads a statement that starts with a keyword, and returns whether there was one.
    private mutating func readKeywordStatement() throws(MermaidDiagramReadError) -> Bool {
        let keywordStart = bytes
        guard let (keyword, afterKeyword) = keywordAtPosition() else { return false }
        bytes = afterKeyword
        switch keyword {
        case .state: try readDeclaration()
        case .note:
            if let note = try StateDiagramNoteSyntax.readNote(&bytes, keyword: keywordStart) {
                let stateIndex = try builder.stateIndex(for: note.state, in: bytes, isFirst: true)
                try builder.addNote(toStateAt: stateIndex, side: note.side, text: note.text)
            }
        case .direction: try readDirection()
        case .accessibilityTitle: builder.setAccessibilityTitle(readAccessibilityLine())
        case .accessibilityDescription: builder.setAccessibilityDescription(try readAccessibilityDescription())
        case .classDefinition, .classAssignment, .style, .click:
            bytes.skipToEndOfLine()
            builder.countUnappliedStatement()
        case .scale, .hide:
            // `scale 350 width` and `hide empty description` change nothing in Mermaid's drawing.
            bytes.skipToEndOfLine()
        }
        return true
    }

    /// The keyword at the position and the position past it, or nil. A word is a keyword only when a space or a line
    /// break follows it, so that `classes` and `notes --> B` name states; `accTitle` and `accDescr` need a colon (or,
    /// for `accDescr`, a brace), `direction` a word after it, and `hide` is only `hide empty description`.
    private func keywordAtPosition() -> (Keyword, GraphDiagramBytes)? {
        var lookahead = bytes
        guard let keyword = Self.keyword(lookahead.readWord(), in: bytes) else { return nil }
        switch keyword {
        case .accessibilityTitle, .accessibilityDescription:
            var afterSpaces = lookahead
            afterSpaces.skipSpaces()
            guard let next = afterSpaces.peek(),
                  next == MermaidByte.colon || (next == MermaidByte.openingBrace && keyword == .accessibilityDescription) else { return nil }
        case .hide:
            guard bytes.hasCaseInsensitivePrefix(Self.hideEmptyDescription) else { return nil }
            lookahead = bytes
            lookahead.advance(by: Self.hideEmptyDescription.utf8CodeUnitCount)
            if let next = lookahead.peek(), MermaidByte.isIdentifierByte(next) { return nil }
        case .direction:
            var afterSpaces = lookahead
            afterSpaces.skipSpaces()
            guard afterSpaces.position > lookahead.position, let next = afterSpaces.peek(), MermaidByte.isLetter(next) else { return nil }
        case .state, .note, .classDefinition, .classAssignment, .style, .click, .scale:
            guard let next = lookahead.peek(), MermaidByte.isWhitespace(next) else { return nil }
        }
        return (keyword, lookahead)
    }

    /// `}`, which closes a composite's body, and `--`, which divides it into concurrent regions. Returns whether one
    /// was read.
    private mutating func readBodyPunctuation() throws(MermaidDiagramReadError) -> Bool {
        if bytes.peek() == MermaidByte.closingBrace {
            guard builder.closeBody() else { throw .invalidSyntax(line: bytes.line, problem: .closingBraceWithoutCompositeState) }
            bytes.advance()
            return true
        }
        guard bytes.isAt(MermaidByte.hyphen, MermaidByte.hyphen), !Self.isAtTransitionArrow(bytes) else { return false }
        guard builder.startRegion() else { throw .invalidSyntax(line: bytes.line, problem: .unexpectedText(bytes.excerpt())) }
        bytes.advance(by: 2)
        return true
    }

    /// `A`, `A : text`, `A --> B` or `A --> B : text`, each state optionally followed by `:::class`.
    private mutating func readStateStatement() throws(MermaidDiagramReadError) {
        guard bytes.peek() != MermaidByte.quotationMark, let first = readReference() else {
            throw .invalidSyntax(line: bytes.line, problem: .unexpectedText(bytes.excerpt()))
        }
        bytes.skipSpaces()
        guard Self.isAtTransitionArrow(bytes) else {
            let stateIndex = try builder.stateIndex(for: first, in: bytes, isFirst: true)
            if let description = StateDiagramTextSyntax.readColonText(&bytes) { builder.addDescription(description, toStateAt: stateIndex) }
            return
        }
        bytes.advance(by: 3)
        bytes.skipSpaces()
        guard let second = readReference() else { throw .invalidSyntax(line: bytes.line, problem: .expectedState) }
        let sourceIndex = try builder.stateIndex(for: first, in: bytes, isFirst: true)
        let targetIndex = try builder.stateIndex(for: second, in: bytes, isFirst: false)
        bytes.skipSpaces()
        try builder.addTransition(from: sourceIndex, to: targetIndex, label: StateDiagramTextSyntax.readColonText(&bytes))
    }

    /// A state reference and any `:::class` after it, which is counted and not applied.
    private mutating func readReference() -> StateDiagramStateReference? {
        guard let reference = StateDiagramTextSyntax.readReference(&bytes) else { return nil }
        while bytes.isAt(MermaidByte.colon, MermaidByte.colon, MermaidByte.colon) {
            bytes.advance(by: 3)
            _ = StateDiagramTextSyntax.readIdentifier(&bytes)
            builder.countUnappliedStatement()
        }
        return reference
    }

    /// What follows `state`: a stereotype, a description, a composite's body, or nothing.
    private mutating func readDeclaration() throws(MermaidDiagramReadError) {
        switch try StateDiagramDeclarationSyntax.readDeclaration(&bytes) {
        case .stereotyped(let identifier, let kind):
            _ = try builder.stateIndex(for: .named(identifier), in: bytes, isFirst: true, kind: kind)
        case .described(let identifier, let descriptions, let opensBody):
            let stateIndex = try builder.stateIndex(for: identifier, in: bytes, isFirst: true)
            builder.addDescriptions(descriptions, toStateAt: stateIndex)
            if opensBody { builder.openBody(ofStateAt: stateIndex) }
        case .composite(let identifier):
            builder.openBody(ofStateAt: try builder.stateIndex(for: .named(identifier), in: bytes, isFirst: true))
        case .nothing:
            break
        }
    }

    /// `direction TB`, `BT`, `LR` or `RL`, for the body it is written in or the whole diagram.
    private mutating func readDirection() throws(MermaidDiagramReadError) {
        bytes.skipSpaces()
        let wordStart = bytes
        let word = bytes.text(bytes.readWord())
        guard let direction = FlowchartDirection(keyword: word) else { throw .invalidSyntax(line: wordStart.line, problem: .unknownDirection(word)) }
        builder.setDirection(direction)
        bytes.skipToEndOfLine()
    }

    /// `accTitle: text`, to the end of the line.
    private mutating func readAccessibilityLine() -> String {
        bytes.skipSpaces()
        if bytes.peek() == MermaidByte.colon { bytes.advance() }
        bytes.skipSpaces()
        let start = bytes.position
        bytes.skipToEndOfLine()
        var end = bytes.position
        while end > start, MermaidByte.isSpace(bytes.buffer[end - 1]) || bytes.buffer[end - 1] == MermaidByte.carriageReturn { end -= 1 }
        return DiagramLabelDecoder.decodingEntities(bytes.text(MermaidTextRange(start: start, end: end)))
    }

    /// `accDescr: text` or `accDescr { lines }`, whose lines are kept without their indentation and blank lines.
    private mutating func readAccessibilityDescription() throws(MermaidDiagramReadError) -> String {
        bytes.skipSpaces()
        guard bytes.peek() == MermaidByte.openingBrace else { return readAccessibilityLine() }
        let opening = bytes
        bytes.advance()
        let start = bytes.position
        while let byte = bytes.peek(), byte != MermaidByte.closingBrace { bytes.advance() }
        guard !bytes.isAtEnd else { throw .invalidSyntax(line: opening.line, problem: .unclosedAccessibilityDescription) }
        let description = bytes.text(MermaidTextRange(start: start, end: bytes.position))
        bytes.advance()
        let lines = description.split(separator: "\n").map { line in line.trimmingCharacters(in: .whitespaces) }
        return DiagramLabelDecoder.decodingEntities(lines.filter { line in !line.isEmpty }.joined(separator: "\n"))
    }

    private enum Keyword {
        case state, note, direction, accessibilityTitle, accessibilityDescription, classDefinition, classAssignment, style, click, scale, hide
    }

    /// The keyword `word` spells in any case (Mermaid reads them so), or nil.
    private static func keyword(_ word: MermaidTextRange, in bytes: GraphDiagramBytes) -> Keyword? {
        func spells(_ literal: StaticString) -> Bool {
            let literalBytes = literal.utf8Start
            for offset in 0..<word.count where bytes.buffer[word.lowerBound + offset] | 0x20 != literalBytes[offset] { return false }
            return true
        }
        // A word is ASCII letters, which setting their 0x20 bit lowercases.
        switch word.count {
        case 4: return spells("note") ? .note : spells("hide") ? .hide : nil
        case 5: return spells("state") ? .state : spells("class") ? .classAssignment : spells("style") ? .style : spells("click") ? .click
            : spells("scale") ? .scale : nil
        case 8: return spells("acctitle") ? .accessibilityTitle : spells("accdescr") ? .accessibilityDescription : spells("classdef") ? .classDefinition : nil
        case 9: return spells("direction") ? .direction : nil
        default: return nil
        }
    }

    /// Whether `-->` is at the position.
    @inline(__always) private static func isAtTransitionArrow(_ bytes: GraphDiagramBytes) -> Bool {
        bytes.isAt(MermaidByte.hyphen, MermaidByte.hyphen, MermaidByte.greaterThan)
    }

    private static let hideEmptyDescription: StaticString = "hide empty description"
    private static let numberSign = UInt8(ascii: "#")
}
