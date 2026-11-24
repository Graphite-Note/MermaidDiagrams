/**
 * File: DiagramLabelWriting.swift
 * -------------------------------
 * Layer: Core
 * Description: Writes a label's lines and spans into the thread's text storage, one line without spans as a byte range
 *              alone; and compares two texts' bytes as Strings compare them.
 *
 * Authors: Bahey Shalash
 * Version: 0.2
 * Date: 24/11/2026
 */

/// A label's lines and spans written into the current thread's storage.
enum DiagramLabelWriting {
    /// A label of `lines`, without spans.
    static func label(lines: [String], flags: DiagramLabelFlags) -> DiagramLabel {
        if lines.count == 1 { return oneLine(lines[0], flags: flags) }
        let byteCount = lines.reduce(0) { total, line in total + line.utf8.count }
        let state = DiagramTextThreadState.current
        let storage = state.storage(forBytes: byteCount, recordBytes: DiagramTextStorage.recordByteCount(lines.count, of: DiagramLabelLineRecord.self))
        let first = storage.reserveRecords(count: lines.count, of: DiagramLabelLineRecord.self)
        for (index, line) in lines.enumerated() {
            let start = append(line, to: storage)
            storage.setRecord(DiagramLabelLineRecord(start: start, end: start + Int32(line.utf8.count), firstSpan: 0, spanCount: 0), at: first,
                              index: index)
        }
        return DiagramLabel(storage: storage, record: DiagramLabelRecord(first: first, end: 0, lineCount: Int32(lines.count), flags: flags))
    }

    /// A label of one line without spans: its bytes' range alone, no record.
    static func oneLine(_ line: String, flags: DiagramLabelFlags) -> DiagramLabel {
        let storage = DiagramTextThreadState.current.storage(forBytes: line.utf8.count, recordBytes: 0)
        let start = append(line, to: storage)
        return DiagramLabel(storage: storage, record: DiagramLabelRecord(first: start, end: start + Int32(line.utf8.count), lineCount: 1,
                                                                         flags: flags.union(.isOneLine)))
    }

    /// A label of one line of `bytes` without spans.
    static func oneLine(_ bytes: UnsafeBufferPointer<UInt8>, flags: DiagramLabelFlags) -> DiagramLabel {
        let storage = DiagramTextThreadState.current.storage(forBytes: bytes.count, recordBytes: 0)
        let start = storage.append(bytes)
        return DiagramLabel(storage: storage, record: DiagramLabelRecord(first: start, end: start + Int32(bytes.count), lineCount: 1,
                                                                         flags: flags.union(.isOneLine)))
    }

    /// A label of lines read into spans, never read without markup: the spans kept only when one has an emphasis.
    static func label(spans lines: [[DiagramLabelSpan]]) -> DiagramLabel {
        let hasEmphasis = lines.contains { line in line.contains { span in !span.style.isEmpty } }
        guard hasEmphasis else { return label(lines: lines.map { line in line.map(\.text).joined() }, flags: []) }
        let spanCount = lines.reduce(0) { total, line in total + line.count }
        let byteCount = lines.reduce(0) { total, line in line.reduce(total) { total, span in total + span.text.utf8.count } }
        let recordBytes = DiagramTextStorage.recordByteCount(lines.count, of: DiagramLabelLineRecord.self)
            + DiagramTextStorage.recordByteCount(spanCount, of: DiagramLabelSpanRecord.self)
        let storage = DiagramTextThreadState.current.storage(forBytes: byteCount, recordBytes: recordBytes)
        let first = storage.reserveRecords(count: lines.count, of: DiagramLabelLineRecord.self)
        let firstSpan = storage.reserveRecords(count: spanCount, of: DiagramLabelSpanRecord.self)
        var spanIndex = 0
        for (index, line) in lines.enumerated() {
            let lineFirstSpan = firstSpan + Int32(spanIndex * MemoryLayout<DiagramLabelSpanRecord>.stride)
            let lineStart = Int32(storage.byteEnd)
            for span in line {
                let start = append(span.text, to: storage)
                storage.setRecord(DiagramLabelSpanRecord(start: start, end: start + Int32(span.text.utf8.count), style: span.style), at: firstSpan,
                                  index: spanIndex)
                spanIndex += 1
            }
            storage.setRecord(DiagramLabelLineRecord(start: lineStart, end: Int32(storage.byteEnd), firstSpan: lineFirstSpan, spanCount: Int32(line.count)),
                              at: first, index: index)
        }
        return DiagramLabel(storage: storage, record: DiagramLabelRecord(first: first, end: 0, lineCount: Int32(lines.count), flags: .hasSpans))
    }

