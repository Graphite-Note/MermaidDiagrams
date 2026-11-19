/**
 * File: MermaidTitleStatements.swift
 * ----------------------------------
 * Layer: Core
 * Description: Reads the statements the Langium-grammar diagrams share (title, accTitle, accDescr) and skips what lies
 *              between statements: blanks, line breaks, comments, directives of one line and blocks of front matter.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 19/11/2026
 */

/// The titles a diagram of Mermaid's Langium grammars (info, packet, radar, treemap) states: `title …`, `accTitle: …`,
/// `accDescr: …` and `accDescr { … }`, each ending its line, the later of two of a kind replacing the earlier. Empty
/// text is no title, as Mermaid's `title || frontMatterTitle` leaves it.
struct MermaidTitleStatements: Equatable, Sendable {
    var title: String?
    var accessibilityTitle: String?
    var accessibilityDescription: String?

    /// Reads the statement at the cursor and moves past its text (not past its line's end); false, with the cursor where
    /// it was, when none starts there.
    mutating func read(_ cursor: inout MermaidTextCursor) throws(MermaidDiagramReadError) -> Bool {
        if PieChartStatementText.isAtKeyword(Self.titleKeyword, cursor) {
            cursor.advance(by: Self.titleKeyword.count)
            title = Self.nonEmpty(PieChartStatementText.readLineValue(&cursor))
            return true
        }
        var lookahead = cursor
        if cursor.hasPrefix(Self.accessibilityTitleKeyword) {
            lookahead.advance(by: Self.accessibilityTitleKeyword.count)
            lookahead.skipSpaces()
            guard lookahead.peek() == MermaidByte.colon else { return false }
            lookahead.advance()
            cursor = lookahead
            accessibilityTitle = Self.nonEmpty(PieChartStatementText.readLineValue(&cursor))
            return true
        }
        guard cursor.hasPrefix(Self.accessibilityDescriptionKeyword) else { return false }
        lookahead.advance(by: Self.accessibilityDescriptionKeyword.count)
        guard let description = try PieChartStatementText.readAccessibilityDescription(&lookahead) else { return false }
        cursor = lookahead
        accessibilityDescription = Self.nonEmpty(description)
        return true
    }

    private static func nonEmpty(_ text: String) -> String? {
        text.isEmpty ? nil : text
    }

    // MARK: Between statements

    /// Skips spaces, tabs, comments, directives and the line breaks between statements, and a block of front matter
    /// (`---` … `---`) in the middle of the text, which Mermaid's lexers drop.
    static func skipBlank(_ cursor: inout MermaidTextCursor) {
        while true {
            skipSpacesAndComments(&cursor)
            guard let byte = cursor.peek() else { return }
            if byte == MermaidByte.newline || byte == MermaidByte.carriageReturn {
                cursor.advance()
            } else if byte == MermaidByte.hyphen, skipFrontMatterBlock(&cursor) {
                continue
            } else {
                return
            }
        }
    }

    /// A statement ends its line: spaces and a comment may follow it, then a line break or the end of the text.
    static func expectLineEnd(_ cursor: inout MermaidTextCursor) throws(MermaidDiagramReadError) {
        skipSpacesAndComments(&cursor)
        guard let byte = cursor.peek(), byte != MermaidByte.newline, byte != MermaidByte.carriageReturn else { return }
        throw .invalidSyntax(line: cursor.line, problem: .unexpectedText(cursor.excerpt()))
    }

    /// Skips spaces and tabs, and each `%%` comment to the end of its line. A directive that closes on its own line
    /// (`%%{ … }%%` followed by a space, a line break or the end) is skipped alone, the rest of the line is read after it;
    /// one that spans lines was blanked before the statements were read.
    static func skipSpacesAndComments(_ cursor: inout MermaidTextCursor) {
        while true {
            cursor.skipSpaces()
            guard cursor.hasPrefix(commentStart) else { return }
            if cursor.hasPrefix(directiveStart), let end = endOfDirective(in: cursor) {
                cursor.advance(by: end - cursor.position)
            } else {
                cursor.skipToEndOfLine()
            }
        }
    }

    /// The position after the `}%%` that closes the directive at the cursor on its own line, when what follows the
    /// closing is white space or the end; nil otherwise.
    private static func endOfDirective(in cursor: MermaidTextCursor) -> Int? {
        var position = cursor.position + directiveStart.count
        let bytes = cursor.bytes
        while position < bytes.count, bytes[position] != MermaidByte.newline {
            if bytes[position] == MermaidByte.closingBrace, bytes[position...].starts(with: directiveEnd) {
                let end = position + directiveEnd.count
                return end >= bytes.count || MermaidByte.isWhitespace(bytes[end]) ? end : nil
            }
            position += 1
        }
        return nil
    }

    /// Skips `---`, a line break, whatever follows up to a line that starts with `---`, and that `---`; false, with the
    /// cursor where it was, when the cursor is not on such a block's opening line or the block is never closed.
    static func skipFrontMatterBlock(_ cursor: inout MermaidTextCursor) -> Bool {
        guard cursor.hasPrefix(fence) else { return false }
        let bytes = cursor.bytes
        var position = cursor.position + fence.count
        while position < bytes.count, MermaidByte.isSpace(bytes[position]) { position += 1 }
        if position < bytes.count, bytes[position] == MermaidByte.carriageReturn { position += 1 }
        guard position < bytes.count, bytes[position] == MermaidByte.newline else { return false }
        position += 1
        while position < bytes.count {
            if bytes[position...].starts(with: fence), position + fence.count >= bytes.count || MermaidByte.isWhitespace(bytes[position + fence.count]) {
                cursor.advance(by: position + fence.count - cursor.position)
                return true
            }
            guard let lineEnd = bytes[position...].firstIndex(of: MermaidByte.newline) else { return false }
            position = lineEnd + 1
        }
        return false
    }

    private static let titleKeyword = Array("title".utf8)
    private static let accessibilityTitleKeyword = Array("accTitle".utf8)
    private static let accessibilityDescriptionKeyword = Array("accDescr".utf8)
    private static let commentStart = Array("%%".utf8)
    private static let directiveStart = Array("%%{".utf8)
    private static let directiveEnd = Array("}%%".utf8)
    private static let fence = Array("---".utf8)
}
