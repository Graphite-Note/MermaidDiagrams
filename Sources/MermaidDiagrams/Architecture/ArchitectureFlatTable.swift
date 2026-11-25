/**
 * File: ArchitectureFlatTable.swift
 * ---------------------------------
 * Layer: Core
 * Description: The architecture grid's maps from a cell to the item in it and from a slide to how far it reaches, kept
 *              in flat arrays with open addressing and emptied in constant time between the parts of a container.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 25/11/2026
 */

/// A key of an `ArchitectureFlatTable`: compared whole, placed by its mixed bits.
protocol ArchitectureFlatTableKey: Equatable {
    /// The key's bits, mixed so that keys near one another land far apart.
    var mixedBits: UInt64 { get }
}

/// A map in three flat arrays (keys, values and the round each slot was written in), probed linearly from a key's mixed
/// bits, at most half full. `removeAll()` starts a new round, so the slots written before read as empty without being
/// cleared; when the round counter wraps the slots are cleared once.
struct ArchitectureFlatTable<Key: ArchitectureFlatTableKey> {
    private var keys: [Key] = []
    private var values: [Int] = []
    private var rounds: [UInt32] = []
    private var round: UInt32 = 1
    private(set) var count = 0
    private let emptyKey: Key

    /// A table whose unused slots hold `emptyKey`, which is never read as a key.
    init(emptyKey: Key) {
        self.emptyKey = emptyKey
    }

    mutating func removeAll() {
        count = 0
        round &+= 1
        if round == 0 {
            for slot in rounds.indices { rounds[slot] = 0 }
            round = 1
        }
    }

    /// The value kept under `key`, nil for none.
    func value(of key: Key) -> Int? {
        guard !keys.isEmpty else { return nil }
        let mask = keys.count - 1
        var slot = Int(truncatingIfNeeded: key.mixedBits) & mask
        while rounds[slot] == round {
            if keys[slot] == key { return values[slot] }
            slot = (slot + 1) & mask
        }
        return nil
    }

    /// Keeps `value` under `key`, in place of what was kept under it.
    mutating func set(_ value: Int, for key: Key) {
        if (count + 1) * 2 > keys.count { grow() }
        let mask = keys.count - 1
        var slot = Int(truncatingIfNeeded: key.mixedBits) & mask
        while rounds[slot] == round {
            if keys[slot] == key {
                values[slot] = value
                return
            }
            slot = (slot + 1) & mask
        }
        keys[slot] = key
        values[slot] = value
        rounds[slot] = round
        count += 1
    }

    /// Twice the slots (16 at first), the entries of this round placed again.
    private mutating func grow() {
        let oldKeys = keys
        let oldValues = values
        let oldRounds = rounds
        let slotCount = max(16, keys.count * 2)
        keys = [Key](repeating: emptyKey, count: slotCount)
        values = [Int](repeating: 0, count: slotCount)
        rounds = [UInt32](repeating: 0, count: slotCount)
        let currentRound = round
        round = 1
        count = 0
        for slot in oldKeys.indices where oldRounds[slot] == currentRound { set(oldValues[slot], for: oldKeys[slot]) }
    }
}

/// The finishing step of SplitMix64: every bit of the result depends on every bit of `bits`.
@inline(__always)
func architectureMixedBits(_ bits: UInt64) -> UInt64 {
    var mixed = bits
    mixed = (mixed ^ (mixed >> 30)) &* 0xBF58_476D_1CE4_E5B9
    mixed = (mixed ^ (mixed >> 27)) &* 0x94D0_49BB_1331_11EB
    return mixed ^ (mixed >> 31)
}

/// A grid cell, its column and row.
struct ArchitectureCellKey: ArchitectureFlatTableKey {
    let column: Int
    let row: Int

    var mixedBits: UInt64 {
        architectureMixedBits(UInt64(bitPattern: Int64(column)) &* 0x9E37_79B9_7F4A_7C15 ^ UInt64(bitPattern: Int64(row)))
    }
}

extension ArchitectureSlideKey: ArchitectureFlatTableKey {
    var mixedBits: UInt64 {
        var bits = architectureMixedBits(UInt64(bitPattern: Int64(column)) ^ UInt64(bitPattern: Int64(row)) &* 0x9E37_79B9_7F4A_7C15)
        bits = architectureMixedBits(bits ^ UInt64(bitPattern: Int64(width)) &* 0x9E37_79B9_7F4A_7C15 ^ UInt64(bitPattern: Int64(height)))
        // A step is -1, 0 or 1 along each axis.
        return architectureMixedBits(bits ^ UInt64(bitPattern: Int64(stepX + 3 * stepY + 4)))
    }
}
