/**
 * File: DiagramTextLiteralLines.swift
 * -----------------------------------
 * Layer: Core
 * Description: The lines of literal text, which keeps every character but the spaces a line breaks at: each written line
 *              broken where it passes a room, at its last space before that when it has one, else between characters.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 24/11/2026
 */

import CoreGraphics

/// The lines of a literal label (a file's name), as Pele's literal labels break.
enum DiagramLiteralLines {
    /// One written line's lines. Each probe measures a String made from a slice of `written` between two of its
    /// characters' boundaries, the same text as the characters it holds, so the widths are those of the characters joined.
    static func lines(of written: Substring, measurer: some DiagramTextMeasuring, room: CGFloat) -> [String] {
        guard !written.isEmpty else { return [""] }
        // Where each character starts, and the end, then whether each is white space: read once, so that no probe walks
        // the characters again. A character is white space by its first scalar, as `Character.isWhitespace` decides, and
        // one that starts with an ASCII byte is decided from that byte.
        let bytes = written.utf8
        var boundaries: [String.Index] = []
        var isWhitespace: [Bool] = []
        boundaries.reserveCapacity(bytes.count + 1)
        isWhitespace.reserveCapacity(bytes.count)
        for index in written.indices {
            boundaries.append(index)
            let firstByte = bytes[index]
            isWhitespace.append(firstByte < 0x80 ? isASCIIWhitespace(firstByte) : written[index].isWhitespace)
        }
        boundaries.append(written.endIndex)
        let characterCount = isWhitespace.count
        func text(_ start: Int, _ end: Int) -> String { String(written[boundaries[start]..<boundaries[end]]) }
        var lines: [String] = []
        var start = 0
        while start < characterCount {
            // The most characters that fit, found by doubling and then halving, so that a long line is measured a few
            // dozen times rather than once per character.
            let remaining = characterCount - start
            func fits(_ length: Int) -> Bool { measurer.width(of: text(start, start + length)) <= room }
            var upper = 1
            while upper < remaining, fits(upper) { upper = min(remaining, upper * 2) }
            var taken = 1
            while taken < upper {
                let middle = (taken + upper + 1) / 2
                if fits(middle) { taken = middle } else { upper = middle - 1 }
            }
            let wraps = start + taken < characterCount
            if wraps, !isWhitespace[start + taken], let lastSpace = (1..<taken).last(where: { offset in isWhitespace[start + offset] }) {
                taken = lastSpace + 1
            }
            var trimmedEnd = start + taken
            while trimmedEnd > start, isWhitespace[trimmedEnd - 1] { trimmedEnd -= 1 }
            lines.append(wraps && trimmedEnd > start ? text(start, trimmedEnd) : text(start, start + taken))
            start += taken
            while wraps, start < characterCount, isWhitespace[start] { start += 1 }
        }
        return lines
    }

    /// Whether an ASCII byte is Unicode white space: a tab, a line feed, a line tabulation, a form feed, a carriage return
    /// or a space.
    private static func isASCIIWhitespace(_ byte: UInt8) -> Bool {
        byte == 0x20 || (0x09...0x0D).contains(byte)
    }
}