    /// A label read for its markup from its decoded bytes: its lines' and, when one has an emphasis, its spans' ranges
    /// of `decoded`; never read without markup.
    static func label(decoded: UnsafeBufferPointer<UInt8>, lines: [DiagramLabelLineRecord], spans: [DiagramLabelSpanRecord]?) -> DiagramLabel {
        if lines.count == 1, spans == nil {
            return oneLine(UnsafeBufferPointer(rebasing: decoded[Int(lines[0].start)..<Int(lines[0].end)]), flags: [])
        }
        let recordBytes = DiagramTextStorage.recordByteCount(lines.count, of: DiagramLabelLineRecord.self)
            + (spans.map { spans in DiagramTextStorage.recordByteCount(spans.count, of: DiagramLabelSpanRecord.self) } ?? 0)
        let storage = DiagramTextThreadState.current.storage(forBytes: decoded.count, recordBytes: recordBytes)
        let base = storage.append(decoded)
        let first = storage.reserveRecords(count: lines.count, of: DiagramLabelLineRecord.self)
        let firstSpan = spans.map { spans in storage.reserveRecords(count: spans.count, of: DiagramLabelSpanRecord.self) } ?? 0
        let spanStride = Int32(MemoryLayout<DiagramLabelSpanRecord>.stride)
        for (index, line) in lines.enumerated() {
            storage.setRecord(DiagramLabelLineRecord(start: base + line.start, end: base + line.end, firstSpan: firstSpan + line.firstSpan * spanStride,
                                                     spanCount: spans == nil ? 0 : line.spanCount), at: first, index: index)
        }
        for (index, span) in (spans ?? []).enumerated() {
            storage.setRecord(DiagramLabelSpanRecord(start: base + span.start, end: base + span.end, style: span.style), at: firstSpan, index: index)
        }
        return DiagramLabel(storage: storage, record: DiagramLabelRecord(first: first, end: 0, lineCount: Int32(lines.count),
                                                                         flags: spans == nil ? [] : .hasSpans))
    }

    /// Appends `text`'s UTF-8 to `storage`, which has room for it; returns where it starts.
    static func append(_ text: String, to storage: DiagramTextStorage) -> Int32 {
        if let start = text.utf8.withContiguousStorageIfAvailable({ bytes in storage.append(bytes) }) { return start }
        return Array(text.utf8).withUnsafeBufferPointer { bytes in storage.append(bytes) }
    }
}

/// Texts compared by their bytes.
enum DiagramTextBytes {
    /// Whether two texts are equal as Strings are: the same bytes, or, beyond ASCII, the same characters however they
    /// are composed.
    static func areEqualAsText(_ left: UnsafeBufferPointer<UInt8>, _ right: UnsafeBufferPointer<UInt8>) -> Bool {
        if left.count == right.count, left.elementsEqual(right) { return true }
        guard !(isASCII(left) && isASCII(right)) else { return false }
        return String(decoding: left, as: UTF8.self) == String(decoding: right, as: UTF8.self)
    }

    static func isASCII(_ bytes: UnsafeBufferPointer<UInt8>) -> Bool {
        !bytes.contains { byte in byte >= 0x80 }
    }
}
