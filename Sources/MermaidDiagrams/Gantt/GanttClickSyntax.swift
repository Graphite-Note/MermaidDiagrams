/**
 * File: GanttClickSyntax.swift
 * ----------------------------
 * Layer: Core
 * Description: Reads a Gantt chart's `click` statements as Pele's lexer and parser read them.
 *
 * Authors: Bahey Shalash
 * Version: 0.2
 * Date: 19/11/2026
 */

/// `click ids href "link"`, `click ids call function(args)`, and the two together in either order, as Pele's Gantt grammar
/// reads them: the identifiers are the run of characters before the first space, `call` takes a name up to its opening
/// parenthesis and arguments up to the closing one (`()` has none), both past the end of the line when the parenthesis is
/// not on it, and `href` a link between quotation marks; what follows is the next statement. A statement with neither is a
/// syntax error, as in Pele. Nothing runs: Pele marks the tasks it names as clickable and sets
/// their links, and so does the reader.
struct GanttClick {
    /// The identifiers written, split at commas.
    let identifiers: [String]
    /// The link written after `href`, or nil.
    let link: String?

    /// Reads the statement at the cursor, which `GanttStatementSyntax.isAtClick` found, to the end of its line.
    static func read(_ cursor: inout MermaidTextCursor) throws(MermaidDiagramReadError) -> GanttClick {
        let line = cursor.line
        cursor.advance(by: keyword.count)
        cursor.skipWhitespace()
        let start = cursor.position
        while let byte = cursor.peek(), !GanttStatementSyntax.isWhitespace(byte) { cursor.advance() }
        let identifiers = cursor.text(from: start, to: cursor.position).split(separator: ",", omittingEmptySubsequences: false).map(String.init)
        cursor.skipSpaces()
        var link: String?
        var hasCall = false
        for _ in 0..<2 {
            if link == nil, cursor.hasCaseInsensitivePrefix(href), let quote = followingQuote(cursor, afterKeyword: href.count) {
                cursor.advance(by: quote + 1)
                let linkStart = cursor.position
                while let byte = cursor.peek(), byte != MermaidByte.quotationMark { cursor.advance() }
                link = cursor.text(from: linkStart, to: cursor.position)
                if cursor.peek() == MermaidByte.quotationMark { cursor.advance() }
            } else if !hasCall, cursor.hasCaseInsensitivePrefix(call), let separator = cursor.peek(call.count), GanttStatementSyntax.isWhitespace(separator) {
                hasCall = true
                cursor.advance(by: call.count)
                cursor.skipWhitespace()
                // As in Pele's lexer, the name runs to its opening parenthesis and the arguments to the closing one, past the
                // line's end and to the text's end when there is none.
                while let byte = cursor.peek(), byte != parenthesis { cursor.advance() }
                if cursor.peek() == parenthesis { while let byte = cursor.peek(), byte != closingParenthesis { cursor.advance() } }
                if cursor.peek() == closingParenthesis { cursor.advance() }
            } else {
                break
            }
            cursor.skipSpaces()
        }
        guard link != nil || hasCall else { throw .invalidSyntax(line: line, problem: .unexpectedText(cursor.excerpt())) }
        // What follows on the line is read as the next statement, as Pele's parser reads the next token.
        return GanttClick(identifiers: identifiers, link: link)
    }

    /// The offset of the quotation mark after `href` and the spaces that follow it (at least one), or nil.
    private static func followingQuote(_ cursor: MermaidTextCursor, afterKeyword length: Int) -> Int? {
        guard let first = cursor.peek(length), GanttStatementSyntax.isWhitespace(first) else { return nil }
        var offset = length
        while let byte = cursor.peek(offset), GanttStatementSyntax.isWhitespace(byte) { offset += 1 }
        return cursor.peek(offset) == MermaidByte.quotationMark ? offset : nil
    }

    private static let keyword = Array("click".utf8)
    private static let href = Array("href".utf8)
    private static let call = Array("call".utf8)
    private static let parenthesis = UInt8(ascii: "(")
    private static let closingParenthesis = UInt8(ascii: ")")
}
