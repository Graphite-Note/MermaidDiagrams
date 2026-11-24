/**
 * File: FlowchartTextSyntax.swift
 * -------------------------------
 * Layer: Core
 * Description: Reads the text written inside a node's brackets or an edge's bars as Pele's grammar reads it, on bytes:
 *              a string, a Markdown string, plain text or a string and plain text, kept as a range of the text.
 *
 * Authors: Félix Chevalier, Bahey Shalash
 * Version: 0.4
 * Date: 24/11/2026
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
extension FlowchartParser {
    /// Reads text up to the first of `closings` and moves past it. Returns the label and which closing ended it.
    /// - Parameter opening: Where the opening bracket stands, whose line an unclosed text is reported on.
    mutating func readText(closedBy closings: FlowchartClosings, state: FlowchartTextState = .text,
                           openedAt opening: Int) throws(MermaidDiagramReadError) -> (FlowchartLabelReference, Int) {
        if startsInvisibleLink() { throw .invalidSyntax(line: bytes.line(at: position), problem: .unexpectedText(bytes.excerpt(at: position))) }
        var string: (range: Range<Int>, form: DiagramLabelDecoder.Form)?
        if bytes[position] == MermaidByte.quotationMark, position < bytes.count { string = try readString(openedAt: opening) }
        let plainStart = position
        // Bytes that may end plain text: the state's own and the closings' first bytes; any other is passed by a mask.
        let stops = closings.stopMask(state: state)
        while position < bytes.count {
            let byte = bytes.base[position]
            if stops.contains(byte), closings.match(in: bytes, at: position) != nil || state.endsPlainText(byte) { break }
            position += 1
        }
        let plainEnd = position
        guard let closing = closings.match(in: bytes, at: position) else {
            let isAtEnd = position >= bytes.count
            throw .invalidSyntax(line: bytes.line(at: isAtEnd ? opening : position),
                                 problem: isAtEnd ? .unclosedShape(closingText: closings.firstText) : .unexpectedText(bytes.excerpt(at: position)))
        }
        // Pele's `text` takes at least one token: a closing right after the opening, or after an empty string, is refused.
        guard plainEnd > plainStart || !(string?.range.isEmpty ?? true) else {
            throw .invalidSyntax(line: bytes.line(at: position), problem: .unexpectedText(bytes.excerpt(at: position)))
        }
        position += closings.length(closing)
        guard let string else { return (writtenLabel(foundationTrimmed(plainStart..<plainEnd), form: .plain), closing) }
        guard plainEnd == plainStart else {
            // A string followed by plain text: their joined text is decoded as 0.7.0 decoded it.
            let joined = bytes.string(from: string.range.lowerBound, to: string.range.upperBound) + bytes.string(from: plainStart, to: plainEnd)
            let trimmed = MermaidByte.startsAndEndsWithPrintableASCII(joined) ? joined : joined.trimmingCharacters(in: .whitespacesAndNewlines)
            return (decoded(DiagramLabelDecoder.label(from: trimmed, form: string.form)), closing)
        }
        return (writtenLabel(foundationTrimmed(string.range), form: string.form), closing)
    }

    /// `"…"`, its text without the quotation marks, or `"`…`"`, a Markdown string, which holds no backtick and no
    /// quotation mark (Pele's lexer refuses a lone backtick there and reads a quotation mark as another string).
    private mutating func readString(openedAt opening: Int) throws(MermaidDiagramReadError) -> (range: Range<Int>, form: DiagramLabelDecoder.Form) {
        position += 1
        let isMarkdown = bytes[position] == MermaidByte.graveAccent
        if isMarkdown { position += 1 }
        let start = position
        while position < bytes.count, case let byte = bytes.base[position], byte != MermaidByte.quotationMark,
              !(isMarkdown && byte == MermaidByte.graveAccent) { position += 1 }
        let end = position
        let isAtEnd = position >= bytes.count
        if isMarkdown {
            guard bytes[position] == MermaidByte.graveAccent, bytes[position + 1] == MermaidByte.quotationMark, position + 1 < bytes.count else {
                throw .invalidSyntax(line: bytes.line(at: isAtEnd ? opening : position),
                                     problem: isAtEnd ? .unclosedQuotation : .unexpectedText(bytes.excerpt(at: position)))
            }
            position += 2
            return (start..<end, .markdown)
        }
        guard !isAtEnd else { throw .invalidSyntax(line: bytes.line(at: opening), problem: .unclosedQuotation) }
        position += 1
        return (start..<end, .plain)
    }

    /// Whether the text starts with an invisible link (`~~~`, after any white space), which Pele's lexer reads as a link
    /// even there.
    private func startsInvisibleLink() -> Bool {
        var lookahead = position
        while lookahead < bytes.count {
            if bytes.base[lookahead] == MermaidByte.tilde { return bytes[lookahead + 1] == MermaidByte.tilde && bytes[lookahead + 2] == MermaidByte.tilde }
            let length = bytes.whitespaceLength(at: lookahead)
            guard length > 0 else { return false }
            lookahead += length
        }
        return false
    }

    /// `written` without the white space and line breaks Foundation trims (`trimmingCharacters(in: .whitespacesAndNewlines)`),
    /// unless it starts and ends with printable ASCII, as 0.7.0's text was trimmed before it was decoded.
    private func foundationTrimmed(_ written: Range<Int>) -> Range<Int> {
        var start = written.lowerBound
        var end = written.upperBound
        guard start < end, !(Self.isPrintableASCII(bytes.base[start]) && Self.isPrintableASCII(bytes.base[end - 1])) else { return written }
        while start < end {
            let length = foundationWhitespaceLength(at: start)
            guard length > 0 else { break }
            start += length
        }
        while end > start {
            var lead = end - 1
            while lead > start, bytes.base[lead] & 0xC0 == 0x80 { lead -= 1 }
            guard foundationWhitespaceLength(at: lead) == end - lead else { break }
            end = lead
        }
        return start..<end
    }

    /// The length of the character at `position` when Foundation's `whitespacesAndNewlines` holds it, else 0.
    private func foundationWhitespaceLength(at position: Int) -> Int {
        let byte = bytes.base[position]
        if byte < 0x80 { return Self.isASCIIWhitespace(byte) ? 1 : 0 }
        guard let (scalar, length) = bytes.scalar(at: position), CharacterSet.whitespacesAndNewlines.contains(scalar) else { return 0 }
        return length
    }

    @inline(__always) static func isASCIIWhitespace(_ byte: UInt8) -> Bool {
        byte == 0x20 || (byte >= 0x09 && byte <= 0x0D)
    }

    @inline(__always) static func isPrintableASCII(_ byte: UInt8) -> Bool {
        byte > 0x20 && byte < 0x7F
    }

    /// The label `DiagramLabelDecoder` makes of the text at `raw` in `form`, by reference: a text without markup is
    /// its one line, trimmed as JavaScript trims (on bytes when its ends are ASCII); a text with markup is decoded when
    /// it is read.
    mutating func writtenLabel(_ raw: Range<Int>, form: DiagramLabelDecoder.Form) -> FlowchartLabelReference {
        let rawRange = MermaidTextRange(start: raw.lowerBound, end: raw.upperBound)
        guard DiagramLabelLineBreaks.isUnmarked(UnsafeBufferPointer(rebasing: bytes.buffer[raw]), isLiteral: false) else {
            return FlowchartLabelReference(kind: form == .markdown ? .markdown : .plain, range: rawRange)
        }
        var start = raw.lowerBound
        var end = raw.upperBound
        while start < end, Self.isASCIIWhitespace(bytes.base[start]) { start += 1 }
        while end > start, Self.isASCIIWhitespace(bytes.base[end - 1]) { end -= 1 }
        // White space beyond ASCII at an end: the decoder trims it as JavaScript does when the label is read.
        if start < end, bytes.base[start] >= 0x80 || bytes.base[end - 1] >= 0x80 { return FlowchartLabelReference(kind: .plain, range: rawRange) }
        return FlowchartLabelReference(kind: .line, range: MermaidTextRange(start: start, end: end))
    }

    /// A label decoded while reading, kept by its index.
    mutating func decoded(_ label: DiagramLabel) -> FlowchartLabelReference {
        parts.rare.decodedLabels.append(label)
        return .decoded(at: parts.rare.decodedLabels.count - 1)
    }

    /// `written` without its quotation marks (`"…"`) and, inside them, a Markdown string's backticks, on bytes: the
    /// text and its form. ASCII text only, whose characters are its bytes.
    func unquotedRange(_ written: Range<Int>) -> (range: Range<Int>, form: DiagramLabelDecoder.Form) {
        var start = written.lowerBound
        var end = written.upperBound
        guard end - start >= 2, bytes.base[start] == MermaidByte.quotationMark, bytes.base[end - 1] == MermaidByte.quotationMark else { return (written, .plain) }
        start += 1
        end -= 1
        guard end - start >= 2, bytes.base[start] == MermaidByte.graveAccent, bytes.base[end - 1] == MermaidByte.graveAccent else { return (start..<end, .plain) }
        return ((start + 1)..<(end - 1), .markdown)
    }

    /// Whether the bytes of `range` are all ASCII.
    func isASCII(_ range: Range<Int>) -> Bool {
        for index in range where bytes.base[index] >= 0x80 { return false }
        return true
    }
}

/// Text between quotation marks loses them; a Markdown string (`"`…`"`) loses its backticks too.
enum FlowchartTextSyntax {
    static func unquoted(_ written: String) -> (text: String, form: DiagramLabelDecoder.Form) {
        guard written.count >= 2, written.hasPrefix("\""), written.hasSuffix("\"") else { return (written, .plain) }
        let inside = written.dropFirst().dropLast()
        if inside.count >= 2, inside.hasPrefix("`"), inside.hasSuffix("`") {
            return (String(inside.dropFirst().dropLast()), .markdown)
        }
        return (String(inside), .plain)
    }
}
