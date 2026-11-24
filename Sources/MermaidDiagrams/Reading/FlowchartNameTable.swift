/**
 * File: FlowchartNameTable.swift
 * ------------------------------
 * Layer: Core
 * Description: The names a flowchart's reading meets (nodes' and groups' identifiers, edges' identifiers, classes'
 *              targets), interned by their UTF-8 bytes in an open-addressing table, each with what it names.
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

/// One name and what the reading has made of it so far.
struct FlowchartName {
    /// The name's bytes: a range of the text, or of the table's side bytes when its start is negative (`~start`).
    var range: MermaidTextRange
    var hash: UInt32
    /// The slot of `FlowchartNameTable.slots` that holds the name.
    var slot: Int32
    var nodeIndex: Int32 = -1
    /// The group ended under this identifier, by its index among the groups ended, or -1.
    var endedGroupIndex: Int32 = -1
    /// The serial of the innermost open group that listed the name as a member, -1 for none, so that a group lists a
    /// name once; a group that ends gives each name it listed back the serial it had before.
    var listingGroupSerial: Int32 = -1
    /// Whether a group that ended took the name as a member: a name belongs to the first group to end with it.
    var isTaken = false
    /// `@{ view: collapsed }` was written for the name.
    var isCollapsed = false
    /// The name was given to an edge (`e1@-->`): its `e1@{ … }` sets an edge's attributes, not a node's.
    var isEdgeIdentifier = false
}

/// Names interned by their UTF-8 bytes: FNV-1a hashes in an open-addressing table, compared byte for byte, as Pele's
/// JavaScript compares strings by their code units.
struct FlowchartNameTable {
    /// A power of two long once `reset` made it: a name's index + 1, or 0 for an empty slot.
    private(set) var slots: [Int32] = []
    var names: [FlowchartName] = []
    /// The bytes of names the reading made (a group's `subGraph<number>`) or read from a String (a `style` statement's).
    private(set) var sideBytes: [UInt8] = []

    /// Empties the table for another reading, clearing only the slots its names took; the first reset makes the slots.
    mutating func reset() {
        // A large reading's room is let go rather than kept by the thread.
        if slots.isEmpty || slots.count > 8_192 {
            slots = Array(repeating: 0, count: 64)
            names = []
            sideBytes = []
            return
        }
        for name in names { slots[Int(name.slot)] = 0 }
        names.removeAll(keepingCapacity: true)
        if !sideBytes.isEmpty { sideBytes.removeAll(keepingCapacity: true) }
    }

    /// The index of the name the text's bytes in `range` spell, added when it is new.
    @inline(__always) mutating func intern(_ range: MermaidTextRange, in bytes: FlowchartBytes) -> Int {
        let start = bytes.base + range.lowerBound
        let hash = Self.hash(start, count: range.count)
        let mask = slots.count &- 1
        var slot = Int(hash) & mask
        while case let entry = slots[slot], entry != 0 {
            let candidate = names[Int(entry &- 1)]
            if candidate.hash == hash, candidate.range.count == range.count, sameBytes(candidate.range, start, in: bytes) { return Int(entry &- 1) }
            slot = (slot &+ 1) & mask
        }
        return add(range, hash: hash, slot: slot)
    }

    /// The index of the name `text` spells, added to the side bytes when it is new.
    mutating func intern(_ text: some Collection<UInt8>, in bytes: FlowchartBytes) -> Int {
        let start = sideBytes.count
        sideBytes.append(contentsOf: text)
        let range = MermaidTextRange(start: Int(~Int32(start)), end: Int(~Int32(start)) + text.count)
        let hash = sideBytes.withUnsafeBufferPointer { side in Self.hash(side.baseAddress! + start, count: text.count) }
        let mask = slots.count &- 1
        var slot = Int(hash) & mask
        while case let entry = slots[slot], entry != 0 {
            let candidate = names[Int(entry &- 1)]
            if candidate.hash == hash, candidate.range.count == range.count,
               sideBytes.withUnsafeBufferPointer({ side in sameBytes(candidate.range, side.baseAddress! + start, in: bytes) }) {
                sideBytes.removeSubrange(start...)
                return Int(entry &- 1)
            }
            slot = (slot &+ 1) & mask
        }
        return add(range, hash: hash, slot: slot)
    }

    /// The name's text.
    func string(_ name: Int, in bytes: FlowchartBytes) -> String {
        let range = names[name].range
        guard range.start < 0 else { return bytes.string(from: range.lowerBound, to: range.upperBound) }
        let start = Int(~range.start)
        return String(decoding: sideBytes[start..<start + range.count], as: UTF8.self)
    }

    /// The name's bytes, for a model that keeps them.
    func bytes(of name: Int, in bytes: FlowchartBytes) -> [UInt8] {
        let range = names[name].range
        guard range.start < 0 else { return Array(UnsafeBufferPointer(rebasing: bytes.buffer[range.lowerBound..<range.upperBound])) }
        let start = Int(~range.start)
        return Array(sideBytes[start..<start + range.count])
    }

    private mutating func add(_ range: MermaidTextRange, hash: UInt32, slot: Int) -> Int {
        let index = names.count
        names.append(FlowchartName(range: range, hash: hash, slot: Int32(slot)))
        slots[slot] = Int32(index + 1)
        if names.count * 2 > slots.count { growSlots() }
        return index
    }

    @inline(__always) private static func hash(_ start: UnsafePointer<UInt8>, count: Int) -> UInt32 {
        var hash: UInt32 = 0x811C_9DC5
        for offset in 0..<count { hash = (hash ^ UInt32(start[offset])) &* 0x0100_0193 }
        return hash
    }

    /// Whether the name at `range` holds the `range.count` bytes at `other`.
    @inline(__always) private func sameBytes(_ range: MermaidTextRange, _ other: UnsafePointer<UInt8>, in bytes: FlowchartBytes) -> Bool {
        guard range.start < 0 else { return memcmp(bytes.base + range.lowerBound, other, range.count) == 0 }
        return sideBytes.withUnsafeBufferPointer { side in memcmp(side.baseAddress! + Int(~range.start), other, range.count) == 0 }
    }

    private mutating func growSlots() {
        let count = slots.count * 2
        slots = Array(repeating: 0, count: count)
        for index in names.indices {
            var slot = Int(names[index].hash) & (count - 1)
            while slots[slot] != 0 { slot = (slot + 1) & (count - 1) }
            slots[slot] = Int32(index + 1)
            names[index].slot = Int32(slot)
        }
    }
}
