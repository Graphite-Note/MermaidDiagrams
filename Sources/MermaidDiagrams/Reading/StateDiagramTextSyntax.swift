/**
 * File: StateDiagramTextSyntax.swift
 * ----------------------------------
 * Layer: Core
 * Description: The pieces of a state diagram's statements read on its bytes: state references as ranges of the text,
 *              the text after a colon and quoted text, kept as ranges where the label decoder reads them as written,
 *              and the labels made of the others without a String in a text of ASCII bytes.
 *
 * Authors: felixchvl, Bahey Shalash
 * Version: 0.3
 * Date: 26/11/2026
 */

import Foundation

/// A state as a statement names it: `[*]`, which is a start or an end by where it stands, an identifier as a range of
/// the text, or, in a text beyond ASCII, an identifier trimmed as Foundation trims text (`state "text" as Id:more`).
enum StateDiagramStateReference: Equatable {
    case startOrEnd
    case named(MermaidTextRange)
    case written(String)
}

/// A text read for a state, a transition or a note: a range of the text that the label decoder reads as written, or the
/// label it decoded.
enum StateDiagramReadText: Equatable {
    case range(MermaidTextRange)
    case label(DiagramLabel)

    /// Whether the text draws no line: a range of white space alone (in ASCII, the decoder trims JavaScript's white
    /// space, the space and tab to carriage return), or an empty label.
    func isEmpty(in bytes: GraphDiagramBytes) -> Bool {
        switch self {
        case .label(let label): return label.isEmpty
        case .range(let range):
            for index in range.lowerBound..<range.upperBound {
                let byte = bytes.buffer[index]
                if byte != MermaidByte.space, !(0x09...0x0D).contains(byte) { return false }
            }
            return true
        }
    }
}

/// Reads the pieces of a state diagram's statements: state references, the text after a colon, and quoted text. An
/// identifier runs to a space, a line break, a colon, a hyphen, a brace or a semicolon, and stops before `%%`, which
/// starts a comment, as in Mermaid's grammar (so `step-1` is not one identifier). Text is Markdown, where `<br>`, a
/// line break and the two characters `\n` all end a line.
enum StateDiagramTextSyntax {
    /// `[*]` or an identifier at the position, or nil when there is neither.
    static func readReference(_ bytes: inout GraphDiagramBytes) -> StateDiagramStateReference? {
        if bytes.isAt(MermaidByte.openingBracket, asterisk, MermaidByte.closingBracket) {
            bytes.advance(by: 3)
            return .startOrEnd
        }
        return readIdentifier(&bytes).map(StateDiagramStateReference.named)
    }

    /// An identifier at the position, or nil when the position is at a byte that ends one.
    static func readIdentifier(_ bytes: inout GraphDiagramBytes) -> MermaidTextRange? {
        let start = bytes.position
        while let byte = bytes.peek(), !endsIdentifier(byte), !bytes.isAtCommentStart { bytes.advance() }
        return bytes.position > start ? MermaidTextRange(start: start, end: bytes.position) : nil
    }

    /// Whether `byte` ends an identifier.
    @inline(__always) static func endsIdentifier(_ byte: UInt8) -> Bool {
        MermaidByte.isWhitespace(byte) || byte == MermaidByte.colon || byte == MermaidByte.hyphen || byte == MermaidByte.openingBrace
            || byte == MermaidByte.semicolon
    }

    /// The text after a colon at the position (`A : text`, `A --> B : text`), to the end of the line or a semicolon,
    /// or nil when no colon is there or nothing but spaces follows it. Only the first colon is taken off: the text
    /// may hold others (`error (ex: timeout)`).
    static func readColonText(_ bytes: inout GraphDiagramBytes) -> StateDiagramReadText? {
        guard bytes.peek() == MermaidByte.colon else { return nil }
        bytes.advance()
        let start = bytes.position
        while let byte = bytes.peek(), byte != MermaidByte.newline, byte != MermaidByte.semicolon { bytes.advance() }
        let text = bytes.trimmed(from: start, to: bytes.position)
        return text.isEmpty ? nil : self.text(bytes, text)
    }

