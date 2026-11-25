/**
 * File: ReferenceStateDiagramNoteSyntax.swift
 * -------------------------------------------
 * Layer: Tests
 * Description: 0.7.0's state diagram reader, kept unchanged but for its names as the reference the reader on bytes is
 *              compared with (StateReadingEquivalenceTests).
 *
 * Authors: felixchvl, Bahey Shalash
 * Version: 0.1
 * Date: 25/11/2026
 */

@testable import MermaidDiagrams
/// A note statement that sits beside a state.
struct ReferenceStateDiagramNoteDeclaration: Equatable {
    let state: ReferenceStateDiagramStateReference
    let side: StateDiagramNoteSide
    let text: DiagramLabel
}

/// Reads what follows the keyword `note`: `left of Id : text` on one line, `left of Id` with lines up to a line that
/// starts with `end note`, or a floating note (`"text" as Id`), which Mermaid reads and does not draw.
enum ReferenceStateDiagramNoteSyntax {
    /// Reads from the cursor, after `note` and its space, to the end of the note. Nil for a floating note.
    /// - Parameter keywordLine: The line of `note`, which a note without `end note` is reported on.
    static func readNote(_ cursor: inout MermaidTextCursor, keywordLine: Int) throws(MermaidDiagramReadError) -> ReferenceStateDiagramNoteDeclaration? {
        cursor.skipSpaces()
        if try ReferenceStateDiagramTextSyntax.readQuotedText(&cursor) != nil {
            try readFloatingNoteIdentifier(&cursor)
            return nil
        }
        guard let side = readSide(&cursor) else {
            throw .invalidSyntax(line: cursor.line, problem: cursor.isAtEnd ? .expectedState : .unexpectedText(cursor.excerpt()))
        }
        cursor.skipSpaces()
        guard let state = ReferenceStateDiagramTextSyntax.readReference(&cursor) else { throw .invalidSyntax(line: cursor.line, problem: .expectedState) }
        cursor.skipSpaces()
        if let text = ReferenceStateDiagramTextSyntax.readColonText(&cursor) {
            return ReferenceStateDiagramNoteDeclaration(state: state, side: side, text: text)
        }
        let text = try readLinesUpToEndNote(&cursor, keywordLine: keywordLine)
        return ReferenceStateDiagramNoteDeclaration(state: state, side: side, text: ReferenceStateDiagramTextSyntax.label(from: text))
    }

    /// `left of` or `right of`, in any case, followed by a space.
    private static func readSide(_ cursor: inout MermaidTextCursor) -> StateDiagramNoteSide? {
        for (side, words) in sideWords where ReferenceStateDiagramTextSyntax.isAtKeyword(cursor, words) {
            cursor.advance(by: words.count)
            return side
        }
        return nil
    }

    /// The text from the cursor to the next line whose first word is `end note`, trimmed; the cursor moves past
    /// `end note`. A line that holds `end note` after other words does not end the note.
    private static func readLinesUpToEndNote(_ cursor: inout MermaidTextCursor, keywordLine: Int) throws(MermaidDiagramReadError) -> String {
        let start = cursor.position
        while true {
            cursor.skipToEndOfLine()
            guard !cursor.isAtEnd else { throw .invalidSyntax(line: keywordLine, problem: .unclosedNote) }
            cursor.advance()
            let lineStart = cursor.position
            cursor.skipSpaces()
            if ReferenceStateDiagramTextSyntax.isAtKeyword(cursor, endNoteWords) {
                let text = cursor.trimmedText(from: start, to: lineStart)
                cursor.advance(by: endNoteWords.count)
                return text
            }
        }
    }

    /// `as Id` after a floating note's text.
    private static func readFloatingNoteIdentifier(_ cursor: inout MermaidTextCursor) throws(MermaidDiagramReadError) {
        cursor.skipSpaces()
        guard ReferenceStateDiagramTextSyntax.isAtKeyword(cursor, asWord) else {
            throw .invalidSyntax(line: cursor.line, problem: cursor.isAtEnd ? .expectedState : .unexpectedText(cursor.excerpt()))
        }
        cursor.advance(by: asWord.count)
        cursor.skipSpaces()
        guard ReferenceStateDiagramTextSyntax.readIdentifier(&cursor) != nil else { throw .invalidSyntax(line: cursor.line, problem: .expectedState) }
    }

    private static let sideWords: [(StateDiagramNoteSide, [UInt8])] = [(.left, Array("left of".utf8)), (.right, Array("right of".utf8))]
    private static let endNoteWords = Array("end note".utf8)
    private static let asWord = Array("as".utf8)
}
