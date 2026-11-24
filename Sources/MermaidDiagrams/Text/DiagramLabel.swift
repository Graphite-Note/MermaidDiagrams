/**
 * File: DiagramLabel.swift
 * ------------------------
 * Layer: Core
 * Description: The text of a node, an edge or a group as lines already read, and the emphasis of their pieces, kept as
 *              byte ranges of a text storage: a label holds no String and no list of its own.
 *
 * Authors: Félix Chevalier, Bahey Shalash
 * Version: 0.5
 * Date: 24/11/2026
 */

/// The text of a node, an edge or a group, as lines: Markdown markers, HTML tags and entity codes are already read,
/// and a line ends where the diagram breaks it (`<br>`, or a new line in a Markdown string). Lines are never
/// interpreted again: they are drawn as the characters they hold. A label with bold, italic or monospaced pieces keeps
/// them as spans of its lines, which are measured and drawn each in its emphasis.
///
/// The lines are UTF-8 bytes in a `DiagramTextStorage` that the label refers to, written once by the thread that read
/// the label and shared with the other labels and blocks it wrote: copying a label retains one reference, and its lines
/// and spans are made as Strings only when they are read.
public struct DiagramLabel: Equatable, Sendable {
    let storage: DiagramTextStorage
    let record: DiagramLabelRecord

    init(storage: DiagramTextStorage, record: DiagramLabelRecord) {
        self.storage = storage
        self.record = record
    }

    init(lines: [String]) {
        self = DiagramLabelWriting.label(lines: lines, flags: lines.count <= 1 ? .isReadWithoutMarkup : [])
    }

    /// One line of text.
    init(_ text: String) {
        self = DiagramLabelWriting.label(lines: [text], flags: .isReadWithoutMarkup)
    }

    /// Lines read into spans for their markup; the spans are kept only when one of them has an emphasis.
    init(spans: [[DiagramLabelSpan]]) {
        self = DiagramLabelWriting.label(spans: spans)
    }

    /// The lines, made as Strings when read.
    public var lines: [String] {
        (0..<lineCount).map { index in withUTF8(ofLine: index) { bytes in String(decoding: bytes, as: UTF8.self) } }
    }

    /// How many lines the label has.
    public var lineCount: Int { Int(record.lineCount) }

    /// The UTF-8 bytes of line `index`, valid in `body` only; `index` is below `lineCount`, as an array's would be.
    public func withUTF8<Result>(ofLine index: Int, _ body: (UnsafeBufferPointer<UInt8>) throws -> Result) rethrows -> Result {
        precondition(index >= 0 && index < lineCount, "line index out of range")
        let range = lineRange(at: index)
        return try withExtendedLifetime(storage) { try body(storage.bytes(from: range.start, to: range.end)) }
    }

    /// Where line `index`'s bytes are in the storage.
    @inline(__always)
    func lineRange(at index: Int) -> (start: Int32, end: Int32) {
        if record.flags.contains(.isOneLine) { return (record.first, record.end) }
        let line = storage.record(at: record.first, index: index, as: DiagramLabelLineRecord.self)
        return (line.start, line.end)
    }

    /// The line record of line `index`; the label is not one line without spans.
    func lineRecord(at index: Int) -> DiagramLabelLineRecord {
        storage.record(at: record.first, index: index, as: DiagramLabelLineRecord.self)
    }

    /// Whether the label's lines have spans, one of them with an emphasis.
    var hasSpans: Bool { record.flags.contains(.hasSpans) }

    /// Whether the label is one line Pele reads without markup (no tag, break, marker, icon or code): Pele's layoutLabel
    /// wraps such a line only at a plain space, a Chinese or Japanese character or a break hint, where it wraps a line
    /// read for its markup at any white space (a tab, a no-break space). Not part of the label's equality.
    var isReadWithoutMarkup: Bool { record.flags.contains(.isReadWithoutMarkup) }

    /// Each line's pieces in their emphasis, or nil when the whole label is in the text's own font.
    var spans: [[DiagramLabelSpan]]? {
        hasSpans ? (0..<lineCount).map { index in spans(ofLine: index) } : nil
    }

    /// Line `index` as spans: the line's own spans, or the line as one span in the text's own font.
    func spans(ofLine index: Int) -> [DiagramLabelSpan] {
        guard hasSpans else {
            let text = withUTF8(ofLine: index) { bytes in String(decoding: bytes, as: UTF8.self) }
            return text.isEmpty ? [] : [DiagramLabelSpan(text: text, style: [])]
        }
        let line = lineRecord(at: index)
        return (0..<Int(line.spanCount)).map { spanIndex in
            let span = storage.record(at: line.firstSpan, index: spanIndex, as: DiagramLabelSpanRecord.self)
            return DiagramLabelSpan(text: String(decoding: storage.bytes(from: span.start, to: span.end), as: UTF8.self), style: span.style)
        }
    }

    /// Labels are equal when they draw the same lines in the same emphasis, however they were read: lines and spans
    /// compare as Strings do.
    public static func == (left: DiagramLabel, right: DiagramLabel) -> Bool {
        guard left.lineCount == right.lineCount, left.hasSpans == right.hasSpans else { return false }
        for index in 0..<left.lineCount {
            let isSame = left.withUTF8(ofLine: index) { leftBytes in
                right.withUTF8(ofLine: index) { rightBytes in DiagramTextBytes.areEqualAsText(leftBytes, rightBytes) }
            }
            guard isSame else { return false }
        }
        return !left.hasSpans || left.spans == right.spans
    }

    /// Whether the label has nothing to draw.
    public var isEmpty: Bool {
        (0..<lineCount).allSatisfy { index in
            let range = lineRange(at: index)
            return range.start == range.end
        }
    }

    /// The lines joined by spaces, as a screen reader reads them; a label of one line, most labels, is that line.
    public var spokenText: String {
        guard lineCount != 1 else { return withUTF8(ofLine: 0) { bytes in String(decoding: bytes, as: UTF8.self) } }
        var byteCount = 0
        for index in 0..<lineCount {
            let range = lineRange(at: index)
            if range.end > range.start { byteCount += Int(range.end - range.start) + 1 }
        }
        return String(unsafeUninitializedCapacity: max(byteCount - 1, 0)) { buffer in
            var written = 0
            for index in 0..<lineCount {
                let range = lineRange(at: index)
                guard range.end > range.start else { continue }
                if written > 0 {
                    buffer[written] = UInt8(ascii: " ")
                    written += 1
                }
                let bytes = storage.bytes(from: range.start, to: range.end)
                _ = UnsafeMutableBufferPointer(rebasing: buffer[written..<(written + bytes.count)]).initialize(from: bytes)
                written += bytes.count
            }
            return written
        }
    }
}
