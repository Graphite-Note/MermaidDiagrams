/**
 * File: C4ByteSearch.swift
 * ------------------------
 * Layer: Core
 * Description: Where a word next starts in a C4 diagram's bytes, sixteen places at a time tested for its first two
 *              bytes, as the C4 lexer looks for the next `direction`.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 24/11/2026
 */

enum C4ByteSearch {
    /// Where `word` (two bytes or more) next starts from `start`, or nil: sixteen places at a time are tested for its first
    /// two bytes, and only those that hold them are compared whole.
    static func firstIndex(of word: [UInt8], in bytes: [UInt8], from start: Int) -> Int? {
        let count = bytes.count
        let wordCount = word.count
        guard start >= 0, wordCount >= 2, start + wordCount <= count else { return nil }
        return bytes.withUnsafeBufferPointer { text in
            guard let base = text.baseAddress else { return nil }
            let raw = UnsafeRawPointer(base)
            let first = SIMD16<UInt8>(repeating: word[0])
            let second = SIMD16<UInt8>(repeating: word[1])
            let last = count - wordCount
            var index = start
            // Sixteen places at a time while the sixteen bytes after the last of them are in the text.
            while index + 16 < count {
                let here = raw.loadUnaligned(fromByteOffset: index, as: SIMD16<UInt8>.self)
                let next = raw.loadUnaligned(fromByteOffset: index + 1, as: SIMD16<UInt8>.self)
                let matches = (here .== first) .& (next .== second)
                if matches != SIMDMask(repeating: false) {
                    for lane in 0..<16 where matches[lane] && index + lane <= last && holds(word, at: index + lane, in: text) { return index + lane }
                }
                index += 16
            }
            while index <= last {
                if holds(word, at: index, in: text) { return index }
                index += 1
            }
            return nil
        }
    }

    private static func holds(_ word: [UInt8], at index: Int, in text: UnsafeBufferPointer<UInt8>) -> Bool {
        var offset = 0
        while offset < word.count, text[index + offset] == word[offset] { offset += 1 }
        return offset == word.count
    }
}
