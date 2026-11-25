/**
 * File: DiagramSVGClassNames.swift
 * --------------------------------
 * Layer: Core
 * Description: The class Pele's SVG gives each part of a scene, `pele-` and the part's raw value, kept as bytes made once
 *              in one block of 32 bytes a part, so that the writer copies a part's class in two 16-byte moves.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 24/11/2026
 */

/// `pele-<raw value>` of every part (`DiagramScenePart`), the longest 26 bytes, each in an entry of
/// `entryByteCount` bytes at the part's ordinal, its length in the entry's last byte. Made the first time a class is
/// written and kept, never changed, so that any thread reads it.
struct DiagramSVGClassNames: @unchecked Sendable {
    private let entries: UnsafePointer<UInt8>

    /// The bytes of one entry: room for the longest class, the bytes copied past a shorter one and its length.
    static let entryByteCount = 32

    /// The process's classes.
    static let shared = DiagramSVGClassNames()

    private init() {
        let parts = DiagramScenePart.allCases
        let entries = UnsafeMutablePointer<UInt8>.allocate(capacity: parts.count * Self.entryByteCount)
        entries.initialize(repeating: 0, count: parts.count * Self.entryByteCount)
        for part in parts {
            let name = Array("pele-\(part.rawValue)".utf8)
            precondition(name.count < Self.entryByteCount, "a part's class fits its entry")
            let entry = entries + part.ordinal * Self.entryByteCount
            entry.update(from: name, count: name.count)
            entry[Self.entryByteCount - 1] = UInt8(name.count)
        }
        self.entries = UnsafePointer(entries)
    }

    /// Copies `part`'s class to `destination`, which has room for `entryByteCount` bytes, and returns its length; the
    /// bytes past the class are left for what follows to overwrite.
    @inline(__always)
    func write(_ part: DiagramScenePart, to destination: UnsafeMutablePointer<UInt8>) -> Int {
        let entry = UnsafeRawPointer(entries + part.ordinal * Self.entryByteCount)
        let target = UnsafeMutableRawPointer(destination)
        target.storeBytes(of: entry.loadUnaligned(as: SIMD16<UInt8>.self), as: SIMD16<UInt8>.self)
        target.storeBytes(of: entry.loadUnaligned(fromByteOffset: 16, as: SIMD16<UInt8>.self), toByteOffset: 16, as: SIMD16<UInt8>.self)
        return Int(entry.load(fromByteOffset: Self.entryByteCount - 1, as: UInt8.self))
    }

    /// `part`'s class as a String, for tests.
    func name(of part: DiagramScenePart) -> String {
        let entry = entries + part.ordinal * Self.entryByteCount
        return String(decoding: UnsafeBufferPointer(start: entry, count: Int(entry[Self.entryByteCount - 1])), as: UTF8.self)
    }
}

extension DiagramScenePart {
    /// The part's place among `allCases`, its declaration order: the tag the enum is stored as, one byte for its fewer
    /// than 256 cases, read without a switch (`DiagramSVGClassNamesTests` checks it against `allCases`).
    @inline(__always)
    var ordinal: Int {
        Int(unsafeBitCast(self, to: UInt8.self))
    }
}
