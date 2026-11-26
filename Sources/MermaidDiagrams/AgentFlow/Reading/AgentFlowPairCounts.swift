/**
 * File: AgentFlowPairCounts.swift
 * -------------------------------
 * Layer: Core
 * Description: How many edges an agent flow's reader has made between each pair of names, in an open-addressing table
 *              in the thread's scratch arena keyed by the two names' numbers, hashed from a basis drawn once per process.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 26/11/2026
 */

/// The number of edges made from one name to another, Mermaid's count that numbers an edge's identifier
/// (`L_start_end_number`). The key is the two names' numbers in one 64-bit word, mixed with a basis drawn once per process
/// so that a text cannot be written to make its pairs collide; a slot holds a pair's key and its count.
struct AgentFlowPairCounts {
    private let arena: DiagramScratchArena
    private var keys: ScratchSpan<UInt64> = .empty
    private var counts: ScratchSpan<Int32> = .empty
    private var usedCount = 0

    /// A table whose slots are in `arena`, made when the first count is set.
    init(arena: DiagramScratchArena) {
        self.arena = arena
    }

    mutating func reserveCapacity(_ count: Int) {
        guard keys.isEmpty else { return }
        var slotCount = 16
        while slotCount < 2 * count + 2 { slotCount *= 2 }
        keys = arena.span(count: slotCount, repeating: Self.emptyKey)
        counts = arena.span(count: slotCount, repeating: 0)
    }

    /// The edges made from `start` to `end` so far.
    func count(_ start: Int32, _ end: Int32) -> Int {
        guard !keys.isEmpty else { return 0 }
        let key = Self.key(start, end)
        let mask = keys.count - 1
        var slot = Self.slot(of: key, mask: mask)
        while keys[slot] != Self.emptyKey {
            if keys[slot] == key { return Int(counts[slot]) }
            slot = (slot + 1) & mask
        }
        return 0
    }

    mutating func set(_ start: Int32, _ end: Int32, to count: Int) {
        if keys.isEmpty { reserveCapacity(8) }
        let key = Self.key(start, end)
        let mask = keys.count - 1
        var slot = Self.slot(of: key, mask: mask)
        while keys[slot] != Self.emptyKey, keys[slot] != key { slot = (slot + 1) & mask }
        if keys[slot] == Self.emptyKey {
            keys[slot] = key
            usedCount += 1
        }
        counts[slot] = Int32(truncatingIfNeeded: count)
        if usedCount * 2 > keys.count { grow() }
    }

    private mutating func grow() {
        let oldKeys = keys
        let oldCounts = counts
        keys = arena.span(count: oldKeys.count * 2, repeating: Self.emptyKey)
        counts = arena.span(count: oldKeys.count * 2, repeating: 0)
        let mask = keys.count - 1
        for index in 0..<oldKeys.count where oldKeys[index] != Self.emptyKey {
            var slot = Self.slot(of: oldKeys[index], mask: mask)
            while keys[slot] != Self.emptyKey { slot = (slot + 1) & mask }
            keys[slot] = oldKeys[index]
            counts[slot] = oldCounts[index]
        }
    }

    /// Names are numbered from 0, so no pair's key is all ones.
    private static let emptyKey = UInt64.max

    private static func key(_ start: Int32, _ end: Int32) -> UInt64 {
        UInt64(UInt32(bitPattern: start)) << 32 | UInt64(UInt32(bitPattern: end))
    }

    private static let basis = UInt64.random(in: 0...UInt64.max) | 1

    @inline(__always)
    private static func slot(of key: UInt64, mask: Int) -> Int {
        var mixed = (key ^ basis) &* 0x9E37_79B9_7F4A_7C15
        mixed ^= mixed >> 31
        mixed = mixed &* 0xBF58_476D_1CE4_E5B9
        mixed ^= mixed >> 29
        return Int(truncatingIfNeeded: mixed) & mask
    }

    /// `number`'s decimal digits appended to `bytes`, as Swift's interpolation writes a non-negative integer.
    static func appendDecimal(_ number: Int, to bytes: inout [UInt8]) {
        guard number >= 10 else {
            bytes.append(UInt8(48 + number))
            return
        }
        appendDecimal(number / 10, to: &bytes)
        bytes.append(UInt8(48 + number % 10))
    }
}
