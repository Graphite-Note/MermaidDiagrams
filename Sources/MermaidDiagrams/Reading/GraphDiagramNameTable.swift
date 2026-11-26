/**
 * File: GraphDiagramNameTable.swift
 * ---------------------------------
 * Layer: Core
 * Description: The names a state, class, entity relationship or requirement diagram's reading meets, interned to
 *              small numbers by their bytes in an open-addressing table when the text is ASCII, or as Strings
 *              otherwise, so that two names are one exactly when 0.7.0's String keys made them one.
 *
 * Authors: Bahey Shalash
 * Version: 0.2
 * Date: 26/11/2026
 */

#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif

/// Names interned to numbers counted from 0 in the order they are first met. In a text of ASCII bytes alone Swift's
/// String equality is byte equality, so names are hashed and compared by their bytes; in any other text two spellings
/// Swift holds equal (a decomposed letter and its composed form, two invalid sequences each read as U+FFFD) are one
/// name, so names are kept as Strings, as 0.7.0's dictionaries keyed them. The hash is FNV-1a on 64 bits from a basis
/// drawn once per process, so that a text cannot be written to make its names collide.
struct GraphDiagramNameTable {
    private let isASCII: Bool
    /// A power of two long once a name is added: a name's number + 1, or 0 for an empty slot.
    private var slots: [Int32] = []
    private var hashes: [UInt64] = []
    private var ranges: [MermaidTextRange] = []
    private var numberByString: [String: Int32] = [:]
    private(set) var count = 0

    /// A table for the names of a text, ASCII or not (`isASCII(_:)`).
    init(isASCII: Bool) {
        self.isASCII = isASCII
    }

    /// Room for `count` names before the table grows.
    mutating func reserveCapacity(_ count: Int) {
        guard isASCII else { return numberByString.reserveCapacity(count) }
        hashes.reserveCapacity(count)
        ranges.reserveCapacity(count)
        var slotCount = Self.leastSlotCount
        while slotCount < 2 * count + 2 { slotCount *= 2 }
        if self.count == 0, slotCount > slots.count { slots = Array(repeating: 0, count: slotCount) }
    }

    /// The number of the name `bytes[range]` spells, and whether it was new.
    mutating func intern(_ bytes: UnsafeBufferPointer<UInt8>, _ range: MermaidTextRange) -> (number: Int, isNew: Bool) {
        guard isASCII else { return internString(String(decoding: UnsafeBufferPointer(rebasing: bytes[range.lowerBound..<range.upperBound]), as: UTF8.self)) }
        if slots.isEmpty { slots = Array(repeating: 0, count: Self.leastSlotCount) }
        let hash = Self.hash(bytes, range)
        let mask = slots.count &- 1
        var slot = Int(truncatingIfNeeded: hash) & mask
        while case let entry = slots[slot], entry != 0 {
            let number = Int(entry &- 1)
            if hashes[number] == hash, Self.same(bytes, ranges[number], range) { return (number, false) }
            slot = (slot &+ 1) & mask
        }
        let number = count
        hashes.append(hash)
        ranges.append(range)
        count += 1
        slots[slot] = Int32(number + 1)
        if count * 2 > slots.count { growSlots() }
        return (number, true)
    }

    /// The number of the name `name` spells, for a name a text beyond ASCII trims as Foundation trims text, and whether
    /// it was new. Only such a text's table, which keys its names by Strings, is given one.
    mutating func intern(_ name: String) -> (number: Int, isNew: Bool) {
        precondition(!isASCII, "a name is interned as a String only in a text beyond ASCII")
        return internString(name)
    }

    private mutating func internString(_ name: String) -> (number: Int, isNew: Bool) {
        if let number = numberByString[name] { return (Int(number), false) }
        let number = count
        numberByString[name] = Int32(number)
        count += 1
        return (number, true)
    }

    private static let leastSlotCount = 32

    /// The process's hash basis: FNV-1a's offset basis mixed with a random number drawn once.
    private static let hashBasis: UInt64 = 0xCBF2_9CE4_8422_2325 ^ UInt64.random(in: 0...UInt64.max)

    @inline(__always) private static func hash(_ bytes: UnsafeBufferPointer<UInt8>, _ range: MermaidTextRange) -> UInt64 {
        var hash = hashBasis
        var index = range.lowerBound
        while index < range.upperBound {
            hash = (hash ^ UInt64(bytes[index])) &* 0x0000_0100_0000_01B3
            index &+= 1
        }
        return hash ^ (hash >> 29)
    }

    @inline(__always) private static func same(_ bytes: UnsafeBufferPointer<UInt8>, _ known: MermaidTextRange, _ range: MermaidTextRange) -> Bool {
        guard known.count == range.count else { return false }
        guard let base = bytes.baseAddress, range.count > 0 else { return true }
        return memcmp(base + known.lowerBound, base + range.lowerBound, range.count) == 0
    }

    private mutating func growSlots() {
        let slotCount = slots.count * 2
        slots = Array(repeating: 0, count: slotCount)
        for number in 0..<hashes.count {
            var slot = Int(truncatingIfNeeded: hashes[number]) & (slotCount - 1)
            while slots[slot] != 0 { slot = (slot + 1) & (slotCount - 1) }
            slots[slot] = Int32(number + 1)
        }
    }

    /// Whether every byte of `bytes` is ASCII, sixteen at a time.
    static func isASCII(_ bytes: UnsafeBufferPointer<UInt8>) -> Bool {
        guard let base = bytes.baseAddress else { return true }
        var combined = SIMD16<UInt8>(repeating: 0)
        var index = 0
        while index + 16 <= bytes.count {
            combined |= UnsafeRawPointer(base + index).loadUnaligned(as: SIMD16<UInt8>.self)
            index += 16
        }
        var tail: UInt8 = 0
        while index < bytes.count {
            tail |= bytes[index]
            index += 1
        }
        return (combined.max() | tail) < 0x80
    }
}

extension GraphDiagramNameTable {
    /// The table emptied for the names of another text, ASCII or not, keeping its room for them unless a long text left
    /// more than `largestKeptSlotCount` slots: so that a thread's readings reuse one table.
    mutating func reset(isASCII: Bool) {
        var keptSlots = slots.count > Self.largestKeptSlotCount ? [] : slots
        var keptHashes = hashes.capacity > Self.largestKeptSlotCount ? [] : hashes
        var keptRanges = ranges.capacity > Self.largestKeptSlotCount ? [] : ranges
        let hadStrings = !numberByString.isEmpty
        var keptStrings = hadStrings && numberByString.capacity > Self.largestKeptSlotCount ? [:] : numberByString
        self = GraphDiagramNameTable(isASCII: isASCII)
        if !keptSlots.isEmpty { keptSlots.withUnsafeMutableBufferPointer { slots in slots.update(repeating: 0) } }
        keptHashes.removeAll(keepingCapacity: true)
        keptRanges.removeAll(keepingCapacity: true)
        if hadStrings { keptStrings.removeAll(keepingCapacity: true) }
        slots = keptSlots
        hashes = keptHashes
        ranges = keptRanges
        numberByString = keptStrings
    }

    private static let largestKeptSlotCount = 8_192
}
