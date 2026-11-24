/**
 * File: BlockNameTable.swift
 * --------------------------
 * Layer: Core
 * Description: The names a block diagram's reading meets, interned by their bytes: an FNV-1a hash in an open-addressing
 *              table, each name compared byte for byte as Pele's JavaScript compares strings, numbered in the order met.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 24/11/2026
 */

#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif

/// Names numbered in the order they are first met, each a run of the bytes the table is asked about, which may grow
/// between calls but never changes what a run already holds.
struct BlockNameTable: Sendable {
    /// A power of two long once a name is interned, empty before: a name's number + 1, or 0 for an empty slot.
    private var slots: [Int32] = []
    /// Each name and its hash, by its number.
    private var entries: [Entry] = []
    /// How many names the slots are first made for.
    private let expectedCount: Int

    private struct Entry {
        let text: BlockText
        let hash: UInt32
    }

    /// A table whose first slots and entries have room for `expectedCount` names.
    init(expectedCount: Int = 8) {
        self.expectedCount = max(expectedCount, 4)
    }

    var count: Int { entries.count }

    /// The number of the name `text` spells in `bytes`, numbered now when it is new.
    mutating func intern(_ text: BlockText, in bytes: [UInt8]) -> Int {
        if slots.isEmpty {
            var slotCount = 16
            while slotCount < 2 * expectedCount { slotCount *= 2 }
            slots = Array(repeating: 0, count: slotCount)
            entries.reserveCapacity(expectedCount)
        }
        return bytes.withUnsafeBufferPointer { buffer in
            let start = buffer.baseAddress.map { base in base + text.lowerBound }
            let hash = Self.hash(start, count: Int(text.count))
            let mask = slots.count &- 1
            var slot = Int(hash) & mask
            while case let entry = slots[slot], entry != 0 {
                let number = Int(entry &- 1)
                if entries[number].hash == hash, entries[number].text.count == text.count, Self.same(entries[number].text, start, in: buffer) { return number }
                slot = (slot &+ 1) & mask
            }
            let number = entries.count
            entries.append(Entry(text: text, hash: hash))
            slots[slot] = Int32(number + 1)
            if entries.count * 2 > slots.count { growSlots() }
            return number
        }
    }

    /// The number of the name `text` spells in `bytes`, nil when it was never met.
    func number(of text: BlockText, in bytes: [UInt8]) -> Int? {
        bytes.withUnsafeBufferPointer { buffer in
            number(of: buffer.baseAddress.map { base in base + text.lowerBound }, count: Int(text.count), in: buffer)
        }
    }

    /// The number of the name `name` spells, nil when it was never met.
    func number(ofBytes name: [UInt8], in bytes: [UInt8]) -> Int? {
        name.withUnsafeBufferPointer { nameBuffer in
            bytes.withUnsafeBufferPointer { buffer in number(of: nameBuffer.baseAddress, count: nameBuffer.count, in: buffer) }
        }
    }

    private func number(of start: UnsafePointer<UInt8>?, count: Int, in buffer: UnsafeBufferPointer<UInt8>) -> Int? {
        guard !slots.isEmpty else { return nil }
        let hash = Self.hash(start, count: count)
        let mask = slots.count &- 1
        var slot = Int(hash) & mask
        while case let entry = slots[slot], entry != 0 {
            let number = Int(entry &- 1)
            if entries[number].hash == hash, Int(entries[number].text.count) == count, Self.same(entries[number].text, start, in: buffer) { return number }
            slot = (slot &+ 1) & mask
        }
        return nil
    }

    @inline(__always) private static func hash(_ start: UnsafePointer<UInt8>?, count: Int) -> UInt32 {
        var hash: UInt32 = 0x811C_9DC5
        guard let start else { return hash }
        for offset in 0..<count { hash = (hash ^ UInt32(start[offset])) &* 0x0100_0193 }
        return hash
    }

    /// Whether the name at `name` holds the `name.count` bytes at `other`.
    @inline(__always) private static func same(_ name: BlockText, _ other: UnsafePointer<UInt8>?, in buffer: UnsafeBufferPointer<UInt8>) -> Bool {
        guard name.count > 0 else { return true }
        guard let base = buffer.baseAddress, let other else { return false }
        return memcmp(base + name.lowerBound, other, Int(name.count)) == 0
    }

    private mutating func growSlots() {
        let count = slots.count * 2
        slots = Array(repeating: 0, count: count)
        for number in entries.indices {
            var slot = Int(entries[number].hash) & (count - 1)
            while slots[slot] != 0 { slot = (slot + 1) & (count - 1) }
            slots[slot] = Int32(number + 1)
        }
    }
}
