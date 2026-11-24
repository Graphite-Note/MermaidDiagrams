/**
 * File: DiagramLabelDecoder.swift
 * -------------------------------
 * Layer: Core
 * Description: Turns the text written for a node, an edge or a group into the lines drawn, as Pele's layoutLabel reads
 *              it: line breaks, HTML's and Markdown's emphasis as spans, other tags dropped, icons left out, codes read.
 *
 * Authors: Félix Chevalier, Bahey Shalash
 * Version: 0.6
 * Date: 23/11/2026
 */

/// Turns the text written for a node, an edge or a group into the lines that are drawn, as Pele's `layoutLabel` reads
/// it (text/label.ts): a text with no markup is one line, trimmed; else it breaks at `<br>`, a written `\n` and a line
/// break, each line trimmed, and each line is read into spans (`DiagramLabelInlineMarkup`): emphasis tags and, in a
/// Markdown string, `*` and `_` markers set the spans' emphasis, other HTML tags are dropped, `fa:fa-…` icon names are
/// left out (`DiagramLabelIcons`), and entity codes are read (`DiagramLabelEntities`). Spaces inside a line are kept
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
        if TextPrototypeRecorder.isRecording { TextPrototypeRecorder.recordDecode(rawText: rawText, form: form) }
        guard !rawText.isEmpty else { return DiagramLabel(lines: [rawText]) }
        // Most text is one line without markup, which a pass over its bytes finds without reading its characters; the
        // text is then kept as it is, trimmed.
        let isLiteral = form == .literal
        let isUnmarked = rawText.utf8.withContiguousStorageIfAvailable { bytes in DiagramLabelLineBreaks.isUnmarked(bytes, isLiteral: isLiteral) }
            ?? DiagramLabelLineBreaks.isUnmarked(Array(rawText.utf8), isLiteral: isLiteral)
        if isUnmarked { return DiagramLabel(lines: [JavaScriptStringTrimming.trimmed(rawText)]) }
        var scalars = Array(rawText.unicodeScalars)
        if isLiteral { scalars = DiagramLabelLineBreaks.literalText(scalars) }
        let isMarkdown = form == .markdown
        let source = isMarkdown ? DiagramLabelLineBreaks.markdownSource(scalars) : JavaScriptStringTrimming.trimmed(scalars[...])
        var open: DiagramTextStyle = []
        let lines = DiagramLabelLineBreaks.lines(of: source).map { line in
            DiagramLabelInlineMarkup.spans(of: JavaScriptStringTrimming.trimmed(line), isMarkdown: isMarkdown, open: &open)
        }
        return DiagramLabel(spans: lines)
    }

    /// The text with each entity code read as Pele reads it (`DiagramLabelEntities`): Mermaid's `#name;` and `#123;`,
    /// HTML's `&name;`, `&#123;` and `&#x7B;`; a code that stands for no character stays as HTML's code.
    static func decodingEntities(_ line: String) -> String {
        DiagramLabelEntities.decoded(line)
    }
}
