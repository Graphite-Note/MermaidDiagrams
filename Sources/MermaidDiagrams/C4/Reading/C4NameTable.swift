/**
 * File: C4NameTable.swift
 * -----------------------
 * Layer: Core
 * Description: The names a C4 diagram's reading meets (aliases, relations' ends, named arguments' keys), interned by
 *              their bytes in an open-addressing table, or as Strings in a text past ASCII, so that two names are one
 *              exactly when 0.7.0's String keys were; names made to collide turn the table to a seeded hash, so that
 *              interning stays linear.
 *
 * Authors: Bahey Shalash
 * Version: 0.2
 * Date: 25/11/2026
 */

/// Names interned to small numbers. In a text of ASCII bytes alone, Swift's String equality is byte equality, so names
/// are hashed (FNV-1a) and compared by their bytes; in any other text two spellings Swift holds equal (a decomposed
/// letter and its composed form, the Kelvin sign and `K`) are one name, so names are kept as Strings, as 0.7.0's
/// dictionaries keyed them.
///
/// FNV-1a is fast but easy to make collide, and colliding names would make each name probe every one before it: a probe
/// longer than `longestProbeCount` turns the table to the standard library's hash, seeded anew in each process
/// (`Hasher`), which no text can be written to collide in, and every name is placed again by it. Numbers stay those
/// given in the order names were met, so what a diagram reads never depends on the hash.
struct C4NameTable {
    private let isASCII: Bool
    /// A power of two long: a name's number + 1, or 0 for an empty slot.
    private var slots: [Int32]
    private var ranges: [(start: Int, end: Int)] = []
    private var hashes: [UInt32] = []
    private var numberByString: [String: Int32] = [:]
    private(set) var count = 0
    /// Whether names are hashed by `Hasher` instead of FNV-1a.
    private(set) var isSeeded = false
    /// How many slots every interning looked at, for the tests that keep it linear.
    private(set) var probeCount = 0

    /// The longest probe FNV-1a is kept for: at most half the slots are full, so a longer one is all but never met unless
    /// names were made to collide.
    static let longestProbeCount = 32

    /// A table for the names of `bytes`, which says whether they are all ASCII.
    init(bytes: [UInt8]) {
        isASCII = Self.isASCII(bytes)
        slots = []
    }

    /// Room for `count` names before the table grows.
    mutating func reserveCapacity(_ count: Int) {
        guard isASCII else {
            numberByString.reserveCapacity(count)
            return
        }
        ranges.reserveCapacity(count)
        hashes.reserveCapacity(count)
        var slotCount = max(slots.count, Self.leastSlotCount)
        while slotCount < 2 * count + 2 { slotCount *= 2 }
        if slotCount > slots.count, self.count == 0 { slots = Array(repeating: 0, count: slotCount) }
    }

    /// The number of the name `bytes[start..<end]` spells, made when it is new.
    mutating func intern(_ bytes: UnsafeBufferPointer<UInt8>, from start: Int, to end: Int) -> Int32 {
        guard isASCII else {
            let name = String(decoding: UnsafeBufferPointer(rebasing: bytes[start..<end]), as: UTF8.self)
            if let number = numberByString[name] { return number }
            let number = Int32(count)
            numberByString[name] = number
            count += 1
            return number
        }
        if slots.isEmpty { slots = Array(repeating: 0, count: Self.leastSlotCount) }
        let hash = hash(bytes, from: start, to: end)
        var mask = slots.count - 1
        var slot = Int(hash) & mask
        var probeLength = 0
        while slots[slot] != 0 {
            let number = Int(slots[slot] - 1)
            if hashes[number] == hash, Self.same(bytes, ranges[number], start, end) { return Int32(number) }
            slot = (slot + 1) & mask
            probeLength += 1
            probeCount += 1
            if probeLength > Self.longestProbeCount, !isSeeded {
                rehashSeeded(bytes)
                return intern(bytes, from: start, to: end)
            }
        }
        let number = count
        ranges.append((start, end))
        hashes.append(hash)
        count += 1
        if count * 2 > slots.count {
            grow()
            mask = slots.count - 1
            slot = Int(hash) & mask
            while slots[slot] != 0 {
                slot = (slot + 1) & mask
                probeCount += 1
            }
        }
        slots[slot] = Int32(number + 1)
        return Int32(number)
    }

    private static let leastSlotCount = 64

    /// Every name hashed again by `Hasher` and placed in the slots again, in the order of their numbers.
    private mutating func rehashSeeded(_ bytes: UnsafeBufferPointer<UInt8>) {
        isSeeded = true
        for number in 0..<count { hashes[number] = hash(bytes, from: ranges[number].start, to: ranges[number].end) }
        slots = Array(repeating: 0, count: slots.count)
        let mask = slots.count - 1
        for number in 0..<count {
            var slot = Int(hashes[number]) & mask
            while slots[slot] != 0 {
                slot = (slot + 1) & mask
                probeCount += 1
            }
            slots[slot] = Int32(number + 1)
        }
    }

    private mutating func grow() {
        slots = Array(repeating: 0, count: slots.count * 2)
        let mask = slots.count - 1
        // The newest name is placed by the caller.
        for number in 0..<(count - 1) {
            var slot = Int(hashes[number]) & mask
            while slots[slot] != 0 {
                slot = (slot + 1) & mask
                probeCount += 1
            }
            slots[slot] = Int32(number + 1)
        }
    }

    private static func same(_ bytes: UnsafeBufferPointer<UInt8>, _ known: (start: Int, end: Int), _ start: Int, _ end: Int) -> Bool {
        guard known.end - known.start == end - start else { return false }
        var offset = 0
        while offset < end - start {
            if bytes[known.start + offset] != bytes[start + offset] { return false }
            offset += 1
        }
        return true
    }

    /// The name's hash: FNV-1a, or `Hasher`'s once the table is seeded.
    private func hash(_ bytes: UnsafeBufferPointer<UInt8>, from start: Int, to end: Int) -> UInt32 {
        guard isSeeded else { return Self.fowlerNollVoHash(bytes, from: start, to: end) }
        var hasher = Hasher()
        hasher.combine(bytes: UnsafeRawBufferPointer(UnsafeBufferPointer(rebasing: bytes[start..<end])))
        return UInt32(truncatingIfNeeded: hasher.finalize())
    }

    private static func fowlerNollVoHash(_ bytes: UnsafeBufferPointer<UInt8>, from start: Int, to end: Int) -> UInt32 {
        var hash: UInt32 = 2_166_136_261
        for index in start..<end { hash = (hash ^ UInt32(bytes[index])) &* 16_777_619 }
        return hash
    }

    private static func isASCII(_ bytes: [UInt8]) -> Bool {
        bytes.withUnsafeBufferPointer { buffer in
            var combined: UInt8 = 0
            for byte in buffer { combined |= byte }
            return combined < 0x80
        }
    }
}
