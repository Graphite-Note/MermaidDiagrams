/**
 * File: FoundationTextOnBytes.swift
 * ----------------------------------------
 * Layer: Core
 * Description: Foundation's trimming of white space (and line breaks) and its search for a character, done on the
 *              text's bytes where ASCII lets them be, and handed to Foundation only for text beyond it, with the same
 *              results.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 23/11/2026
 */

import Foundation

/// Foundation's `trimmingCharacters(in:)` with `.whitespaces` or `.whitespacesAndNewlines`, the ASCII ends trimmed on the
/// text's bytes: the sets' ASCII members are the space and the tab, and with line breaks the line feed, vertical tab,
/// form feed and carriage return. Text whose ends, once those are trimmed, lie beyond ASCII is handed to Foundation,
/// whose sets hold Unicode's spaces and line separators.
enum FoundationTextOnBytes {
    static func trimmed(_ text: String, includingLineBreaks: Bool) -> String {
        let bytes = text.utf8
        var start = bytes.startIndex
        var end = bytes.endIndex
        while start < end, isTrimmed(bytes[start], includingLineBreaks: includingLineBreaks) { start = bytes.index(after: start) }
        while start < end, isTrimmed(bytes[bytes.index(before: end)], includingLineBreaks: includingLineBreaks) { end = bytes.index(before: end) }
        if start < end, bytes[start] >= 0x80 || bytes[bytes.index(before: end)] >= 0x80 {
            return text.trimmingCharacters(in: includingLineBreaks ? .whitespacesAndNewlines : .whitespaces)
        }
        if start == bytes.startIndex, end == bytes.endIndex { return text }
        return String(Substring(bytes[start..<end]))
    }

    @inline(__always)
    private static func isTrimmed(_ byte: UInt8, includingLineBreaks: Bool) -> Bool {
        byte == MermaidByte.space || byte == MermaidByte.tab || (includingLineBreaks && byte >= MermaidByte.newline && byte <= MermaidByte.carriageReturn)
    }

    /// Foundation's `contains` of a one-character text, an ASCII character other than a line feed or a carriage return:
    /// it compares characters, so the byte must be a character of its own. Text without the byte holds no such
    /// character, and in text all in ASCII each byte is one; other text is handed to Foundation.
    static func contains(_ text: String, character byte: UInt8) -> Bool {
        precondition(byte < 0x80 && byte != MermaidByte.newline && byte != MermaidByte.carriageReturn, "a character Foundation reads otherwise")
        var holdsByte = false
        var isASCII = true
        for textByte in text.utf8 {
            if textByte == byte { holdsByte = true }
            if textByte >= 0x80 { isASCII = false }
        }
        guard holdsByte else { return false }
        return isASCII || text.contains(String(Unicode.Scalar(byte)))
    }
}
