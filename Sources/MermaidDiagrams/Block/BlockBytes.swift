/**
 * File: BlockBytes.swift
 * ----------------------
 * Layer: Core
 * Description: What the block reader does to runs of UTF-8 bytes in place of a String's methods: trimming white space
 *              and line breaks as Foundation's `trimmingCharacters(in: .whitespacesAndNewlines)` trims them, scalar by
 *              scalar, and comparing runs.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 24/11/2026
 */

import Foundation

enum BlockBytes {
    /// The bytes of `buffer` without the white space and line breaks (`CharacterSet.whitespacesAndNewlines`) at either
    /// end, scalar by scalar, as `trimmingCharacters(in: .whitespacesAndNewlines)` leaves a String.
    static func trimmed(_ buffer: UnsafeBufferPointer<UInt8>) -> UnsafeBufferPointer<UInt8> {
        let range = trimmedRange(buffer)
        return UnsafeBufferPointer(rebasing: buffer[range])
    }

    /// The offsets, in `buffer`, of what `trimmed` leaves.
    static func trimmedRange(_ buffer: UnsafeBufferPointer<UInt8>) -> Range<Int> {
        var start = 0
        var end = buffer.count
        while start < end {
            let (scalar, length) = scalar(startingAt: start, in: buffer)
            guard isWhitespaceOrNewline(scalar) else { break }
            start += length
        }
        while end > start {
            var scalarStart = end - 1
            while scalarStart > start, buffer[scalarStart] & 0xC0 == 0x80 { scalarStart -= 1 }
            let (scalar, _) = scalar(startingAt: scalarStart, in: buffer)
            guard isWhitespaceOrNewline(scalar) else { break }
            end = scalarStart
        }
        return start..<end
    }

    /// `text` trimmed as `trimmed` trims, a run of the same bytes.
    static func trimmed(_ text: BlockText, in bytes: [UInt8]) -> BlockText {
        bytes.withUnsafeBufferPointer { buffer in
            let range = trimmedRange(UnsafeBufferPointer(rebasing: buffer[text.lowerBound..<text.upperBound]))
            return BlockText(start: text.lowerBound + range.lowerBound, count: range.count)
        }
    }

    /// Whether two runs of `bytes` hold the same bytes.
    static func same(_ first: BlockText, _ second: BlockText, in bytes: [UInt8]) -> Bool {
        guard first.count == second.count else { return false }
        guard first.start != second.start else { return true }
        return bytes.withUnsafeBufferPointer { buffer in
            guard let base = buffer.baseAddress else { return true }
            return memcmp(base + first.lowerBound, base + second.lowerBound, Int(first.count)) == 0
        }
    }

    /// The scalar whose bytes start at `index` and how many bytes it takes; a byte that starts no well-formed scalar
    /// reads as U+FFFD, one byte long, which is no white space.
    private static func scalar(startingAt index: Int, in buffer: UnsafeBufferPointer<UInt8>) -> (scalar: UInt32, length: Int) {
        let lead = buffer[index]
        if lead < 0x80 { return (UInt32(lead), 1) }
        let length = lead >= 0xF0 ? 4 : lead >= 0xE0 ? 3 : lead >= 0xC0 ? 2 : 1
        guard length > 1, index + length <= buffer.count else { return (0xFFFD, 1) }
        var value = UInt32(lead) & (0xFF >> (length + 1))
        for offset in 1..<length {
            let continuation = buffer[index + offset]
            guard continuation & 0xC0 == 0x80 else { return (0xFFFD, 1) }
            value = value << 6 | UInt32(continuation & 0x3F)
        }
        return (value, length)
    }

    private static func isWhitespaceOrNewline(_ scalar: UInt32) -> Bool {
        switch scalar {
        case 0x09...0x0D, 0x20: return true
        case 0..<0x80: return false
        default: return Unicode.Scalar(scalar).map(whitespacesAndNewlines.contains) ?? false
        }
    }

    private static let whitespacesAndNewlines = CharacterSet.whitespacesAndNewlines
}
