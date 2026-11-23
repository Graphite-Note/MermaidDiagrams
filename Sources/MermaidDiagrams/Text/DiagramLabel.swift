/**
 * File: DiagramLabel.swift
 * ------------------------
 * Layer: Core
 * Description: The text of a node, an edge or a group as lines already read, and the emphasis of their pieces.
 *
 * Authors: Félix Chevalier, Bahey Shalash
 * Version: 0.2
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
    /// Whether the label is one line Pele reads without markup (no tag, break, marker, icon or code): Pele's layoutLabel
    /// wraps such a line only at a plain space, a Chinese or Japanese character or a break hint, where it wraps a line
    /// read for its markup at any white space (a tab, a no-break space). Not part of the label's equality.
    let isReadWithoutMarkup: Bool

    init(lines: [String]) {
        self.lines = lines
        self.spans = nil
        self.isReadWithoutMarkup = lines.count <= 1
    }

    /// One line of text.
    init(_ text: String) {
        self.lines = [text]
        self.spans = nil
        self.isReadWithoutMarkup = true
    }

    /// Lines read into spans for their markup; the spans are kept only when one of them has an emphasis.
    init(spans: [[DiagramLabelSpan]]) {
        self.lines = spans.map { line in line.map(\.text).joined() }
        self.spans = spans.contains { line in line.contains { span in !span.style.isEmpty } } ? spans : nil
        self.isReadWithoutMarkup = false
    }

    /// Labels are equal when they draw the same lines in the same emphasis, however they were read.
    public static func == (left: DiagramLabel, right: DiagramLabel) -> Bool {
        left.lines == right.lines && left.spans == right.spans
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
