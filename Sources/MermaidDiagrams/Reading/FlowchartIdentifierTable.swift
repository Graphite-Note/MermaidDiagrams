/**
 * File: FlowchartIdentifierTable.swift
 * ------------------------------------
 * Layer: Core
 * Description: The nodes a flowchart's text has named so far, found by the UTF-8 bytes of an identifier as written, so
 *              that naming a node again makes no string and hashes its bytes once.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 23/11/2026
 */

/// The node each spelling of an identifier written so far names, keyed by the identifier's bytes in the flowchart's
/// text: each key is a range of those bytes, hashed once (64-bit FNV-1a) and compared byte by byte. A spelling is added
/// once the builder knows which node it names, so a hit gives that node: equal bytes are equal strings. A miss says
/// no node is named by these bytes; another spelling may still be the same string (Swift counts some different bytes
/// beyond ASCII as equal), which the builder's dictionary of strings answers (`FlowchartDiagramBuilder`).
struct FlowchartIdentifierTable {
    private struct Key {
        let start: Int
        let end: Int
        let hash: UInt64
        let nodeIndex: Int
    }

    private var keys: [Key] = []
    /// Open addressing over `keys`: each slot holds a key's index plus one, or zero when empty; the count is a power of two
    /// at least twice the keys'. Empty while the keys are few enough to be looked through in order.
    private var slots: [Int32] = []

    /// Keys up to this many are looked through in order, without slots.
    private static let largestCountLookedThrough = 8

    /// A table for about `expectedCount` spellings, which grows past them.
    init(expectedCount: Int) {
        keys.reserveCapacity(expectedCount)
        if expectedCount > Self.largestCountLookedThrough { makeSlots(atLeast: expectedCount) }
    }

    /// 64-bit FNV-1a over the bytes from `start` to `end`, and whether they are all ASCII.
    static func hash(of bytes: [UInt8], from start: Int, to end: Int) -> (hash: UInt64, isASCII: Bool) {
        var hash: UInt64 = 0xCBF2_9CE4_8422_2325
        var highBits: UInt8 = 0
        for index in start..<end {
            let byte = bytes[index]
            highBits |= byte
            hash = (hash ^ UInt64(byte)) &* 0x0000_0100_0000_01B3
        }
        return (hash, highBits < 0x80)
    }

    /// The node the spelling from `start` to `end` of `bytes` names, when it has been added.
    func nodeIndex(in bytes: [UInt8], from start: Int, to end: Int, hash: UInt64) -> Int? {
        if slots.isEmpty {
            for key in keys where key.hash == hash && Self.bytes(bytes, from: key.start, to: key.end, equalBytesFrom: start, to: end) {
                return key.nodeIndex
            }
            return nil
        }
        let mask = slots.count - 1
        var slot = Int(truncatingIfNeeded: hash) & mask
        while slots[slot] != 0 {
            let key = keys[Int(slots[slot]) - 1]
            if key.hash == hash, Self.bytes(bytes, from: key.start, to: key.end, equalBytesFrom: start, to: end) { return key.nodeIndex }
            slot = (slot + 1) & mask
        }
        return nil
    }

    /// Adds the spelling from `start` to `end`, which `nodeIndex(in:from:to:hash:)` has just not found, as naming `nodeIndex`.
    mutating func add(from start: Int, to end: Int, hash: UInt64, nodeIndex: Int) {
        keys.append(Key(start: start, end: end, hash: hash, nodeIndex: nodeIndex))
        if slots.isEmpty {
            if keys.count > Self.largestCountLookedThrough { makeSlots(atLeast: keys.count) }
            return
        }
        if keys.count * 2 > slots.count {
            makeSlots(atLeast: keys.count)
        } else {
            place(keyAt: keys.count - 1)
        }
    }

    /// Slots for at least `count` keys, twice as many and a power of two, holding the keys there are.
    private mutating func makeSlots(atLeast count: Int) {
        var slotCount = 32
        while slotCount < count * 2 { slotCount *= 2 }
        slots = [Int32](repeating: 0, count: slotCount)
        for index in keys.indices { place(keyAt: index) }
    }

    private mutating func place(keyAt index: Int) {
        let mask = slots.count - 1
        var slot = Int(truncatingIfNeeded: keys[index].hash) & mask
        while slots[slot] != 0 { slot = (slot + 1) & mask }
        slots[slot] = Int32(truncatingIfNeeded: index + 1)
    }

    private static func bytes(_ bytes: [UInt8], from firstStart: Int, to firstEnd: Int, equalBytesFrom secondStart: Int, to secondEnd: Int) -> Bool {
        guard firstEnd - firstStart == secondEnd - secondStart else { return false }
        var offset = 0
        while firstStart + offset < firstEnd {
            if bytes[firstStart + offset] != bytes[secondStart + offset] { return false }
            offset += 1
        }
        return true
    }
}
