/**
 * File: RequirementLexerBytes.swift
 * ---------------------------------
 * Layer: Core
 * Description: The byte tests and searches the requirement lexer makes on a diagram's borrowed bytes: word characters,
 *              the ends of an unquoted text, line ends and line breaks, and JavaScript's trimming (keywords are told in
 *              RequirementKeywordWords).
 *
 * Authors: Bahey Shalash
 * Version: 0.3
 * Date: 26/11/2026
 */

#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif

extension RequirementLexer {
    /// A character of `\w`: an ASCII letter, digit or `_`, told by its bit in two masks of the 128 ASCII bytes.
    @inline(__always) static func isWordByte(_ byte: UInt8) -> Bool {
        isMarked(byte, low: 0x03FF_0000_0000_0000, high: 0x07FF_FFFE_87FF_FFFE)
    }

    /// Whether `byte` is ASCII and its bit is set: bit `byte` of `low` for the first 64 bytes, of `high` for the next.
    @inline(__always) private static func isMarked(_ byte: UInt8, low: UInt64, high: UInt64) -> Bool {
        byte < 64 ? (low >> UInt64(byte)) & 1 != 0 : byte < 128 && (high >> UInt64(byte - 64)) & 1 != 0
    }

    /// An ASCII byte that is no whitespace of JavaScript's: no whitespace character starts with it.
    @inline(__always) static func isPlainNonSpace(_ byte: UInt8) -> Bool {
        byte < 0x80 && byte != MermaidByte.space && (byte < MermaidByte.tab || byte > MermaidByte.carriageReturn)
    }

    /// The bytes that end an unquoted text: `:,\r\n{<>-=`, told by their bits.
    @inline(__always) static func endsUnquotedText(_ byte: UInt8) -> Bool {
        isMarked(byte, low: 0x7400_3000_0000_2400, high: 0x0800_0000_0000_0000)
    }

    /// The end of the run of JavaScript's whitespace that starts at `start`, as `JavaScriptWhitespace.endOfRun` finds it:
    /// a space, a tab, a line feed, a vertical tab, a form feed or a carriage return passed a byte at a time, the rest of
    /// the run, from a byte past ASCII, found by it.
    @inline(__always) static func endOfWhitespace(in bytes: UnsafeBufferPointer<UInt8>, from start: Int) -> Int {
        var end = start
        while end < bytes.count {
            let byte = bytes[end]
            if byte == MermaidByte.space || (byte >= MermaidByte.tab && byte <= MermaidByte.carriageReturn) {
                end += 1
            } else {
                return byte < 0xC2 ? end : JavaScriptWhitespace.endOfRun(in: bytes, from: end)
            }
        }
        return end
    }

    /// A line terminator, what JavaScript's `.` does not match: a line feed, a carriage return, U+2028 or U+2029.
    static func isLineEnd(_ bytes: UnsafeBufferPointer<UInt8>, at position: Int) -> Bool {
        let byte = bytes[position]
        if byte == MermaidByte.newline || byte == MermaidByte.carriageReturn { return true }
        return byte == 0xE2 && position + 2 < bytes.count && bytes[position + 1] == 0x80 && (bytes[position + 2] == 0xA8 || bytes[position + 2] == 0xA9)
    }

    /// The first line terminator at or after `start`, or the text's end.
    static func lineEnd(in bytes: UnsafeBufferPointer<UInt8>, from start: Int) -> Int {
        var position = start
        while position < bytes.count, !isLineEnd(bytes, at: position) { position += 1 }
        return position
    }

    /// The first line feed at or after `start`, or the text's end.
    static func lineBreak(in bytes: UnsafeBufferPointer<UInt8>, from start: Int) -> Int {
        firstIndex(of: MermaidByte.newline, in: bytes, from: start)
    }

    /// The first `byte` at or after `start`, or the text's end.
    static func firstIndex(of byte: UInt8, in bytes: UnsafeBufferPointer<UInt8>, from start: Int) -> Int {
        guard start < bytes.count, let base = bytes.baseAddress else { return bytes.count }
        guard let found = memchr(base + start, Int32(byte), bytes.count - start) else { return bytes.count }
        return base.distance(to: found.assumingMemoryBound(to: UInt8.self))
    }

    /// `range` without JavaScript's whitespace at either end, as `trim` leaves a string.
    static func trimmed(_ bytes: UnsafeBufferPointer<UInt8>, _ range: Range<Int>) -> Range<Int> {
        let start = JavaScriptWhitespace.endOfRun(in: bytes[range], from: range.lowerBound)
        var end = range.upperBound
        while case let length = JavaScriptWhitespace.lengthOfLast(in: bytes[start..<end]), length > 0 { end -= length }
        return start..<end
    }

    /// Whether `word`, in lowercase, is written at `position` in any case, compared byte by byte.
    static func hasLowercased(_ word: StaticString, in bytes: UnsafeBufferPointer<UInt8>, at position: Int) -> Bool {
        let count = word.utf8CodeUnitCount
        guard position >= 0, position + count <= bytes.count else { return false }
        let wordBytes = word.utf8Start
        for offset in 0..<count where MermaidByte.lowercased(bytes[position + offset]) != wordBytes[offset] { return false }
        return true
    }
}
