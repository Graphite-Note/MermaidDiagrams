/**
 * File: RequirementLexerBytes.swift
 * ---------------------------------
 * Layer: Core
 * Description: The byte tests and searches the requirement lexer makes on a diagram's borrowed bytes: word characters,
 *              the ends of an unquoted text, line ends and line breaks, JavaScript's trimming, and keywords compared
 *              without regard to case.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 25/11/2026
 */

#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif

extension RequirementLexer {
    /// A character of `\w`.
    @inline(__always) static func isWordByte(_ byte: UInt8) -> Bool {
        MermaidByte.isLetter(byte) || MermaidByte.isDigit(byte) || byte == MermaidByte.underscore
    }

    /// An ASCII byte that is no whitespace of JavaScript's: no whitespace character starts with it.
    @inline(__always) static func isPlainNonSpace(_ byte: UInt8) -> Bool {
        byte < 0x80 && byte != MermaidByte.space && (byte < MermaidByte.tab || byte > MermaidByte.carriageReturn)
    }

    /// The bytes that end an unquoted text: `:,\r\n{<>-=`.
    @inline(__always) static func endsUnquotedText(_ byte: UInt8) -> Bool {
        switch byte {
        case MermaidByte.colon, MermaidByte.comma, MermaidByte.carriageReturn, MermaidByte.newline, MermaidByte.openingBrace, MermaidByte.lessThan,
             MermaidByte.greaterThan, MermaidByte.hyphen, MermaidByte.equals: true
        default: false
        }
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

extension RequirementKeywords {
    /// The keyword the word from `start` to `end` is in any case, or nil: compared byte by byte, made lowercase, with the
    /// keywords of its length that start with its first letter, without making it a string to look it up.
    static func keyword(from start: Int, to end: Int, in bytes: UnsafeBufferPointer<UInt8>) -> RequirementTokenKind? {
        let first = MermaidByte.lowercased(bytes[start])
        guard first < 0x80 else { return nil }
        let length = end - start
        candidates: for (word, kind) in keywordsByFirstByte[Int(first)] where word.count == length {
            for offset in 1..<length where MermaidByte.lowercased(bytes[start + offset]) != word[offset] { continue candidates }
            return kind
        }
        return nil
    }

    /// `byLowercaseWord`'s words as bytes, by their first byte.
    private static let keywordsByFirstByte: [[(word: [UInt8], kind: RequirementTokenKind)]] = {
        var byFirstByte = [[(word: [UInt8], kind: RequirementTokenKind)]](repeating: [], count: 128)
        for (word, kind) in byLowercaseWord {
            let bytes = Array(word.utf8)
            byFirstByte[Int(bytes[0])].append((bytes, kind))
        }
        return byFirstByte
    }()
}