    /// The range of the text between quotation marks at the position, which may run over several lines; the position
    /// moves past the closing mark. Nil when the position is not at a quotation mark.
    static func readQuotedText(_ bytes: inout GraphDiagramBytes) throws(MermaidDiagramReadError) -> MermaidTextRange? {
        guard bytes.peek() == MermaidByte.quotationMark else { return nil }
        let opening = bytes
        bytes.advance()
        let start = bytes.position
        while let byte = bytes.peek(), byte != MermaidByte.quotationMark { bytes.advance() }
        guard !bytes.isAtEnd else { throw .invalidSyntax(line: opening.line, problem: .unclosedQuotation) }
        let text = MermaidTextRange(start: start, end: bytes.position)
        bytes.advance()
        return text
    }

    /// Whether the word at the position is `word` in any case, followed by a space, a line break or the end, so that
    /// `assemble` is not `as` and `classroom` is not `class`. `word` is lowercase.
    static func isAtKeyword(_ bytes: GraphDiagramBytes, _ word: StaticString) -> Bool {
        guard bytes.hasCaseInsensitivePrefix(word) else { return false }
        guard let next = bytes.peek(word.utf8CodeUnitCount) else { return true }
        return MermaidByte.isWhitespace(next)
    }

    /// The text of `range`, written for a state, a transition or a note: the range itself when the label decoder reads
    /// it as written (ASCII without markup: one line, trimmed), else its label (`label(_:_:)`).
    static func text(_ bytes: GraphDiagramBytes, _ range: MermaidTextRange) -> StateDiagramReadText {
        guard bytes.isASCII, DiagramLabelLineBreaks.isUnmarked(UnsafeBufferPointer(rebasing: bytes.buffer[range.lowerBound..<range.upperBound]),
                                                                isLiteral: false) else {
            return .label(label(bytes, range))
        }
        return .range(range)
    }

    /// The drawn lines of the text of `range`, written for a state, a transition or a note: made from the bytes in a
    /// text of ASCII bytes, from a String as 0.7.0 made it otherwise, where Foundation finds `\n` by characters.
    static func label(_ bytes: GraphDiagramBytes, _ range: MermaidTextRange) -> DiagramLabel {
        guard bytes.isASCII else { return label(from: bytes.text(range)) }
        var hasEscapedLineBreak = false
        var hasEmphasisMarkers = false
        var index = range.lowerBound
        while index < range.upperBound {
            let byte = bytes.buffer[index]
            if byte == asterisk || byte == MermaidByte.underscore { hasEmphasisMarkers = true }
            if byte == backslash, index + 1 < range.upperBound, bytes.buffer[index + 1] == letterN { hasEscapedLineBreak = true }
            index += 1
        }
        let form: DiagramLabelDecoder.Form = hasEmphasisMarkers ? .markdown : .plain
        let text = UnsafeBufferPointer(rebasing: bytes.buffer[range.lowerBound..<range.upperBound])
        guard hasEscapedLineBreak else { return DiagramLabelDecoder.label(fromUTF8: text, form: form) }
        return withLineBreaks(text).withUnsafeBufferPointer { written in DiagramLabelDecoder.label(fromUTF8: written, form: form) }
    }

    /// `text` with each `\n` written as a line break, left to right, as `replacingOccurrences(of:with:)` writes it.
    private static func withLineBreaks(_ text: UnsafeBufferPointer<UInt8>) -> [UInt8] {
        var written: [UInt8] = []
        written.reserveCapacity(text.count)
        var index = 0
        while index < text.count {
            if text[index] == backslash, index + 1 < text.count, text[index + 1] == letterN {
                written.append(MermaidByte.newline)
                index += 2
            } else {
                written.append(text[index])
                index += 1
            }
        }
        return written
    }

    /// The drawn lines of `text`, as 0.7.0 made them.
    static func label(from text: String) -> DiagramLabel {
        let withLineBreaks = text.contains("\\n") ? text.replacingOccurrences(of: "\\n", with: "\n") : text
        // Without emphasis markers, Markdown text reads as plain text, which skips the decoder when it is one plain line.
        let hasEmphasisMarkers = withLineBreaks.utf8.contains { byte in byte == UInt8(ascii: "*") || byte == MermaidByte.underscore }
        return DiagramLabelDecoder.label(from: withLineBreaks, form: hasEmphasisMarkers ? .markdown : .plain)
    }

    static let asterisk = UInt8(ascii: "*")
    static let backslash = UInt8(ascii: "\\")
    static let letterN = UInt8(ascii: "n")
}
