/**
 * File: StateDiagramDeclarationSyntax.swift
 * -----------------------------------------
 * Layer: Core
 * Description: What a state diagram's `state` statement declares, read on the text's bytes: a stereotyped state, a
 *              described one, a composite's opening, or nothing.
 *
 * Authors: felixchvl, Bahey Shalash
 * Version: 0.2
 * Date: 25/11/2026
 */

import Foundation

/// What a `state` statement declares.
enum StateDiagramDeclaration: Equatable {
    /// `state Id <<fork>>`, `<<join>>`, `<<choice>>`, or the same in double brackets (`[[choice]]`).
    case stereotyped(identifier: MermaidTextRange, kind: StateDiagramStateKind)
    /// `state "text" as Id`, or `state "text" as Id:more text`, which gives the state a second description.
    case described(identifier: StateDiagramStateReference, descriptions: [DiagramLabel], opensBody: Bool)
    /// `state Id {`: a composite state whose body follows.
    case composite(identifier: MermaidTextRange)
    /// `state Id` alone, which declares nothing in Mermaid: a state is made by naming it in another statement.
    case nothing
}

/// Reads what follows the keyword `state`.
enum StateDiagramDeclarationSyntax {
    /// Reads from the position, after `state` and its space, to the end of the declaration; for one that opens a body,
    /// the position ends past the `{`.
    static func readDeclaration(_ bytes: inout GraphDiagramBytes) throws(MermaidDiagramReadError) -> StateDiagramDeclaration {
        bytes.skipSpaces()
        let declaration = bytes
        if let (identifier, kind) = readStereotyped(&bytes) {
            guard !identifier.isEmpty else { throw .invalidSyntax(line: declaration.line, problem: .expectedState) }
            return .stereotyped(identifier: identifier, kind: kind)
        }
        if let description = try StateDiagramTextSyntax.readQuotedText(&bytes) {
            return try StateDiagramDescribedSyntax.readDescribed(&bytes, description: description)
        }
        let start = bytes.position
        while let byte = bytes.peek(), !MermaidByte.isWhitespace(byte), byte != MermaidByte.openingBrace { bytes.advance() }
        let identifier = MermaidTextRange(start: start, end: bytes.position)
        guard !identifier.isEmpty else { throw .invalidSyntax(line: declaration.line, problem: .expectedState) }
        bytes.skipSpaces()
        if bytes.peek() == MermaidByte.openingBrace {
            bytes.advance()
            return .composite(identifier: identifier)
        }
        // More words on the line declare nothing, unless a brace follows them: a composite's name is one word.
        let wordsStart = bytes.position
        while let byte = bytes.peek(), byte != MermaidByte.newline, byte != MermaidByte.semicolon, byte != MermaidByte.openingBrace,
              !bytes.isAtCommentStart {
            bytes.advance()
        }
        if bytes.peek() == MermaidByte.openingBrace {
            let words = bytes.text(identifier) + " " + bytes.text(bytes.trimmed(from: wordsStart, to: bytes.position))
            throw .invalidSyntax(line: declaration.line, problem: .stateNameNotOneWord(words))
        }
        return .nothing
    }

    /// `Id <<kind>>` on the rest of the line: the text before the stereotype, trimmed, and the kind; the position moves
    /// past the stereotype. Nil when the line holds none before a line break or a comment.
    private static func readStereotyped(_ bytes: inout GraphDiagramBytes) -> (MermaidTextRange, StateDiagramStateKind)? {
        var lookahead = bytes
        let start = lookahead.position
        while let byte = lookahead.peek(), byte != MermaidByte.newline, !lookahead.isAtCommentStart {
            if byte == MermaidByte.lessThan || byte == MermaidByte.openingBracket, let (kind, length) = stereotype(at: lookahead) {
                let identifier = lookahead.trimmed(from: start, to: lookahead.position)
                lookahead.advance(by: length)
                bytes = lookahead
                return (identifier, kind)
            }
            lookahead.advance()
        }
        return nil
    }

    /// The stereotype at the position and its length in bytes, or nil.
    private static func stereotype(at bytes: GraphDiagramBytes) -> (StateDiagramStateKind, Int)? {
        let isAngled = bytes.isAt(MermaidByte.lessThan, MermaidByte.lessThan)
        guard isAngled || bytes.isAt(MermaidByte.openingBracket, MermaidByte.openingBracket) else { return nil }
        let closing = isAngled ? MermaidByte.greaterThan : MermaidByte.closingBracket
        var nameStart = bytes
        nameStart.advance(by: 2)
        for (kind, name) in stereotypeNames where nameStart.hasCaseInsensitivePrefix(name) {
            var afterName = nameStart
            afterName.advance(by: name.utf8CodeUnitCount)
            if afterName.isAt(closing, closing) { return (kind, 4 + name.utf8CodeUnitCount) }
        }
        return nil
    }

