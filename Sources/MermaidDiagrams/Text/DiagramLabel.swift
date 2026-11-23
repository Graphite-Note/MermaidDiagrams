/**
 * File: DiagramLabel.swift
 * ------------------------
 * Layer: Core
 * Description: The text of a node, an edge or a group as lines already read, and the emphasis of their pieces.
 *
 * Authors: Félix Chevalier, Bahey Shalash
 * Version: 0.1
 * Date: 23/11/2026
 */

/// The text of a node, an edge or a group, as lines: Markdown markers, HTML tags and entity codes are already read,
/// and a line ends where the diagram breaks it (`<br>`, or a new line in a Markdown string). Lines are never
/// interpreted again: they are drawn as the characters they hold. A label with bold, italic or monospaced pieces keeps
/// them as spans of its lines, which are measured and drawn each in its emphasis.
public struct DiagramLabel: Equatable, Sendable {
    public let lines: [String]
    /// Each line's pieces in their emphasis, or nil when the whole label is in the text's own font.
    let spans: [[DiagramLabelSpan]]?

    init(lines: [String]) {
        self.lines = lines
        self.spans = nil
    }

    /// One line of text.
    init(_ text: String) {
        self.lines = [text]
        self.spans = nil
    }

    /// Lines read into spans; the spans are kept only when one of them has an emphasis.
    init(spans: [[DiagramLabelSpan]]) {
        self.lines = spans.map { line in line.map(\.text).joined() }
        self.spans = spans.contains { line in line.contains { span in !span.style.isEmpty } } ? spans : nil
    }

    /// Whether the label has nothing to draw.
    public var isEmpty: Bool {
        lines.allSatisfy(\.isEmpty)
    }

    /// The lines joined by spaces, as a screen reader reads them.
    public var spokenText: String {
        lines.filter { line in !line.isEmpty }.joined(separator: " ")
    }

    /// Line `index` as spans: the line's own spans, or the line as one span in the text's own font.
    func spans(ofLine index: Int) -> [DiagramLabelSpan] {
        if let spans { return spans[index] }
        return lines[index].isEmpty ? [] : [DiagramLabelSpan(text: lines[index], style: [])]
    }
}
