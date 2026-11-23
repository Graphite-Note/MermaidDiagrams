/**
 * File: FlowchartTextSyntax.swift
 * -------------------------------
 * Layer: Core
 * Description: Reads the text inside a flowchart node's brackets or an edge's bars as Pele's lexer reads it: a string,
 *              a Markdown string or plain text, which may hold no bracket.
 *
 * Authors: Félix Chevalier, Bahey Shalash
 * Version: 0.2
 * Date: 23/11/2026
 */

import Foundation

/// The lexer state Pele reads a node's text in (flowchart/lexer.ts): `text` after most brackets and between an edge's
/// bars, `trapezoid` after `[/` and `[\`, `ellipse` after `(-`. Each ends a run of plain text at its own characters.
enum FlowchartTextState {
    case text
    case trapezoid
    case ellipse

    /// Whether plain text in this state stops at `byte`: a bracket, a brace or a parenthesis in all three, a vertical
    /// bar in `text`, a quotation mark in `text` and `ellipse`, which opens a string there.
    func endsPlainText(_ byte: UInt8) -> Bool {
        switch byte {
        case UInt8(ascii: "("), UInt8(ascii: ")"), MermaidByte.openingBracket, MermaidByte.closingBracket, MermaidByte.openingBrace,
             MermaidByte.closingBrace: true
        case MermaidByte.verticalBar: self == .text
        case MermaidByte.quotationMark: self != .trapezoid
        default: false
        }
    }
}

/// Reads the text written inside a node's brackets or an edge's bars as Pele's grammar reads it (flowchart/parser.ts
/// `text`): a string (`"…"`) or a Markdown string (`"`…`"`), which may hold any bracket, and plain text after it; or plain
/// text alone. Plain text holds no bracket, brace, parenthesis, vertical bar or quotation mark (`A[a (b) c]` is refused,
/// as Mermaid's specs expect), and the text is not empty (`A[]` is refused).
enum FlowchartTextSyntax {
    /// Reads text up to the first of `closings` and moves past it. Returns the label and which closing ended it.
    /// - Parameter openingLine: The line of the opening bracket, which an unclosed text is reported on.
    static func readText(_ cursor: inout MermaidTextCursor, closedByAnyOf closings: [[UInt8]], state: FlowchartTextState = .text,
                         openingLine: Int) throws(MermaidDiagramReadError) -> (DiagramLabel, Int) {
        if startsInvisibleLink(cursor) { throw .invalidSyntax(line: cursor.line, problem: .unexpectedText(cursor.excerpt())) }
        var written = ""
        var form = DiagramLabelDecoder.Form.plain
        var hasToken = false
        if cursor.peek() == MermaidByte.quotationMark {
            let string = try readString(&cursor, openingLine: openingLine)
            written = string.text
            form = string.form
            hasToken = !string.text.isEmpty
        }
        let plainStart = cursor.position
        while let byte = cursor.peek(), closings.firstIndex(where: { closing in cursor.hasPrefix(closing) }) == nil, !state.endsPlainText(byte) {
            cursor.advance()
        }
        if cursor.position > plainStart {
            written += cursor.text(from: plainStart, to: cursor.position)
            hasToken = true
        }
        guard let closingIndex = closings.firstIndex(where: { closing in cursor.hasPrefix(closing) }) else {
            throw .invalidSyntax(line: cursor.isAtEnd ? openingLine : cursor.line,
                                 problem: cursor.isAtEnd ? .unclosedShape(closingText: closingText(closings)) : .unexpectedText(cursor.excerpt()))
        }
        // Pele's `text` takes at least one token: a closing right after the opening, or after an empty string, is refused.
        guard hasToken else { throw .invalidSyntax(line: cursor.line, problem: .unexpectedText(cursor.excerpt())) }
        cursor.advance(by: closings[closingIndex].count)
        let trimmed = written.trimmingCharacters(in: .whitespacesAndNewlines)
        return (DiagramLabelDecoder.label(from: trimmed, form: form), closingIndex)
    }

    /// `"…"`, its text without the quotation marks, or `"`…`"`, a Markdown string, which holds no backtick and no
    /// quotation mark (Pele's lexer refuses a lone backtick there and reads a quotation mark as another string).
    private static func readString(_ cursor: inout MermaidTextCursor,
                                   openingLine: Int) throws(MermaidDiagramReadError) -> (text: String, form: DiagramLabelDecoder.Form) {
        cursor.advance()
        let isMarkdown = cursor.peek() == MermaidByte.graveAccent
        if isMarkdown { cursor.advance() }
        let start = cursor.position
        while let byte = cursor.peek(), byte != MermaidByte.quotationMark, !(isMarkdown && byte == MermaidByte.graveAccent) { cursor.advance() }
        let text = cursor.text(from: start, to: cursor.position)
        if isMarkdown {
            guard cursor.peek() == MermaidByte.graveAccent, cursor.peek(1) == MermaidByte.quotationMark else {
                throw .invalidSyntax(line: cursor.isAtEnd ? openingLine : cursor.line,
                                     problem: cursor.isAtEnd ? .unclosedQuotation : .unexpectedText(cursor.excerpt()))
            }
            cursor.advance(by: 2)
            return (text, .markdown)
        }
        guard !cursor.isAtEnd else { throw .invalidSyntax(line: openingLine, problem: .unclosedQuotation) }
        cursor.advance()
        return (text, .plain)
    }

    /// Whether the text starts with an invisible link (`~~~`, after any spaces), which Pele's lexer reads as a link
    /// even there.
    private static func startsInvisibleLink(_ cursor: MermaidTextCursor) -> Bool {
        var lookahead = cursor
        while let byte = lookahead.peek(), JavaScriptWhitespace.length(in: lookahead.bytes, at: lookahead.position) > 0 || byte == MermaidByte.tilde {
            if byte == MermaidByte.tilde { return lookahead.peek(1) == MermaidByte.tilde && lookahead.peek(2) == MermaidByte.tilde }
            lookahead.advance(by: JavaScriptWhitespace.length(in: lookahead.bytes, at: lookahead.position))
        }
        return false
    }

    /// Text between quotation marks loses them; a Markdown string (`"`…`"`) loses its backticks too.
    static func unquoted(_ written: String) -> (text: String, form: DiagramLabelDecoder.Form) {
        guard written.count >= 2, written.hasPrefix("\""), written.hasSuffix("\"") else { return (written, .plain) }
        let inside = written.dropFirst().dropLast()
        if inside.count >= 2, inside.hasPrefix("`"), inside.hasSuffix("`") {
            return (String(inside.dropFirst().dropLast()), .markdown)
        }
        return (String(inside), .plain)
    }

    private static func closingText(_ closings: [[UInt8]]) -> String {
        String(decoding: closings.first ?? [], as: UTF8.self)
    }
}
