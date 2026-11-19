/**
 * File: TreemapRowTokens.swift
 * ----------------------------
 * Layer: Core
 * Description: The pieces of a treemap's rows, as Mermaid's lexer cuts them: quoted names, values, class names, class
 *              definitions and the indentation before a row.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 19/11/2026
 */

/// A `classDef` statement: the class's name and the text of its style declarations, up to a `;` or the end of the line.
struct TreemapClassDefinition {
    let name: String
    let styleText: String?
    let line: Int
}

/// Reads the pieces of a treemap's rows at a cursor. A line break and a `%%` comment are skipped between any two pieces; a
/// run of spaces or tabs is a piece of its own (a row's indentation, or the blank before a `:`), as it is for the lexer.
enum TreemapRowTokens {
    /// Skips line breaks, comments (`%%` to the end of the line, directives of one line too) and lines of nothing but blanks,
    /// which are what a directive written over several lines leaves behind. A carriage return that does not come before a
    /// line break is no piece of any kind and is left. The blanks that end a row's line are not skipped: they are the
    /// indentation the lexer reads the next row with.
    static func skipHidden(_ cursor: inout MermaidTextCursor) {
        while let byte = cursor.peek() {
            if MermaidByte.isSpace(byte), isAtLineStart(cursor), isBlankLine(from: cursor) {
                cursor.skipSpaces()
            } else if byte == MermaidByte.newline {
                cursor.advance()
            } else if byte == MermaidByte.carriageReturn, cursor.peek(1) == MermaidByte.newline {
                cursor.advance(by: 2)
            } else if cursor.hasPrefix(commentStart) {
                cursor.skipToEndOfLine()
            } else {
                return
            }
        }
    }

    private static func isAtLineStart(_ cursor: MermaidTextCursor) -> Bool {
        cursor.position == 0 || cursor.bytes[cursor.position - 1] == MermaidByte.newline
    }

    /// Whether only spaces and tabs come before the end of the line, or of the text.
    private static func isBlankLine(from cursor: MermaidTextCursor) -> Bool {
        var lookahead = cursor
        lookahead.skipSpaces()
        guard let byte = lookahead.peek() else { return true }
        return byte == MermaidByte.newline || (byte == MermaidByte.carriageReturn && lookahead.peek(1) == MermaidByte.newline)
    }

    /// The length of the run of spaces and tabs at the cursor, which is moved past it; nil when there is none.
    static func readIndentation(_ cursor: inout MermaidTextCursor) -> Int? {
        let start = cursor.position
        cursor.skipSpaces()
        return cursor.position > start ? cursor.position - start : nil
    }

    /// A name between quotation marks or apostrophes, taken as it is written (no escapes), which may span lines.
    static func readQuotedName(_ cursor: inout MermaidTextCursor) throws(MermaidDiagramReadError) -> String? {
        guard let quotation = cursor.peek(), quotation == MermaidByte.quotationMark || quotation == apostrophe else { return nil }
        let openingLine = cursor.line
        cursor.advance()
        let start = cursor.position
        while let byte = cursor.peek(), byte != quotation { cursor.advance() }
        guard !cursor.isAtEnd else { throw .invalidSyntax(line: openingLine, problem: .unclosedQuotation) }
        let name = cursor.text(from: start, to: cursor.position)
        cursor.advance()
        return name
    }

    /// The class name after `:::`: a letter or underscore, then letters, digits and underscores.
    static func readClassName(_ cursor: inout MermaidTextCursor) -> String? {
        guard let first = cursor.peek(), isNameStart(first) else { return nil }
        let start = cursor.position
        while let byte = cursor.peek(), isNameStart(byte) || MermaidByte.isDigit(byte) { cursor.advance() }
        return cursor.text(from: start, to: cursor.position)
    }

    /// A value: digits, `.`, `,` and `_` in any order, starting with a digit or a `.`, read as JavaScript's `parseFloat` reads
    /// the run without its commas. Nil, with the cursor where it was, when no run starts there; `.some(nil)` when the run is
    /// no number (`.`, `..5`).
    static func readValue(_ cursor: inout MermaidTextCursor) -> Double?? {
        guard let first = cursor.peek(), MermaidByte.isDigit(first) || first == MermaidByte.period else { return nil }
        var bytes: [UInt8] = []
        while let byte = cursor.peek(), MermaidByte.isDigit(byte) || byte == MermaidByte.period || byte == MermaidByte.comma || byte == MermaidByte.underscore {
            if byte != MermaidByte.comma { bytes.append(byte) }
            cursor.advance()
        }
        return .some(JavaScriptNumberReading.parseFloat(bytes[...]))
    }

    /// `classDef`, white space, a name of at least two characters, then, after more white space, the style text up to a `;`
    /// or the end of the line, and an optional `;`. White space may run over lines. Nil, with the cursor where it was, when no
    /// class definition starts there.
    static func readClassDefinition(_ cursor: inout MermaidTextCursor) -> TreemapClassDefinition? {
        guard cursor.hasPrefix(classDefinitionKeyword) else { return nil }
        var lookahead = cursor
        let line = lookahead.line
        lookahead.advance(by: classDefinitionKeyword.count)
        guard skipJavaScriptWhitespace(&lookahead) else { return nil }
        guard let name = readClassName(&lookahead), name.utf8.count >= 2 else { return nil }
        var styleText: String?
        var afterName = lookahead
        if skipJavaScriptWhitespace(&afterName) {
            let start = afterName.position
            while let byte = afterName.peek(), byte != MermaidByte.semicolon, byte != MermaidByte.newline, byte != MermaidByte.carriageReturn { afterName.advance() }
            let text = afterName.text(from: start, to: afterName.position)
            styleText = text.isEmpty ? nil : text
            lookahead = afterName
        }
        if lookahead.peek() == MermaidByte.semicolon { lookahead.advance() }
        cursor = lookahead
        return TreemapClassDefinition(name: name, styleText: styleText, line: line)
    }

    /// Skips JavaScript's white space (`\s`, line breaks included); false when none is there.
    private static func skipJavaScriptWhitespace(_ cursor: inout MermaidTextCursor) -> Bool {
        let end = JavaScriptWhitespace.endOfRun(in: cursor.bytes, from: cursor.position)
        guard end > cursor.position else { return false }
        cursor.advance(by: end - cursor.position)
        return true
    }

    private static func isNameStart(_ byte: UInt8) -> Bool {
        MermaidByte.isLetter(byte) || byte == MermaidByte.underscore
    }

    private static let apostrophe = UInt8(ascii: "'")
    private static let commentStart = Array("%%".utf8)
    private static let classDefinitionKeyword = Array("classDef".utf8)
}
