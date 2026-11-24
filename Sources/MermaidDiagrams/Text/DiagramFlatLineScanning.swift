/**
 * File: DiagramFlatLineScanning.swift
 * -----------------------------------
 * Layer: Core
 * Description: The two passes the flat text measuring makes over a text's bytes: one that finds, sixteen bytes at a
 *              time, the next byte that may start a line break, and one that adds up a line's advances while it tells
 *              what kinds of byte the line holds, in four chains of additions where the face sums exactly.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 24/11/2026
 */

import CoreGraphics

/// What a line's bytes hold, as the flat measuring asks: a byte that is not printable ASCII (a control, DEL, a byte past
/// ASCII), a space, a byte that may start markup (`#`, `&`, `*`, `:`, `<`, backslash, `_`).
struct DiagramFlatByteKinds: OptionSet {
    let rawValue: UInt8

    static let unprintable = DiagramFlatByteKinds(rawValue: 1)
    static let space = DiagramFlatByteKinds(rawValue: 2)
    static let markup = DiagramFlatByteKinds(rawValue: 4)

    /// The kinds of each byte, made once, never written again and never freed.
    nonisolated(unsafe) static let byByte: UnsafePointer<UInt8> = {
        let table = UnsafeMutablePointer<UInt8>.allocate(capacity: 256)
        for byte in 0..<256 {
            var kinds: DiagramFlatByteKinds = DiagramFontAdvances.isPrintable(UInt8(byte)) ? [] : .unprintable
            if byte == Int(UInt8(ascii: " ")) { kinds.insert(.space) }
            if "#&*:<\\_".utf8.contains(UInt8(byte)) { kinds.insert(.markup) }
            table[byte] = kinds.rawValue
        }
        return UnsafePointer(table)
    }()
}

enum DiagramFlatLineScanning {
    /// The first byte at or after `index` before `end` that may start a break (a line feed, a backslash, `<`), or `end`:
    /// sixteen bytes compared at once with each of the three.
    @inline(__always)
    static func nextBreakCandidate(_ bytes: UnsafePointer<UInt8>, from index: Int, to end: Int) -> Int {
        var position = index
        while position + 16 <= end {
            let chunk = UnsafeRawPointer(bytes + position).loadUnaligned(as: SIMD16<UInt8>.self)
            var found = chunk .== SIMD16<UInt8>(repeating: 0x0A)
            found .|= chunk .== SIMD16<UInt8>(repeating: UInt8(ascii: "\\"))
            found .|= chunk .== SIMD16<UInt8>(repeating: UInt8(ascii: "<"))
            if any(found) { break }
            position += 16
        }
        while position < end {
            let byte = bytes[position]
            if byte == 0x0A || byte == UInt8(ascii: "\\") || byte == UInt8(ascii: "<") { return position }
            position += 1
        }
        return end
    }

    /// The width of `bytes[start..<end]` and the kinds of byte it holds. In a face that sums exactly every grouping of
    /// the additions gives the same sum, so four chains run side by side; in any other the advances are added from the
    /// first byte on, as a block adds them, and so they are past `DiagramFlatTextWrapping.longestWrappedByteCount` bytes.
    @inline(__always)
    static func measured(_ bytes: UnsafePointer<UInt8>, from start: Int, to end: Int, advances: DiagramFontAdvances)
        -> (width: CGFloat, kinds: DiagramFlatByteKinds) {
        let table = advances.byByte
        let kindsByByte = DiagramFlatByteKinds.byByte
        var kinds: UInt8 = 0
        var position = start
        guard advances.isExactlySummable, end - start < DiagramFlatTextWrapping.longestWrappedByteCount else {
            var width: CGFloat = 0
            while position < end {
                let byte = Int(bytes[position])
                kinds |= kindsByByte[byte]
                width += table[byte]
                position += 1
            }
            return (width, DiagramFlatByteKinds(rawValue: kinds))
        }
        var first: CGFloat = 0
        var second: CGFloat = 0
        var third: CGFloat = 0
        var fourth: CGFloat = 0
        while position + 4 <= end {
            let byte0 = Int(bytes[position])
            let byte1 = Int(bytes[position + 1])
            let byte2 = Int(bytes[position + 2])
            let byte3 = Int(bytes[position + 3])
            kinds |= kindsByByte[byte0] | kindsByByte[byte1] | kindsByByte[byte2] | kindsByByte[byte3]
            first += table[byte0]
            second += table[byte1]
            third += table[byte2]
            fourth += table[byte3]
            position += 4
        }
        while position < end {
            let byte = Int(bytes[position])
            kinds |= kindsByByte[byte]
            first += table[byte]
            position += 1
        }
        return ((first + second) + (third + fourth), DiagramFlatByteKinds(rawValue: kinds))
    }
}