    /// The kinds a stereotype names, by their names in lowercase.
    private static let stereotypeNames: [(StateDiagramStateKind, StaticString)] = [(.fork, "fork"), (.join, "join"), (.choice, "choice")]
}

/// Reads `"text" as Id`, `"text" as Id:more` or `"text" as Id {`, after the quoted text.
enum StateDiagramDescribedSyntax {
    static func readDescribed(_ bytes: inout GraphDiagramBytes, description: MermaidTextRange) throws(MermaidDiagramReadError) -> StateDiagramDeclaration {
        bytes.skipWhitespace()
        guard StateDiagramTextSyntax.isAtKeyword(bytes, "as") else {
            throw .invalidSyntax(line: bytes.line, problem: bytes.isAtEnd ? .expectedState : .unexpectedText(bytes.excerpt()))
        }
        bytes.advance(by: 2)
        bytes.skipSpaces()
        let identifierStart = bytes
        let start = bytes.position
        while let byte = bytes.peek(), byte != MermaidByte.newline, byte != MermaidByte.openingBrace, !bytes.isAtCommentStart { bytes.advance() }
        let written = bytes.trimmed(from: start, to: bytes.position)
        let (identifier, descriptions) = bytes.isASCII ? asciiIdentifier(bytes, written, description: description)
            : writtenIdentifier(bytes, written, description: description)
        guard identifier != .named(.empty), identifier != .written("") else { throw .invalidSyntax(line: identifierStart.line, problem: .expectedState) }
        let opensBody = bytes.peek() == MermaidByte.openingBrace
        if opensBody { bytes.advance() }
        return .described(identifier: identifier, descriptions: descriptions.filter { label in !label.isEmpty }, opensBody: opensBody)
    }

    /// The identifier and texts of a text of ASCII bytes, trimmed of the bytes Foundation's white space and line
    /// breaks are in ASCII.
    private static func asciiIdentifier(_ bytes: GraphDiagramBytes, _ written: MermaidTextRange,
                                        description: MermaidTextRange) -> (StateDiagramStateReference, [DiagramLabel]) {
        var descriptions = [StateDiagramTextSyntax.label(bytes, trimmed(bytes, description, isLineBreakTrimmed: true))]
        var identifier = written
        if let colon = UnsafeBufferPointer(rebasing: bytes.buffer[written.lowerBound..<written.upperBound]).firstIndex(of: MermaidByte.colon) {
            let colonOffset = written.lowerBound + colon
            descriptions.append(StateDiagramTextSyntax.label(bytes, trimmed(bytes, MermaidTextRange(start: colonOffset + 1, end: written.upperBound),
                                                                            isLineBreakTrimmed: false)))
            identifier = trimmed(bytes, MermaidTextRange(start: written.lowerBound, end: colonOffset), isLineBreakTrimmed: false)
        }
        return (identifier.isEmpty ? .named(.empty) : .named(identifier), descriptions)
    }

    /// `range` without Foundation's `whitespaces` at its ends (a space or a tab, in ASCII), or its
    /// `whitespacesAndNewlines` (those and the line feed, vertical tab, form feed and carriage return).
    private static func trimmed(_ bytes: GraphDiagramBytes, _ range: MermaidTextRange, isLineBreakTrimmed: Bool) -> MermaidTextRange {
        func isTrimmed(_ byte: UInt8) -> Bool { byte == MermaidByte.space || byte == MermaidByte.tab || (isLineBreakTrimmed && byte >= 0x0A && byte <= 0x0D) }
        var start = range.lowerBound
        var end = range.upperBound
        while start < end, isTrimmed(bytes.buffer[start]) { start += 1 }
        while end > start, isTrimmed(bytes.buffer[end - 1]) { end -= 1 }
        return MermaidTextRange(start: start, end: end)
    }

    /// The identifier and texts of a text beyond ASCII, as 0.7.0 read them from Strings.
    private static func writtenIdentifier(_ bytes: GraphDiagramBytes, _ written: MermaidTextRange,
                                          description: MermaidTextRange) -> (StateDiagramStateReference, [DiagramLabel]) {
        var identifier = bytes.text(written)
        var descriptions = [StateDiagramTextSyntax.label(from: bytes.text(description).trimmingCharacters(in: .whitespacesAndNewlines))]
        if let colon = identifier.firstIndex(of: ":") {
            descriptions.append(StateDiagramTextSyntax.label(from: identifier[identifier.index(after: colon)...].trimmingCharacters(in: .whitespaces)))
            identifier = identifier[..<colon].trimmingCharacters(in: .whitespaces)
        }
        return (.written(identifier), descriptions)
    }
}
