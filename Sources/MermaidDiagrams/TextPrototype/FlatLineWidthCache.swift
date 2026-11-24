/**
 * File: FlatLineWidthCache.swift
 * ------------------------------
 * Layer: Prototype
 * Description: The width of text beyond printable ASCII, as a Core Text line lays it out, kept by its UTF-8 bytes and
 *              its font, so that text met again is found without making a String.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 24/11/2026
 */

import CoreGraphics
import Foundation

/// Line widths by font and bytes, in an open-addressed table; a text not found is measured by the present measurer
/// (a String made once), so that the width is the one it gives.
final class FlatLineWidthCache: @unchecked Sendable {
    static let shared = FlatLineWidthCache()

    private struct Entry {
        var hash: UInt64 = 0
        var face: Int32 = -1
        var byteStart: Int32 = 0
        var byteCount: Int32 = 0
        var width: CGFloat = 0
    }

    private static let capacity = 8_192
    private static let longestKeptByteCount = 256
    private var entries = UnsafeMutablePointer<Entry>.allocate(capacity: capacity)
    private var keyBytes: [UInt8] = []
    private var count = 0
    private var lock = os_unfair_lock()

    private init() {
        entries.initialize(repeating: Entry(), count: Self.capacity)
        keyBytes.reserveCapacity(64 * 1_024)
    }

    /// The width of `bytes[start..<end]` in face `face` (an identifier unique to the font), measured by `measurer` when
    /// it is not known.
    func width(_ bytes: UnsafeBufferPointer<UInt8>, _ start: Int, _ end: Int, face: Int32, measurer: UnsafePointer<CoreTextDiagramTextMeasurer>) -> CGFloat {
        let byteCount = end - start
        guard byteCount <= Self.longestKeptByteCount else { return measurer.pointee.width(of: String(decoding: UnsafeBufferPointer(rebasing: bytes[start..<end]), as: UTF8.self)) }
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325 ^ UInt64(UInt32(bitPattern: face))
        for index in start..<end { hash = (hash ^ UInt64(bytes[index])) &* 0x0000_0100_0000_01B3 }
        let mask = Self.capacity - 1
        os_unfair_lock_lock(&lock)
        var slot = Int(truncatingIfNeeded: hash) & mask
        while entries[slot].face >= 0 {
            let entry = entries[slot]
            if entry.hash == hash, entry.face == face, Int(entry.byteCount) == byteCount,
               keyBytes.withUnsafeBufferPointer({ keys in memcmp(keys.baseAddress! + Int(entry.byteStart), bytes.baseAddress! + start, byteCount) == 0 }) {
                os_unfair_lock_unlock(&lock)
                return entry.width
            }
            slot = (slot + 1) & mask
        }
        os_unfair_lock_unlock(&lock)
        let width = measurer.pointee.width(of: String(decoding: UnsafeBufferPointer(rebasing: bytes[start..<end]), as: UTF8.self))
        os_unfair_lock_lock(&lock)
        if count * 10 >= Self.capacity * 7 {
            entries.update(repeating: Entry(), count: Self.capacity)
            keyBytes.removeAll(keepingCapacity: true)
            count = 0
            slot = Int(truncatingIfNeeded: hash) & mask
        }
        while entries[slot].face >= 0 { slot = (slot + 1) & mask }
        entries[slot] = Entry(hash: hash, face: face, byteStart: Int32(keyBytes.count), byteCount: Int32(byteCount), width: width)
        keyBytes.append(contentsOf: UnsafeBufferPointer(rebasing: bytes[start..<end]))
        count += 1
        os_unfair_lock_unlock(&lock)
        return width
    }
}
