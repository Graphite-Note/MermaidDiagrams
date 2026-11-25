/**
 * File: TreeViewByteLines.swift
 * -----------------------------
 * Layer: Core
 * Description: The lines after a tree view's keyword read straight from the text's bytes into the text its tokens are
 *              read from, when the text holds no carriage return: the comment lines and the blank lines before them
 *              left out as the box-drawing reader leaves them, without a String per line.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 24/11/2026
 */

/// Reads the lines after the keyword as `TreeViewBoxDrawingReader.lines(after:in:)` and `TreeViewTokenSource(lines:)`
/// read them, on the bytes. A line of ASCII alone is told a comment line, or a line of blanks, on its bytes, where its
/// characters are its bytes; any other line is told so from its String, as the box-drawing reader tells it.
enum TreeViewByteLines {
    /// The token source of the lines of `bytes` from `start` on, the first line (the keyword's) left out and the others
    /// numbered from `keywordLine`, box drawing turned into indentation (`TreeViewByteBoxDrawing`); nil when the text
    /// needs the box-drawing reader, which splits at carriage returns as Swift's characters do and reads box drawing
    /// beside characters past ASCII.
    static func tokenSource(after keywordLine: Int, in bytes: [UInt8], from start: Int) throws(MermaidDiagramReadError) -> TreeViewTokenSource? {
        guard start <= bytes.count else { return nil }
        let outcome = bytes.withUnsafeBufferPointer { buffer -> Result<TreeViewTokenSource?, MermaidDiagramReadError> in
            do throws(MermaidDiagramReadError) {
                return .success(try tokenSource(after: keywordLine, in: UnsafeBufferPointer(rebasing: buffer[start...])))
            } catch {
                return .failure(error)
            }
        }
        return try outcome.get()
    }

    private static func tokenSource(after keywordLine: Int, in text: UnsafeBufferPointer<UInt8>) throws(MermaidDiagramReadError) -> TreeViewTokenSource? {
        guard !text.contains(MermaidByte.carriageReturn) else { return nil }
        var lines: [Range<Int>] = []
        lines.reserveCapacity(text.reduce(1) { count, byte in byte == MermaidByte.newline ? count + 1 : count })
        var lineStart = 0
        for index in text.indices where text[index] == MermaidByte.newline {
            lines.append(lineStart..<index)
            lineStart = index + 1
        }
        lines.append(lineStart..<text.count)
        let kept = keptLines(lines, of: text)
        if TreeViewBoxDrawingReader.containsBoxCharacter(text) {
            return try TreeViewByteBoxDrawing.converted(kept, lines: lines, in: text, keywordLine: keywordLine)
        }
        var output = TreeViewSourceBuilder(byteCapacity: text.count, lineCapacity: kept.count)
        for index in kept.dropFirst() { output.append(text[lines[index]], writtenLine: keywordLine + index) }
        return output.source
    }

    /// The indices of the lines the box-drawing reader keeps: a comment line goes, with the lines of blanks just before it
    /// but the first line (`TreeViewBoxDrawingReader.withoutCommentLines`).
    private static func keptLines(_ lines: [Range<Int>], of text: UnsafeBufferPointer<UInt8>) -> [Int] {
        var kept: [Int] = []
        kept.reserveCapacity(lines.count)
        for (index, line) in lines.enumerated() {
            guard isCommentLine(UnsafeBufferPointer(rebasing: text[line])), !kept.isEmpty else {
                kept.append(index)
                continue
            }
            while let last = kept.last, kept.count > 1, isBlank(UnsafeBufferPointer(rebasing: text[lines[last]])) { kept.removeLast() }
        }
        return kept
    }

    /// Whether the line is one Mermaid's preprocessing removes: `%%` and a character more after white space, not a
    /// directive's `%%{`, unless the line starts, after its spaces and tabs, with a printable ASCII character other than
    /// `%` or a box-drawing one.
    private static func isCommentLine(_ line: UnsafeBufferPointer<UInt8>) -> Bool {
        var first = 0
        while first < line.count, line[first] == MermaidByte.space || line[first] == MermaidByte.tab { first += 1 }
        if first < line.count, line[first] >= 0x21, line[first] <= 0x7E, line[first] != percent { return false }
        // Without a percent sign the line holds no `%%`.
        guard line.contains(percent) else { return false }
        guard isASCII(line) else { return TreeViewBoxDrawingReader.isCommentLine(String(decoding: line, as: UTF8.self)) }
        var contentStart = 0
        while contentStart < line.count, isASCIIWhitespace(line[contentStart]) { contentStart += 1 }
        let contentCount = line.count - contentStart
        guard contentCount > 2, line[contentStart] == percent, line[contentStart + 1] == percent else { return false }
        return line[contentStart + 2] != openingBrace
    }

    /// Whether the line is empty or all white space, as Swift's characters tell it.
    private static func isBlank(_ line: UnsafeBufferPointer<UInt8>) -> Bool {
        guard isASCII(line) else { return String(decoding: line, as: UTF8.self).allSatisfy(\.isWhitespace) }
        return line.allSatisfy(isASCIIWhitespace)
    }

    private static func isASCII(_ line: UnsafeBufferPointer<UInt8>) -> Bool {
        !line.contains { byte in byte >= 0x80 }
    }

    /// White space among ASCII's characters: a tab, a line feed, a vertical tab, a form feed, a carriage return, a space.
    private static func isASCIIWhitespace(_ byte: UInt8) -> Bool {
        byte == MermaidByte.space || (byte >= 0x09 && byte <= 0x0D)
    }

    private static let percent = UInt8(ascii: "%")
    private static let openingBrace = UInt8(ascii: "{")
}
