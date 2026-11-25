/**
 * File: EventModelBlockText.swift
 * -------------------------------
 * Layer: Core
 * Description: An event model's data block or note cut out of its braces or quotation marks: without carriage returns,
 *              the blank lines at its ends and its lines' shared indentation, each line without its trailing white space;
 *              a block of ASCII read on its bytes into the String it gives.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 25/11/2026
 */

extension EventModelDiagramBuilder {
    /// The text between the outer braces (or, without a brace, inside the quotation marks), without carriage returns,
    /// the blank lines at either end and the indentation its lines share, each line without its trailing whitespace.
    static func blockText(_ raw: String) -> String {
        if let ascii = raw.utf8.withContiguousStorageIfAvailable(asciiBlockText), let text = ascii { return text }
        return blockTextOfScalars(raw)
    }

    /// JavaScript's whitespace within ASCII: the tab to the carriage return and the space.
    private static func isBlank(_ byte: UInt8) -> Bool { (byte >= 0x09 && byte <= 0x0D) || byte == 0x20 }

    /// `blockText` of a text of ASCII alone, read on its bytes; nil for a text with a byte beyond ASCII. Its lines are
    /// ranges of the text between its line feeds, carriage returns skipped wherever they are, so that the String is
    /// written once, straight from them.
    private static func asciiBlockText(_ bytes: UnsafeBufferPointer<UInt8>) -> String? {
        var combined: UInt8 = 0
        for byte in bytes { combined |= byte }
        guard combined < 0x80 else { return nil }
        let opening = bytes.firstIndex(of: UInt8(ascii: "{"))
        let closing = bytes.lastIndex(of: UInt8(ascii: "}"))
        var inner = 0..<0
        if let opening, let closing, closing > opening {
            inner = (opening + 1)..<closing
        } else if opening == nil, bytes.count >= 2 {
            inner = 1..<(bytes.count - 1)
        }
        var lines = EventModelBlockLines(bytes, inner)
        var firstKept: (start: Int, end: Int)?
        var lastKeptEnd = inner.lowerBound
        var indent = Int.max
        while let line = lines.next() {
            guard let leading = lines.leadingBlankCount(of: line) else { continue }
            if firstKept == nil { firstKept = line }
            lastKeptEnd = line.end
            indent = min(indent, leading)
        }
        guard let firstKept else { return "" }
        let kept = firstKept.start..<lastKeptEnd
        return String(unsafeUninitializedCapacity: kept.count) { text in
            var written = 0
            var keptLines = EventModelBlockLines(bytes, kept)
            var isFirst = true
            while let line = keptLines.next() {
                if !isFirst {
                    text[written] = MermaidByte.newline
                    written += 1
                }
                isFirst = false
                written = keptLines.write(line, droppingFirst: indent, into: text, at: written)
            }
            return written
        }
    }

    /// `blockText` read scalar by scalar, for any text.
    static func blockTextOfScalars(_ raw: String) -> String {
        let scalars = Array(raw.unicodeScalars)
        let opening = scalars.firstIndex(of: "{")
        let closing = scalars.lastIndex(of: "}")
        var inner: ArraySlice<Unicode.Scalar> = []
        if let opening, let closing, closing > opening {
            inner = scalars[(opening + 1)..<closing]
        } else if opening == nil, scalars.count >= 2 {
            inner = scalars[1..<(scalars.count - 1)]
        }
        var lines = inner.filter { scalar in scalar != "\r" }.split(separator: "\n", omittingEmptySubsequences: false).map(Array.init)
        while let first = lines.first, first.allSatisfy(isWhitespace) { lines.removeFirst() }
        while let last = lines.last, last.allSatisfy(isWhitespace) { lines.removeLast() }
        let indent = lines.filter { line in !line.allSatisfy(isWhitespace) }.map { line in line.prefix(while: isWhitespace).count }.min() ?? 0
        return lines.map { line in
            var kept = line.dropFirst(min(indent, line.count))
            while let last = kept.last, isWhitespace(last) { kept = kept.dropLast() }
            return UnicodeScalarText.string(kept)
        }.joined(separator: "\n")
    }

    /// JavaScript's whitespace (`\s`).
    static func isWhitespace(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.value {
        case 0x09...0x0D, 0x20, 0xA0, 0x1680, 0x2000...0x200A, 0x2028, 0x2029, 0x202F, 0x205F, 0x3000, 0xFEFF: true
        default: false
        }
    }
}

/// The lines of a range of ASCII bytes, split at its line feeds, as `blockText` reads them once its carriage returns
/// are taken out: a carriage return counts as no character of the line it is on.
struct EventModelBlockLines {
    private let bytes: UnsafeBufferPointer<UInt8>
    private let end: Int
    private var position: Int
    private var isDone = false

    init(_ bytes: UnsafeBufferPointer<UInt8>, _ range: Range<Int>) {
        self.bytes = bytes
        end = range.upperBound
        position = range.lowerBound
    }

    /// The next line's bytes, from its start to its line feed or the range's end.
    mutating func next() -> (start: Int, end: Int)? {
        guard !isDone else { return nil }
        let start = position
        while position < end, bytes[position] != MermaidByte.newline { position += 1 }
        let line = (start, position)
        if position < end { position += 1 } else { isDone = true }
        return line
    }

    private static func isBlank(_ byte: UInt8) -> Bool { (byte >= 0x09 && byte <= 0x0D) || byte == 0x20 }

    /// How many characters the line starts with that are blank, or nil when every one is: a blank line.
    func leadingBlankCount(of line: (start: Int, end: Int)) -> Int? {
        var count = 0
        for index in line.start..<line.end where bytes[index] != MermaidByte.carriageReturn {
            guard Self.isBlank(bytes[index]) else { return count }
            count += 1
        }
        return nil
    }

    /// Writes the line's characters into `text` from `offset`, its first `dropped` characters and its trailing blanks left
    /// out, and returns where the writing ends.
    func write(_ line: (start: Int, end: Int), droppingFirst dropped: Int, into text: UnsafeMutableBufferPointer<UInt8>, at offset: Int) -> Int {
        var start = line.start
        var skipped = 0
        while start < line.end, skipped < dropped {
            if bytes[start] != MermaidByte.carriageReturn { skipped += 1 }
            start += 1
        }
        var last = line.end
        while last > start, Self.isBlank(bytes[last - 1]) { last -= 1 }
        var written = offset
        for index in start..<last where bytes[index] != MermaidByte.carriageReturn {
            text[written] = bytes[index]
            written += 1
        }
        return written
    }
}
