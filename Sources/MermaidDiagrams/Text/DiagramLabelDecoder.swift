/**
 * File: DiagramLabelDecoder.swift
 * -------------------------------
 * Layer: Core
 * Description: Turns the text written for a node, an edge or a group into the lines drawn, as Pele's layoutLabel reads
 *              it: line breaks, HTML's and Markdown's emphasis as spans, other tags dropped, icons left out, codes read.
 *
 * Authors: Félix Chevalier, Bahey Shalash
 * Version: 0.9
 * Date: 24/11/2026
 */

/// Turns the text written for a node, an edge or a group into the lines that are drawn, as Pele's `layoutLabel` reads
/// it (text/label.ts): a text with no markup is one line, trimmed; else it breaks at `<br>`, a written `\n` and a line
/// break, each line trimmed, and each line is read into spans (`DiagramLabelByteMarkup`): emphasis tags and, in a
/// Markdown string, `*` and `_` markers set the spans' emphasis, other HTML tags are dropped, `fa:fa-…` icon names are
/// left out (`DiagramLabelByteEntities`), and entity codes are read (`DiagramLabelEntities`). Spaces inside a line are kept
/// as written, as Pele keeps and measures them.
enum DiagramLabelDecoder {
    /// How the text was written: plain or quoted, or as a Markdown string (`"`…`"`).
    enum Form {
        case plain
        case markdown
        /// Text in which only `<br>` is markup: other tags and icon names stay as written, as a journey's and a timeline's
        /// do (Pele's `plainLabel`).
        case literal
    }

    static func label(from rawText: String, form: Form) -> DiagramLabel {
        let label = decoded(rawText, form: form)
        #if DEBUG
        DiagramLabelDecodingObservation.observer?(rawText, form, label)
        #endif
        return label
    }

    /// The label of the text whose UTF-8 is `bytes`, as `label(from:form:)` reads it, without making a String.
    static func label(fromUTF8 bytes: UnsafeBufferPointer<UInt8>, form: Form) -> DiagramLabel {
        let label = unmarkedLabel(bytes, isLiteral: form == .literal) ?? markedLabel(bytes, form: form)
        #if DEBUG
        DiagramLabelDecodingObservation.observer?(String(decoding: bytes, as: UTF8.self), form, label)
        #endif
        return label
    }

    private static func decoded(_ rawText: String, form: Form) -> DiagramLabel {
        // Most text is one line without markup, which a pass over its bytes finds without reading its characters; its
        // bytes are then kept as they are, trimmed, in the thread's text storage.
        let isLiteral = form == .literal
        let unmarked = rawText.utf8.withContiguousStorageIfAvailable { bytes in unmarkedLabel(bytes, isLiteral: isLiteral) }
            ?? Array(rawText.utf8).withUnsafeBufferPointer { bytes in unmarkedLabel(bytes, isLiteral: isLiteral) }
        if let unmarked { return unmarked }
        return rawText.utf8.withContiguousStorageIfAvailable { bytes in markedLabel(bytes, form: form) }
            ?? Array(rawText.utf8).withUnsafeBufferPointer { bytes in markedLabel(bytes, form: form) }
    }

    /// The label of text with markup, read on its bytes (`DiagramLabelByteDecoder`) with the thread's decoding lists.
    private static func markedLabel(_ bytes: UnsafeBufferPointer<UInt8>, form: Form) -> DiagramLabel {
        DiagramTextThreadState.current.withDecoder { decoder in decoder.label(of: bytes, form: form) }
    }

    /// The label of text Pele reads without markup, one line of its bytes trimmed of JavaScript's white space (empty text
    /// included); nil for text with markup.
    private static func unmarkedLabel(_ bytes: UnsafeBufferPointer<UInt8>, isLiteral: Bool) -> DiagramLabel? {
        guard bytes.isEmpty || DiagramLabelLineBreaks.isUnmarked(bytes, isLiteral: isLiteral) else { return nil }
        let start = JavaScriptWhitespace.endOfRun(in: bytes, from: 0)
        var end = bytes.count
        while end > start, case let length = JavaScriptWhitespace.lengthOfLast(in: bytes[start..<end]), length > 0 { end -= length }
        return DiagramLabelWriting.oneLine(UnsafeBufferPointer(rebasing: bytes[start..<end]), flags: .isReadWithoutMarkup)
    }

    /// The text with each entity code read as Pele reads it (`DiagramLabelEntities`): Mermaid's `#name;` and `#123;`,
    /// HTML's `&name;`, `&#123;` and `&#x7B;`; a code that stands for no character stays as HTML's code.
    static func decodingEntities(_ line: String) -> String {
        DiagramLabelEntities.decoded(line)
    }
}

#if DEBUG
/// What the tests watch of every label decoded in a debug build: the text written, its form and the label made, so that
/// every label of every corpus is checked against the decoding it replaces.
enum DiagramLabelDecodingObservation {
    nonisolated(unsafe) static var observer: ((String, DiagramLabelDecoder.Form, DiagramLabel) -> Void)?
}
#endif
