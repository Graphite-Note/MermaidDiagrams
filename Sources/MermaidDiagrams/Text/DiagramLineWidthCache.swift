/**
 * File: DiagramLineWidthCache.swift
 * ---------------------------------
 * Layer: Core
 * Description: The width of a line beyond printable ASCII as a Core Text line lays it out, kept by its font and its
 *              UTF-8 bytes in one open-addressed table, so that text met again is found without making a String.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 24/11/2026
 */

import CoreGraphics
import CoreText
import Foundation

/// Line widths by registered face and bytes. Text beyond printable ASCII, whose fallback fonts Core Text finds for each
/// line it makes (a tree view's box drawing, a C4 diagram's guillemets), costs microseconds a line to lay out; a text
/// found here costs a hash of its bytes. A text not found is made a String once and laid out as before, so its width is
/// the one Core Text gives that String. Keys of at most `longestKeptByteCount` bytes, in a table of `capacity` slots
/// emptied when it is 70% full, so that it holds at most about a megabyte and a half.
final class DiagramLineWidthCache: @unchecked Sendable {
    static let shared = DiagramLineWidthCache()

    private struct Slot {
        var hash: UInt64 = 0
        var face: Int32 = -1
        var keyStart: Int32 = 0
        var keyCount: Int32 = 0
        var width: CGFloat = 0
    }

    private static let capacity = 8_192
    private static let longestKeptByteCount = 256
    /// The table is emptied once it holds this many keys: 70% of its slots.
    private static let largestKeptCount = capacity * 7 / 10

    private let lock: UnsafeMutablePointer<os_unfair_lock>
    private let slots: UnsafeMutablePointer<Slot>
    private var keyBytes: [UInt8] = []
    private var count = 0

    private init() {
        lock = .allocate(capacity: 1)
        lock.initialize(to: os_unfair_lock())
        slots = .allocate(capacity: Self.capacity)
        slots.initialize(repeating: Slot(), count: Self.capacity)
    }

    /// The width of `bytes` in the registered face `face`, laid out the first time.
    func width(of bytes: UnsafeBufferPointer<UInt8>, face: DiagramFontFaceIndex) -> CGFloat {
        guard bytes.count <= Self.longestKeptByteCount, let base = bytes.baseAddress else {
            return Self.layOutWidth(of: bytes, font: DiagramFontFaceRegistry.shared.coreTextFont(face))
        }
        let hash = Self.hash(of: bytes, face: face.rawValue)
        let mask = Self.capacity - 1
        os_unfair_lock_lock(lock)
        var slot = Int(truncatingIfNeeded: hash) & mask
        while slots[slot].face >= 0 {
            let candidate = slots[slot]
            if candidate.hash == hash, candidate.face == face.rawValue, Int(candidate.keyCount) == bytes.count,
               keyBytes.withUnsafeBufferPointer({ keys in memcmp(keys.baseAddress! + Int(candidate.keyStart), base, bytes.count) == 0 }) {
                os_unfair_lock_unlock(lock)
                return candidate.width
            }
            slot = (slot + 1) & mask
        }
        os_unfair_lock_unlock(lock)
        let width = Self.layOutWidth(of: bytes, font: DiagramFontFaceRegistry.shared.coreTextFont(face))
        os_unfair_lock_lock(lock)
        defer { os_unfair_lock_unlock(lock) }
        if count >= Self.largestKeptCount {
            slots.update(repeating: Slot(), count: Self.capacity)
            keyBytes.removeAll(keepingCapacity: true)
            count = 0
        }
        // Another thread may have kept the same text meanwhile; a second slot for it is harmless, as it holds the same width.
        slot = Int(truncatingIfNeeded: hash) & mask
        while slots[slot].face >= 0 { slot = (slot + 1) & mask }
        slots[slot] = Slot(hash: hash, face: face.rawValue, keyStart: Int32(keyBytes.count), keyCount: Int32(bytes.count), width: width)
        keyBytes.append(contentsOf: bytes)
        count += 1
        return width
    }

    /// Whether a text of `bytes` in `face` is kept, for the tests of the cache's emptying.
    func contains(_ bytes: UnsafeBufferPointer<UInt8>, face: DiagramFontFaceIndex) -> Bool {
        guard let base = bytes.baseAddress else { return false }
        let hash = Self.hash(of: bytes, face: face.rawValue)
        os_unfair_lock_lock(lock)
        defer { os_unfair_lock_unlock(lock) }
        var slot = Int(truncatingIfNeeded: hash) & (Self.capacity - 1)
        while slots[slot].face >= 0 {
            let candidate = slots[slot]
            if candidate.hash == hash, candidate.face == face.rawValue, Int(candidate.keyCount) == bytes.count,
               keyBytes.withUnsafeBufferPointer({ keys in memcmp(keys.baseAddress! + Int(candidate.keyStart), base, bytes.count) == 0 }) {
                return true
            }
            slot = (slot + 1) & (Self.capacity - 1)
        }
        return false
    }

    /// FNV-1a over the face and the bytes.
    private static func hash(of bytes: UnsafeBufferPointer<UInt8>, face: Int32) -> UInt64 {
        var hash: UInt64 = 0xCBF2_9CE4_8422_2325 ^ UInt64(UInt32(bitPattern: face))
        for byte in bytes { hash = (hash ^ UInt64(byte)) &* 0x0000_0100_0000_01B3 }
        return hash
    }

    /// The width of a Core Text line of the text `bytes` hold in `font`, as text has always been laid out here.
    static func layOutWidth(of bytes: UnsafeBufferPointer<UInt8>, font: CTFont) -> CGFloat {
        let text = String(decoding: bytes, as: UTF8.self)
        let attributes = [kCTFontAttributeName as NSAttributedString.Key: font]
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: attributes))
        return CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil))
    }
}
