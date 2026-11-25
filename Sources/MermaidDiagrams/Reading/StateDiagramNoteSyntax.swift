/**
 * File: StateDiagramNoteSyntax.swift
 * ----------------------------------
 * Layer: Core
 * Description: A state diagram's `note` statement read on the text's bytes: a note on one line, one whose lines run
 *              to `end note`, or a floating note, which is read and not drawn.
 *
 * Authors: felixchvl, Bahey Shalash
 * Version: 0.2
 * Date: 25/11/2026
 */

/// A note statement that sits beside a state.
struct StateDiagramNoteDeclaration: Equatable {
    let state: StateDiagramStateReference
    let side: StateDiagramNoteSide
    let text: DiagramLabel
}

/// Reads what follows the keyword `note`: `left of Id : text` on one line, `left of Id` with lines up to a line that
/// starts with `end note`, or a floating note (`"text" as Id`), which Mermaid reads and does not draw.
enum StateDiagramNoteSyntax {
    /// Reads from the position, after `note` and its space, to the end of the note. Nil for a floating note.
    /// - Parameter keyword: The position of `note`, whose line a note without `end note` is reported on.
    static func readNote(_ bytes: inout GraphDiagramBytes, keyword: GraphDiagramBytes) throws(MermaidDiagramReadError) -> StateDiagramNoteDeclaration? {
        bytes.skipSpaces()
        if try StateDiagramTextSyntax.readQuotedText(&bytes) != nil {
            try readFloatingNoteIdentifier(&bytes)
            return nil
        }
        guard let side = readSide(&bytes) else {
            throw .invalidSyntax(line: bytes.line, problem: bytes.isAtEnd ? .expectedState : .unexpectedText(bytes.excerpt()))
        }
        bytes.skipSpaces()
        guard let state = StateDiagramTextSyntax.readReference(&bytes) else { throw .invalidSyntax(line: bytes.line, problem: .expectedState) }
        bytes.skipSpaces()
        if let text = StateDiagramTextSyntax.readColonText(&bytes) {
            return StateDiagramNoteDeclaration(state: state, side: side, text: text)
        }
        let text = try readLinesUpToEndNote(&bytes, keyword: keyword)
        return StateDiagramNoteDeclaration(state: state, side: side, text: StateDiagramTextSyntax.label(bytes, text))
    }

    /// `left of` or `right of`, in any case, followed by a space.
    private static func readSide(_ bytes: inout GraphDiagramBytes) -> StateDiagramNoteSide? {
        for (side, words) in sideWords where StateDiagramTextSyntax.isAtKeyword(bytes, words) {
            bytes.advance(by: words.utf8CodeUnitCount)
            return side
        }
        return nil
    }

    /// The text from the position to the next line whose first word is `end note`, trimmed; the position moves past
    /// `end note`. A line that holds `end note` after other words does not end the note.
    private static func readLinesUpToEndNote(_ bytes: inout GraphDiagramBytes, keyword: GraphDiagramBytes) throws(MermaidDiagramReadError) -> MermaidTextRange {
        let start = bytes.position
        while true {
            bytes.skipToEndOfLine()
            guard !bytes.isAtEnd else { throw .invalidSyntax(line: keyword.line, problem: .unclosedNote) }
            bytes.advance()
            let lineStart = bytes.position
            bytes.skipSpaces()
            if StateDiagramTextSyntax.isAtKeyword(bytes, endNoteWords) {
                let text = bytes.trimmed(from: start, to: lineStart)
                bytes.advance(by: endNoteWords.utf8CodeUnitCount)
                return text
            }
        }
    }

    /// `as Id` after a floating note's text.
    private static func readFloatingNoteIdentifier(_ bytes: inout GraphDiagramBytes) throws(MermaidDiagramReadError) {
        bytes.skipSpaces()
        guard StateDiagramTextSyntax.isAtKeyword(bytes, asWord) else {
            throw .invalidSyntax(line: bytes.line, problem: bytes.isAtEnd ? .expectedState : .unexpectedText(bytes.excerpt()))
        }
        bytes.advance(by: asWord.utf8CodeUnitCount)
        bytes.skipSpaces()
        guard StateDiagramTextSyntax.readIdentifier(&bytes) != nil else { throw .invalidSyntax(line: bytes.line, problem: .expectedState) }
    }

    private static let sideWords: [(StateDiagramNoteSide, StaticString)] = [(.left, "left of"), (.right, "right of")]
    private static let endNoteWords: StaticString = "end note"
    private static let asWord: StaticString = "as"
}
